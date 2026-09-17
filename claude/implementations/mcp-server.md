# MCP Server Implementation

**Date:** 2026-09-17
**Feature:** Model Context Protocol endpoint so AI agents can look up commodity codes in a conversation

## Overview

Tariffik now speaks the Model Context Protocol at `POST /mcp`. An agent such as
Claude Code, Claude Desktop, or Cursor connects with an ordinary Tariffik API key
and gets five tools: two that produce a commodity code suggestion, two that read
the UK Trade Tariff directly, and one that reads back what the account has
already looked up.

The use case that drove it: working through order and shipping emails in a chat
session. The agent reads the mail itself through whatever email integration it
has, pulls the product link out of each message, calls `lookup_from_url`, and the
results land in the Tariffik account ready for the existing CSV export.

This closes the "MCP Server for Agentic Integration" block in `TODO.md`.

## Design Decisions

**Inside Rails, not a separate process.** A standalone stdio server wrapping the
public REST API would have been quicker, but it would run only on one machine,
and URL lookups would have to go through the async batch endpoint and poll. A
controller in the app reaches the services directly, deploys with everything
else, and works for any account rather than one laptop.

**URL lookups are synchronous.** `POST /api/v1/commodity-codes/suggest-from-url`
queues a batch job and hands back a poll URL, which suits a server-to-server
integration. An agent mid-conversation wants the answer in the same turn.
`ApiCommodityService#suggest_from_url` was already synchronous; only the public
endpoint wrapped it in a job, so the MCP tool calls the service.

**Existing API keys, not a new credential.** *(Superseded on 2026-09-17 — see
`mcp-oauth-authorization.md`.)* `/mcp` originally inherited
`Api::V1::BaseController` so an MCP client was just another API consumer. It is
now an OAuth 2.1 resource server and no longer accepts API keys; they remain the
credential for `/api/v1`.

**Stateless.** No session id is issued, so any request can be served by any
process and nothing has to be held between calls.

**No OAuth advertised.** Auth failures return a bare 401. Adding a
`WWW-Authenticate` header would send MCP clients into an OAuth discovery flow
this server does not implement. A test guards this.

**Only tool calls are billed.** `initialize`, `tools/list`, and `ping` are
protocol chatter. `increment_usage` is overridden to fire only when a tool
actually ran, so a client reconnecting does not eat the daily allowance.

**Tool failures are results, not protocol errors.** A page that will not scrape
comes back as `isError: true` with an explanation in the content block, so the
model can read it and try `lookup_from_description` instead. JSON-RPC error codes
are reserved for malformed requests and unknown methods.

## Database Changes

None. Saved lookups reuse the existing `product_lookups` table.

## New Files Created

| File | Purpose |
|------|---------|
| `app/controllers/mcp/server_controller.rb` | JSON-RPC 2.0 over Streamable HTTP: `initialize`, `ping`, `tools/list`, `tools/call`, notifications |
| `app/services/mcp/tool_catalog.rb` | Tool definitions and input schemas, protocol version negotiation, server instructions |
| `app/services/mcp/tool_runner.rb` | Executes each tool against `ApiCommodityService`, `TariffLookupService`, and `ProductLookup` |
| `test/controllers/mcp/server_controller_test.rb` | 25 tests: auth, handshake, each tool, quota accounting, tenant isolation |
| `claude/implementations/mcp-server.md` | This document |

## Modified Files

| File | Change |
|------|--------|
| `config/routes.rb` | `POST /mcp`; `GET`/`DELETE /mcp` return 405 |
| `config/initializers/rack_attack.rb` | `Rack::Attack.api_key_authenticated_path?` now covers `/mcp` alongside `/api/v1`, so MCP shares the per-tier throttle, the API-key identifier middleware, and the JSON 429 body instead of the general per-IP limit |
| `README.md` | Connection instructions |
| `TODO.md` | Ticked the MCP items |

## Routes

| Method | Path | Action |
|--------|------|--------|
| POST | `/mcp` | `mcp/server#handle` |
| GET, DELETE | `/mcp` | `mcp/server#unsupported` (405) |

## Tools

