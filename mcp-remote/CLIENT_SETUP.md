# DeepSeek MCP — setup for users on other devices

You've been given access to a private DeepSeek-backed MCP service. It exposes one tool, `ask_deepseek`, which forwards your prompt to DeepSeek's API through a private gateway. Use it from Claude Desktop, claude.ai (web), or any MCP-aware client.

## What you need

- A **bearer key** (a 64-char hex string). The owner will send this to you via a secure channel — **not** in plain email or chat.
- **Node.js** installed if you'll use Claude Desktop (https://nodejs.org — install the LTS).

---

## Claude Desktop — macOS

1. Open (or create) this file:
   `~/Library/Application Support/Claude/claude_desktop_config.json`

2. Paste the block below, replacing `PASTE_YOUR_KEY_HERE` with the key you were sent. If the file already has an `mcpServers` block, merge the `deephermes` entry into it instead of replacing the whole file.

```json
{
  "mcpServers": {
    "deephermes": {
      "command": "npx",
      "args": [
        "-y", "mcp-remote",
        "https://deephermes-mcp-116263110764.us-central1.run.app/mcp",
        "--header", "Authorization:Bearer PASTE_YOUR_KEY_HERE"
      ]
    }
  }
}
```

3. Fully quit Claude Desktop (**Cmd+Q** — not just close the window) and reopen.
4. In a new chat, ask *"What tools do you have?"* — `ask_deepseek` should be listed.

## Claude Desktop — Windows

Same JSON. Config file lives at:

```
%APPDATA%\Claude\claude_desktop_config.json
```

Make sure `node` and `npx` are on your PATH (install Node.js LTS if missing). Restart Claude Desktop after editing.

## Claude Desktop — Linux

Same JSON. Config file lives at:

```
~/.config/Claude/claude_desktop_config.json
```

Restart Claude Desktop.

## claude.ai (web)

*Requires a Claude Pro / Team / Enterprise plan with Custom Connectors enabled.*

1. Open https://claude.ai
2. Profile menu → **Settings** → **Connectors** (older UI: **Integrations**)
3. **Add custom connector**
4. URL: `https://deephermes-mcp-116263110764.us-central1.run.app/mcp`
5. Authentication: **Bearer token**
6. Paste your key
7. Save, then start a new chat

## Claude iOS / Android

Mobile Claude apps don't currently support custom MCP servers. Use claude.ai in mobile Safari/Chrome — the web connector path works there.

## Cursor

`~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "deephermes": {
      "url": "https://deephermes-mcp-116263110764.us-central1.run.app/mcp",
      "headers": { "Authorization": "Bearer PASTE_YOUR_KEY_HERE" }
    }
  }
}
```

Restart Cursor.

---

## Using `ask_deepseek` in a chat

After setup, Claude/Cursor can call the tool on your behalf. You can ask things like:

- *"Use ask_deepseek to give me a second opinion on this code."*
- *"Ask DeepSeek's reasoner model: if a train leaves Chicago at 3pm…"* — Claude will pass `model: deepseek-reasoner`.

Parameters Claude can use:

- `prompt` (required) — your question/instruction.
- `model` — `deepseek-chat` (V3, fast, default) or `deepseek-reasoner` (R1, slower, shows reasoning).
- `system` — optional system message.
- `max_tokens` — default 1024.

---

## Security

- Your bearer key is the equivalent of a password. **Don't paste it anywhere shared** (chat transcripts, public repos, screenshots).
- If you suspect the key has leaked, contact the owner — they'll rotate it.
- The underlying gateway is publicly callable. Don't pass sensitive prompts.
- The owner can see request volume per key (when logging is enabled) but not the prompts themselves.
