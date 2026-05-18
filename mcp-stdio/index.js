#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const GATEWAY_URL = process.env.DEEPSEEK_GATEWAY_URL;
const DEFAULT_MODEL = process.env.DEFAULT_MODEL || "deepseek-chat";

if (!GATEWAY_URL) {
  console.error("DEEPSEEK_GATEWAY_URL env var is required");
  process.exit(1);
}

const server = new Server(
  { name: "deephermes-mcp", version: "0.1.0" },
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
          prompt: {
            type: "string",
            description: "The user prompt",
          },
          system: {
            type: "string",
            description: "Optional system message",
          },
          model: {
            type: "string",
            description: "Model name. Defaults to deepseek-chat (V3).",
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

const transport = new StdioServerTransport();
await server.connect(transport);
// stdout is reserved for JSON-RPC; logs go to stderr
console.error(`deephermes-mcp ready (gateway=${GATEWAY_URL})`);
