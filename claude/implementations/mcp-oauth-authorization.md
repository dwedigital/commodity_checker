# MCP OAuth Authorization Implementation

**Date:** 2026-09-17
**Feature:** Tariffik becomes its own OAuth 2.1 authorization server, and `/mcp` becomes an OAuth resource server

## Overview

The MCP endpoint no longer accepts API keys. It accepts OAuth 2.1 access tokens
issued by Tariffik itself, to a client the user has explicitly approved, for a
user who signed in with Google.

This is what the MCP authorization spec (2025-06-18) requires of a remote MCP
server, and it is what claude.ai's connectors need: they will not use a static
bearer token, they expect to discover an authorization server, register
themselves, and run an authorization code flow with PKCE.

Builds on `google-oauth-only-login.md` — Google is the identity behind the
consent screen — and replaces the API key auth described in `mcp-server.md`.

## Design Decisions

**Doorkeeper for the core, custom code for the MCP-specific parts.** Doorkeeper
issues and validates codes and tokens, verifies PKCE, rotates refresh tokens and
handles revocation. It does not do RFC 7591 registration, RFC 8414 or RFC 9728
metadata, or RFC 8707 audience binding, so those are written here. Writing token
issuance by hand was the alternative and was rejected: the protocol details are
where the risk is, and Doorkeeper has had them reviewed for years.

**OAuth only on `/mcp`.** API keys were dropped rather than kept alongside, so
there is exactly one way to authenticate an MCP request and every token is
audience-bound and revocable. API keys remain the credential for `/api/v1`.

**Audience binding through `custom_access_token_attributes`.** Doorkeeper carries
the `resource` parameter from the authorize request onto the grant, onto the
access token, and onto any refreshed token. `/mcp` refuses a token whose
`resource` is not itself. A token with no `resource` is accepted, because this
authorization server protects exactly one resource and so cannot have issued a
token for anything else — **if a second protected resource is ever added, that
has to become strict.**

**Authorization code only.** No implicit flow (gone in OAuth 2.1), no password
grant, and no client credentials: an MCP tool acts on a person's account, so
every token has to belong to a person.

**PKCE forced, S256 only.** `plain` provides none of PKCE's protection, so it is
neither accepted nor advertised.

**Consent is never skipped.** Clients register themselves with no vetting, so
automatic approval is exactly the confused-deputy problem the MCP security
guidance describes. The consent screen names the client, the account, and the
host it will redirect back to.

**The Starter entitlement moved into the endpoint.** MCP access used to be gated
by needing an API key, which needs a Starter subscription. OAuth would otherwise
have handed the tools to every free account, so `/mcp` now checks
`user.has_api_access?` and returns 403 with an explanation.

## Database Changes

Migration `20260917151559_create_doorkeeper_tables.rb`, with three departures
from Doorkeeper's generated version:

| Change | Why |
|--------|-----|
| `oauth_applications.secret` nullable | MCP clients register as public clients and authenticate with PKCE |
| `oauth_access_grants.code_challenge`, `code_challenge_method` | PKCE (Doorkeeper ships this as a separate generator) |
| `oauth_access_grants.resource`, `oauth_access_tokens.resource` | RFC 8707 audience binding |

Foreign keys from both grants and tokens to `users` were also enabled.

## New Files Created

| File | Purpose |
|------|---------|
| `config/initializers/doorkeeper.rb` | Authorization server configuration |
| `app/controllers/oauth/metadata_controller.rb` | RFC 8414 and RFC 9728 discovery documents |
| `app/controllers/oauth/registrations_controller.rb` | RFC 7591 dynamic client registration |
| `app/views/doorkeeper/authorizations/new.html.erb` | Consent screen |
| `app/views/doorkeeper/authorizations/_pre_auth_fields.html.erb` | Carries every authorize parameter, `resource` included, through the consent POST |
| `app/views/doorkeeper/authorizations/error.html.erb` | Authorization failure |
| `app/views/doorkeeper/authorized_applications/index.html.erb` | Connected apps, with disconnect |
| `app/views/layouts/doorkeeper/application.html.erb` | Renders Doorkeeper's screens inside Tariffik's layout |
| `test/support/oauth_test_helper.rb` | Token and PKCE helpers |
| `test/controllers/oauth/metadata_controller_test.rb` | Discovery documents |
| `test/controllers/oauth/registrations_controller_test.rb` | Registration and redirect URI rules |
| `test/integration/mcp_oauth_flow_test.rb` | The whole journey, end to end |

## Modified Files

