// One-shot end-to-end test of the deployed deephermes-mcp HTTP MCP server.
// Reads MCP_URL and MCP_KEY from env.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

const url = process.env.MCP_URL || "https://deephermes-mcp-116263110764.us-central1.run.app/mcp";
const key = process.env.MCP_KEY;
if (!key) {
  console.error("MCP_KEY env var required");
  process.exit(1);
}

const transport = new StreamableHTTPClientTransport(new URL(url), {
  requestInit: { headers: { Authorization: `Bearer ${key}` } },
});

const client = new Client({ name: "smoke-test", version: "0.1" }, { capabilities: {} });

console.log(">> connect()");
await client.connect(transport);
console.log("   connected");

console.log(">> listTools()");
const tools = await client.listTools();
console.log("   tools:", tools.tools.map((t) => t.name).join(", "));

console.log(">> callTool('ask_deepseek')");
const result = await client.callTool({
  name: "ask_deepseek",
  arguments: { prompt: "What is 7 times 8? Reply with only the number.", max_tokens: 20 },
});
console.log("   result content:", JSON.stringify(result.content));

await client.close();
console.log(">> done");
