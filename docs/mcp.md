# Model Context Protocol (MCP)

Dawarich exposes an experimental, read-only [Model Context Protocol](https://modelcontextprotocol.io/) endpoint at:

```text
https://YOUR_DAWARICH_HOST/api/v1/mcp
```

The endpoint uses the Streamable HTTP transport and the same API key authentication and data-access rules as the rest of the Dawarich API.

## Available tools

| Tool | Description |
|---|---|
| `get_timeline` | Returns visits and journeys for an ISO 8601 time range of up to 7 local calendar days and at most 500 entries. |
| `get_latest_location` | Returns the newest visible, non-anomalous location point. |

Both tools are read-only. They only return data belonging to the API-key owner and respect the owner's plan data window.

## Authentication

Create or copy your Dawarich API key from the account settings, then send it as a bearer token:

> **Important:** The current Dawarich API key is not MCP-scoped. Although the MCP tools are read-only, the same credential can authorize write operations through other Dawarich API endpoints. Only configure it in MCP clients you fully trust, and rotate it if that client or configuration is exposed.

```http
Authorization: Bearer YOUR_DAWARICH_API_KEY
```

Treat the key like a password. Do not put it in a shared client configuration, commit it to source control, or include it in support logs.

## Client configuration

The exact configuration format depends on the MCP client. A client that accepts Streamable HTTP servers and custom headers typically uses settings equivalent to:

```json
{
  "mcpServers": {
    "dawarich": {
      "type": "http",
      "url": "https://YOUR_DAWARICH_HOST/api/v1/mcp",
      "headers": {
        "Authorization": "Bearer YOUR_DAWARICH_API_KEY"
      }
    }
  }
}
```

Use HTTPS whenever the client connects over a network.

## Protocol smoke test

```bash
curl --request POST \
  --url https://YOUR_DAWARICH_HOST/api/v1/mcp \
  --header 'Authorization: Bearer YOUR_DAWARICH_API_KEY' \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json' \
  --data '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-11-25",
      "capabilities": {},
      "clientInfo": { "name": "curl", "version": "1.0" }
    }
  }'
```

A successful response contains `serverInfo.name` set to `dawarich` and advertises the `tools` capability.

## Deployment notes

- The MCP endpoint is stateless and works with multi-process Puma and multiple application instances; it does not require sticky sessions.
- Host validation follows Dawarich's existing Rails `APPLICATION_HOSTS` configuration. Ensure the public hostname is already listed there, as required for normal Dawarich requests.
- Existing API rate limits apply to MCP requests.
- The MVP does not implement MCP OAuth discovery. Clients authenticate with an existing Dawarich API key.