| File | Change |
|------|--------|
| `Gemfile` | `doorkeeper` |
| `app/controllers/mcp/server_controller.rb` | API key auth replaced with OAuth token validation, audience check, scope check, entitlement check, and the RFC 9728 `WWW-Authenticate` challenge |
| `config/routes.rb` | `use_doorkeeper` (applications CRUD skipped), `/oauth/register`, the two well-known endpoints |
| `config/initializers/rack_attack.rb` | `/mcp` throttled per token owner rather than per API key; `/oauth/register` and `/oauth/token` throttled by IP |
| `app/views/users/accounts/show.html.erb` | Connected apps panel |
| `app/helpers/application_helper.rb` | Consent screen gets the auth-page treatment |
| `config/locales/doorkeeper.en.yml` | Plain-language wording for the `mcp` scope |
| `app/assets/stylesheets/tariffik.css` | `.tf-consent` |
| `test/controllers/mcp/server_controller_test.rb` | Rewritten against OAuth |

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/.well-known/oauth-protected-resource` (and `/mcp`) | RFC 9728 |
| GET | `/.well-known/oauth-authorization-server` (and `/mcp`) | RFC 8414 |
| POST | `/oauth/register` | RFC 7591 |
| GET/POST/DELETE | `/oauth/authorize` | Consent |
| POST | `/oauth/token` | Code exchange and refresh |
| POST | `/oauth/revoke`, `/oauth/introspect` | Doorkeeper |
| GET/DELETE | `/oauth/authorized_applications` | Connected apps |

## Data Flow

```
MCP client                    Tariffik (resource server + authorization server)
    │
    │ POST /mcp  (no token)
    ├────────────────────────► 401 + WWW-Authenticate: Bearer resource_metadata="…"
    │
    │ GET /.well-known/oauth-protected-resource/mcp
    ├────────────────────────► { resource, authorization_servers: [issuer] }
    │
    │ GET /.well-known/oauth-authorization-server
    ├────────────────────────► { authorize, token, register, S256 }
    │
    │ POST /oauth/register                          (no credentials yet)
    ├────────────────────────► { client_id }        public client, no secret
    │
    │ browser ► GET /oauth/authorize + code_challenge + resource
    │                          ├─ not signed in ──► Google sign-in ──► back here
    │                          └─ consent screen ──► user approves
    ├◄─────────────────────────  302 redirect_uri?code=…&state=…
    │
    │ POST /oauth/token  code + code_verifier + resource
    ├────────────────────────► access_token (1h, resource-bound) + refresh_token
    │
    │ POST /mcp  Authorization: Bearer …
    ├────────────────────────► validate: accessible? scope? audience? entitled?
    └◄─────────────────────────  JSON-RPC response
```

## Testing / Verification

```bash
bin/rails test        # 384 runs, 0 failures
bundle exec rubocop   # clean
```

Verified against a live server on 2026-09-17, driving the consent screen in
Chrome and the rest with real HTTP:

| Check | Result |
|-------|--------|
| `POST /mcp` with no token | 401 with `WWW-Authenticate: Bearer … resource_metadata="…/.well-known/oauth-protected-resource/mcp"` |
| Discovery documents | Resource names the authorization server; server advertises authorize, token, register, `S256` |
| `POST /oauth/register` | Public client created, **no secret returned** |
| `/oauth/authorize` while signed out | Redirected to Google sign-in, then back to the authorize URL with `resource` and `code_challenge` intact |
| Consent screen | Names the client, the account, and the redirect host |
| Approve | 302 to the client's callback with a code; the stored grant carried `resource` and `S256` |
| Token exchange, wrong PKCE verifier | 400 `invalid_grant` |
| Token exchange, correct verifier | 200, Bearer, 3600s, scope `mcp`, refresh token issued |
| `initialize`, `tools/list`, `get_code` with that token | All succeeded against the live UK Trade Tariff |
| Refresh, then reuse | Refreshed token works on `/mcp` |
| Token bound to `https://evil.example.com/mcp` | **401** `The access token was not issued for this MCP server` |
| Connected apps page | Lists the client with a working disconnect |

### Bug found by the browser run, not by the tests

The consent form was being submitted by Turbo (`format=turbo_stream` in the
logs). Turbo cannot follow the cross-origin redirect back to a client's callback,
so the browser sat on the consent page and the flow dead-ended — while every
integration test passed, because integration tests do not run Turbo. Both consent
forms now carry `data: { turbo: false }`, and a test asserts that attribute on
the rendered markup, which is the only thing that can guard it from Rails.

A second, smaller one: `optional_scopes []` registered a scope literally named
`"[]"`, which was being advertised in both discovery documents. The line is gone
and a test pins `scopes_supported` to exactly `["mcp"]`.

## Limitations & Future Improvements

- **Audience binding is lenient about a missing `resource`.** Safe while there is
  one protected resource; must become strict if another is added.
- **No request logging for MCP.** `ApiRequest` requires an `api_key`, so OAuth
  MCP traffic does not appear in the developer dashboard. Throttling counts are
  per user, but there is no per-user usage history.
- **Registration is open.** RFC 7591 intends that, and it is throttled to 10 per
  hour per IP, but nothing expires unused clients. A sweep of applications with
  no tokens would keep the table tidy.
- **No consent screen for scope changes.** There is one scope, so nothing to
  re-consent to yet.
- **`claude.ai` connector untested.** The flow was verified with a hand-driven
  client; connecting from claude.ai itself needs the production deploy and HTTPS.