| Tool | Arguments | Backed by |
|------|-----------|-----------|
| `lookup_from_url` | `url`, `save` (default true) | `ApiCommodityService#suggest_from_url` → `ProductLookup` |
| `lookup_from_description` | `description`, `save` (default true) | `ApiCommodityService#suggest_from_description` → `ProductLookup` |
| `search_codes` | `query`, `limit` (max 50) | `TariffLookupService#search` |
| `get_code` | `code` (6–10 digits, punctuation ignored) | `TariffLookupService#get_commodity` |
| `list_recent_lookups` | `limit` (max 100), `since` | `user.product_lookups` |

Codes come back twice: `commodity_code` as raw digits and `formatted_code` as
`6109 10 0010`, matching how the site renders them.

## Data Flow

```
Claude session
      │  POST /mcp   Authorization: Bearer tk_live_...
      ▼
ApiKeyRateLimitMiddleware ──► per-tier minute throttle (Rack::Attack)
      ▼
Mcp::ServerController  (Api::V1::BaseController: authenticate, daily limit, log)
      │
      ├── initialize / ping / tools/list ──► Mcp::ToolCatalog        (no quota spent)
      │
      └── tools/call ──► Mcp::ToolRunner                             (1 request spent)
                              │
                              ├─ lookup_from_url ──► ApiCommodityService
                              │        └─ ProductScraperService ─► LlmCommoditySuggester
                              │                                        └─ TariffLookupService (validate)
                              │        └─ ProductLookup.create!   (dashboard + CSV export)
                              │
                              ├─ lookup_from_description ──► ApiCommodityService ─► ProductLookup.create!
                              ├─ search_codes / get_code ──► TariffLookupService
                              └─ list_recent_lookups ──► user.product_lookups
```

## Connecting

```bash
claude mcp add --transport http tariffik https://tariffik.com/mcp
```

No credential is passed: the client discovers Tariffik's authorization server
from the 401, registers itself, and opens a browser for you to approve it. MCP
access still needs a Starter subscription or higher, now enforced by the endpoint
rather than by the credential. See `mcp-oauth-authorization.md`.

## Testing / Verification

```bash
bin/rails test test/controllers/mcp/server_controller_test.rb   # 25 runs, 0 failures
bin/rails test test/controllers                                 # 108 runs, 0 failures
bundle exec rubocop app/controllers/mcp app/services/mcp        # clean
```

Verified against a live dev server on 2026-09-17, hitting the real UK Trade
Tariff and Anthropic APIs:

| Check | Result |
|-------|--------|
| No API key | 401 |
| `initialize` | protocolVersion `2025-06-18`, serverInfo `tariffik` |
| `notifications/initialized` | 202, empty body |
| `tools/list` | all five tools with input schemas |
| `get_code` `"6109 10 0010"` | `6109100010`, "T-shirts" |
| `lookup_from_description` cotton t-shirt | `6109100010`, confidence 0.9, validated, saved as lookup 1 |
| `lookup_from_url` allbirds wool runner | `6404199000`, validated, saved as lookup 2 |
| `get_code` `"9999999999"` | `isError: true`, `not_found` |

## Limitations & Future Improvements

- **Scrape quality carries straight through.** The allbirds check returned
  confidence 0.6 because `ProductScraperService` picked up the site tagline as
  the title and a fragment of a meta tag as the material. That is a pre-existing
  scraper weakness, not an MCP one, but it is more visible here because an agent
  will act on the first answer it gets.
- ~~**Static bearer tokens only.**~~ Done on 2026-09-17: Tariffik is now its own
  OAuth 2.1 authorization server. See `mcp-oauth-authorization.md`.
- **No batch tool.** A sweep of thirty emails means thirty sequential calls.
  `POST /api/v1/commodity-codes/batch` already exists; a `batch_lookup` tool
  could submit to it and poll.
- **No `outputSchema`.** Tool results are JSON inside a text content block, which
  every client understands. Declaring output schemas and returning
  `structuredContent` would let strict clients validate results.
- **Nothing writes back.** An agent can read saved lookups but cannot confirm a
  code, attach one to an order, or trigger the CSV export.
