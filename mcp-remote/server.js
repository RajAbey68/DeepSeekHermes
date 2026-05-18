import express from "express";
import { randomUUID } from "node:crypto";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  isInitializeRequest,
} from "@modelcontextprotocol/sdk/types.js";

const PORT = parseInt(process.env.PORT || "8080", 10);
const GATEWAY_URL = process.env.DEEPSEEK_GATEWAY_URL;
const DEFAULT_MODEL = process.env.DEFAULT_MODEL || "deepseek-chat";

// Comma-separated list of allowed client bearer tokens, sourced from Secret Manager
// at deploy time via --update-secrets MCP_CLIENT_KEYS=MCPClientKeys:latest
const ALLOWED_KEYS = (process.env.MCP_CLIENT_KEYS || "")
  .split(",")
  .map((k) => k.trim())
  .filter(Boolean);

if (!GATEWAY_URL) {
  console.error("DEEPSEEK_GATEWAY_URL env var is required");
  process.exit(1);
}
if (ALLOWED_KEYS.length === 0) {
  console.error("MCP_CLIENT_KEYS env var is required (comma-separated allowed bearer tokens)");
  process.exit(1);
}

function makeMcpServer() {
  const server = new Server(
    { name: "deephermes-mcp-remote", version: "0.1.0" },
    { capabilities: { tools: {} } }
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [
      {
        name: "ask_deepseek",
        description:
          "Ask DeepSeek (an open-source LLM family) via a private gateway, and return its reply. " +
          "Reach for this when: " +
          "(a) you want a second opinion to compare against your own answer; " +
          "(b) the question involves math, logic puzzles, or multi-step reasoning — pass model='deepseek-reasoner'; " +
          "(c) code review or an alternative implementation would help; " +
          "(d) general factual questions where DeepSeek's training may add coverage. " +
          "Models: 'deepseek-chat' (V3, fast, default) or 'deepseek-reasoner' (R1, slower, explicit chain-of-thought). " +
          "The gateway is publicly callable — do not pass sensitive content.",
        inputSchema: {
          type: "object",
          properties: {
            prompt: { type: "string", description: "The user prompt" },
            system: { type: "string", description: "Optional system message" },
            model: {
              type: "string",
              description: "Model name. Default deepseek-chat (V3).",
              enum: ["deepseek-chat", "deepseek-reasoner"],
            },
            max_tokens: {
              type: "number",
              description: "Maximum completion tokens. Default 1024.",
            },
          },
          required: ["prompt"],
        },
      },
    ],
  }));

  server.setRequestHandler(CallToolRequestSchema, async (req) => {
    if (req.params.name !== "ask_deepseek") {
      return {
        content: [{ type: "text", text: `Unknown tool: ${req.params.name}` }],
        isError: true,
      };
    }
    const args = req.params.arguments ?? {};
    const messages = [];
    if (args.system) messages.push({ role: "system", content: args.system });
    messages.push({ role: "user", content: args.prompt });

    const body = {
      model: args.model || DEFAULT_MODEL,
      messages,
      max_tokens: args.max_tokens ?? 1024,
    };

    try {
      const res = await fetch(`${GATEWAY_URL}/ai/chat/completions`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (!res.ok) {
        const text = await res.text();
        return {
          content: [{ type: "text", text: `Gateway error ${res.status}: ${text}` }],
          isError: true,
        };
      }
      const data = await res.json();
      const content = data.choices?.[0]?.message?.content ?? "(empty response)";
      return { content: [{ type: "text", text: content }] };
    } catch (err) {
      return {
        content: [{ type: "text", text: `Error calling gateway: ${err.message}` }],
        isError: true,
      };
    }
  });

  return server;
}

const app = express();
app.use(express.json({ limit: "1mb" }));

// CORS for browser-based MCP clients
app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS");
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, Mcp-Session-Id, Last-Event-Id, Mcp-Protocol-Version"
  );
  res.setHeader(
    "Access-Control-Expose-Headers",
    "Mcp-Session-Id, Last-Event-Id, Mcp-Protocol-Version, WWW-Authenticate"
  );
  if (req.method === "OPTIONS") return res.status(204).end();
  next();
});

// Bearer auth
function requireBearer(req, res, next) {
  const auth = req.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : null;
  if (!token || !ALLOWED_KEYS.includes(token)) {
    return res.status(401).json({
      jsonrpc: "2.0",
      error: { code: -32001, message: "Unauthorized" },
      id: null,
    });
  }
  next();
}

app.get("/health", (req, res) => res.json({ status: "ok" }));

// Session storage: sessionId -> transport
const transports = new Map();

app.post("/mcp", requireBearer, async (req, res) => {
  const sessionId = req.headers["mcp-session-id"];
  try {
    let transport = sessionId ? transports.get(sessionId) : null;

    if (!transport) {
      if (!isInitializeRequest(req.body)) {
        return res.status(400).json({
          jsonrpc: "2.0",
          error: { code: -32000, message: "Bad Request: no session and not an initialize request" },
          id: null,
        });
      }
      transport = new StreamableHTTPServerTransport({
        sessionIdGenerator: () => randomUUID(),
        onsessioninitialized: (sid) => {
          transports.set(sid, transport);
        },
      });
      transport.onclose = () => {
        if (transport.sessionId) transports.delete(transport.sessionId);
      };
      const server = makeMcpServer();
      await server.connect(transport);
    }

    await transport.handleRequest(req, res, req.body);
  } catch (err) {
    console.error("MCP POST error:", err);
    if (!res.headersSent) {
      res.status(500).json({
        jsonrpc: "2.0",
        error: { code: -32603, message: "Internal server error" },
        id: null,
      });
    }
  }
});

app.get("/mcp", requireBearer, async (req, res) => {
  const sessionId = req.headers["mcp-session-id"];
  const transport = sessionId && transports.get(sessionId);
  if (!transport) return res.status(404).send("Session not found");
  await transport.handleRequest(req, res);
});

app.delete("/mcp", requireBearer, async (req, res) => {
  const sessionId = req.headers["mcp-session-id"];
  const transport = sessionId && transports.get(sessionId);
  if (!transport) return res.status(404).send("Session not found");
  await transport.handleRequest(req, res);
});

app.listen(PORT, () => {
  console.log(`deephermes-mcp-remote listening on :${PORT}`);
  console.log(`  gateway: ${GATEWAY_URL}`);
  console.log(`  allowed client keys: ${ALLOWED_KEYS.length}`);
});

process.on("SIGTERM", async () => {
  console.log("SIGTERM — closing transports");
  for (const t of transports.values()) {
    try { await t.close(); } catch {}
  }
  process.exit(0);
});
