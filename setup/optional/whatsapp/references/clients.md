# MCP client registration

Always use the absolute MCP server binary path and the same `WHATSAPP_API_KEY` configured in the bridge. Back up existing configuration and preserve unrelated servers.

## Claude Code

If the `claude` CLI is installed, inspect `claude mcp list` and use its current `mcp add` syntax. Remove/replace only the `whatsapp-mcp` registration.

```text
claude mcp add whatsapp-mcp <absolute-binary> -s user \
  -e WHATSAPP_API_KEY=<secret> \
  -e API_BASE_URL=http://localhost:8080/api
```

Run `claude mcp --help` when the installed CLI rejects the syntax.

## Claude Desktop and Cursor JSON

Merge one entry under `mcpServers`:

```json
{
  "mcpServers": {
    "whatsapp-mcp": {
      "command": "/absolute/path/to/whatsapp-mcp",
      "env": {
        "WHATSAPP_API_KEY": "<secret>",
        "API_BASE_URL": "http://localhost:8080/api"
      }
    }
  }
}
```

On Windows, serialize JSON with a parser rather than hand-escaping backslashes. Back up, parse, update only `mcpServers.whatsapp-mcp`, serialize, parse again, and roll back on failure. Do not add both a JSON registration and an MCPB extension.

## OpenAI Codex

Prefer the current CLI because it handles TOML safely:

```text
codex mcp remove whatsapp-mcp
codex mcp add whatsapp-mcp \
  --env WHATSAPP_API_KEY=<secret> \
  --env API_BASE_URL=http://localhost:8080/api \
  -- <absolute-binary>
codex mcp list
```

If direct editing is necessary, preserve unrelated configuration:

```toml
[mcp_servers.whatsapp-mcp]
command = "<absolute-binary>"
args = []

[mcp_servers.whatsapp-mcp.env]
WHATSAPP_API_KEY = "<secret>"
API_BASE_URL = "http://localhost:8080/api"
```

Codex reads global configuration from `~/.codex/config.toml`; a trusted project can also use `.codex/config.toml`. Restart or refresh the Codex surface after registration and confirm the server with `/mcp` or the MCP settings UI where available.

Official Codex reference: `https://developers.openai.com/codex/mcp/`.

## Claude Desktop MCPB

MCPB is optional and replaces the Desktop JSON entry. Follow the current specification at `https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md` and validate with the installed MCPB CLI.

As of the August 2026 audit, use manifest version `0.3`:

```json
{
  "manifest_version": "0.3",
  "name": "whatsapp-mcp",
  "display_name": "WhatsApp (vimigo)",
  "version": "1.0.0",
  "description": "Read and send WhatsApp through a local bridge.",
  "author": { "name": "vimigo-lee" },
  "server": {
    "type": "binary",
    "entry_point": "server/whatsapp-mcp",
    "mcp_config": {
      "command": "server/whatsapp-mcp",
      "env": {
        "WHATSAPP_API_KEY": "${user_config.api_key}",
        "API_BASE_URL": "${user_config.api_base_url}"
      }
    }
  },
  "user_config": {
    "api_key": {
      "type": "string",
      "title": "Bridge API key",
      "sensitive": true,
      "required": true
    },
    "api_base_url": {
      "type": "string",
      "title": "Bridge URL",
      "default": "http://localhost:8080/api",
      "required": false
    }
  }
}
```

Use platform-specific packages or overrides for Windows `.exe` binaries and CPU architectures. Validate the manifest, pack the bundle, and let the user approve the Desktop install and secret entry. Do not place the API key on the clipboard without explicit consent.
