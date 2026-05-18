# deephermes-mcp-remote

A Streamable-HTTP MCP server, deployed to Cloud Run. It calls your existing `deephermes` gateway (which holds the DeepSeek API key) and exposes `ask_deepseek` as an MCP tool to remote clients authenticated by Bearer token.

```
[ Friend's Claude Desktop / Cursor ]──HTTPS+Bearer──>[ deephermes-mcp ]──HTTP──>[ deephermes gateway ]──>DeepSeek API
```

## Deploy

```
cd ~/hermes-mcp-remote
./deploy.sh
```

First run: generates 3 random client keys and stores them in Secret Manager secret `MCPClientKeys`. Save them when the script prints them — you can't fetch the *historical* output again, but the secret is readable via `gcloud secrets versions access latest --secret=MCPClientKeys`.

## How a friend uses it

### Option 1: Cursor

In `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "deephermes": {
      "url": "https://deephermes-mcp-116263110764.us-central1.run.app/mcp",
      "headers": {
        "Authorization": "Bearer <client-key>"
      }
    }
  }
}
```

### Option 2: Claude Desktop (varies by version)

Recent Claude Desktop versions support remote MCP servers. The config schema is moving, so check the official MCP docs for the exact JSON shape your version expects. If your version only supports stdio, fall back to Option 3.

### Option 3: Local stdio shim → remote HTTP (always works)

If a client only supports stdio MCP, run `mcp-remote` locally as a tiny proxy:

```json
{
  "mcpServers": {
    "deephermes": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://deephermes-mcp-116263110764.us-central1.run.app/mcp", "--header", "Authorization:Bearer <client-key>"]
    }
  }
}
```

`mcp-remote` is a small community proxy from `npm` that any stdio client can launch; it forwards JSON-RPC over the network to a remote Streamable-HTTP server.

## Operating

**List current client keys (be careful — secrets will print to your terminal):**

```
gcloud secrets versions access latest --secret=MCPClientKeys --project=leadsync-489921
```

**Add a new key (preserves existing ones):**

```
NEW=$(openssl rand -hex 32)
OLD=$(gcloud secrets versions access latest --secret=MCPClientKeys --project=leadsync-489921)
printf '%s,%s' "$OLD" "$NEW" | gcloud secrets versions add MCPClientKeys --data-file=- --project=leadsync-489921
# Tell the new user: Bearer $NEW
```

The Cloud Run service reads `MCPClientKeys:latest` at startup. Cloud Run reads the new version automatically on its next cold start; to push the new keys to active instances immediately:

```
gcloud run services update deephermes-mcp --region us-central1 --project leadsync-489921
```

**Revoke a key:** edit the secret to a list without that key, then push as a new version. Same procedure.

## Costs

Scale-to-zero, same as the gateway. Free tier swallows personal use. Each MCP call funnels through the gateway → DeepSeek bills your account in the usual way.
