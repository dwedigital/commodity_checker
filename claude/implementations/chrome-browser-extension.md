# Chrome Browser Extension Implementation

**Date:** 2026-01-18
**Feature:** Browser extension for commodity code lookups while browsing

## Overview

This implementation adds a Chrome browser extension that allows users to look up commodity codes for products while browsing e-commerce websites. The extension:

- Allows **3 free lifetime lookups** without login (tracked by extension instance ID)
- Supports **login with existing Tariffik accounts** via OAuth-style flow
- **Extracts product info** from the current page using JSON-LD, Open Graph, and HTML parsing
- **Saves lookups** to the user's account (respecting subscription tier limits)

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Code location | `browser-extension/` in repo root | Easier to maintain together with backend |
| Manifest version | Manifest V3 | Required for Chrome Web Store, modern service workers |
| Free lookup tracking | Server-side by extension ID | Simple implementation, acceptable bypass risk for 3 lookups |
| Authenticated access | Match subscription tier | Free: 5/month, Starter: 100/month, Pro+: unlimited |
| Auth flow | OAuth-style redirect | Secure - credentials never touch extension |
| Token storage | Chrome storage API | Persists across sessions, syncs with Chrome account |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Chrome Extension                              │
├─────────────────────────────────────────────────────────────────┤
│  sidepanel.html/js │  content.js        │  service-worker.js    │
│  (Side Panel UI)   │  (product extract) │  (background/auth)    │
└────────┬───────────┴────────┬───────────┴──────────┬────────────┘
         │                    │                      │
         └────────────────────┴──────────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │  Tariffik API     │
                    │  /api/v1/extension│
                    └─────────┬─────────┘
                              │
    ┌─────────────────────────┼─────────────────────────┐
    ▼                         ▼                         ▼
ExtensionLookup        ExtensionToken           ProductLookup
(anonymous tracking)   (auth tokens)            (saved results)
```

The extension uses Chrome's **Side Panel API** instead of a popup for better UX - the panel stays open while browsing and automatically refreshes when switching tabs.

## Database Changes

### New Table: `extension_lookups`

Tracks anonymous lookups by extension instance ID.

```ruby
create_table :extension_lookups do |t|
  t.string :extension_id, null: false
  t.string :lookup_type, default: "url"
  t.text :url
  t.string :commodity_code
  t.string :ip_address
  t.timestamps
end
add_index :extension_lookups, :extension_id
add_index :extension_lookups, [:extension_id, :created_at]
```

### New Table: `extension_tokens`

Long-lived auth tokens for authenticated extension users. Similar pattern to `api_keys`.

```ruby
create_table :extension_tokens do |t|
  t.references :user, null: false, foreign_key: true
  t.string :token_digest, null: false
  t.string :token_prefix, null: false
  t.string :extension_id
  t.string :name
  t.datetime :last_used_at
  t.datetime :revoked_at
  t.timestamps
end
add_index :extension_tokens, :token_digest, unique: true
add_index :extension_tokens, :token_prefix
add_index :extension_tokens, [:user_id, :revoked_at]
```

### New Table: `extension_auth_codes`

Short-lived OAuth authorization codes for token exchange.

```ruby
create_table :extension_auth_codes do |t|
  t.references :user, null: false, foreign_key: true
  t.string :code_digest, null: false
  t.string :extension_id, null: false
  t.datetime :expires_at, null: false
  t.datetime :used_at
  t.timestamps
end
add_index :extension_auth_codes, :code_digest, unique: true
add_index :extension_auth_codes, :expires_at
```

## New Files Created

### Backend - Models

| File | Purpose |
|------|---------|
| `app/models/extension_lookup.rb` | Tracks anonymous lookups, enforces 3-lookup lifetime limit |
| `app/models/extension_token.rb` | Auth tokens for extension (like ApiKey pattern) |
| `app/models/extension_auth_code.rb` | OAuth codes with 5-minute expiry, single-use |

### Backend - Controllers

| File | Purpose |
|------|---------|
| `app/controllers/api/v1/extension_controller.rb` | API endpoints: lookup, usage, token exchange/revoke |
| `app/controllers/extension_auth_controller.rb` | OAuth web pages: authorize, create_code, callback |

### Backend - Services

| File | Purpose |
|------|---------|
| `app/services/extension_lookup_service.rb` | Orchestrates lookups for both anonymous and authenticated users |

### Backend - Views

| File | Purpose |
|------|---------|
| `app/views/extension_auth/authorize.html.erb` | Authorization consent page |
| `app/views/extension_auth/callback.html.erb` | Success/code display page |

### Backend - Configuration

| File | Purpose |
|------|---------|
| `config/initializers/cors.rb` | CORS config for chrome-extension:// origin |
| `db/migrate/20260118200000_create_extension_lookups.rb` | Extension lookups migration |
| `db/migrate/20260118200001_create_extension_tokens.rb` | Extension tokens migration |
| `db/migrate/20260118200002_create_extension_auth_codes.rb` | Extension auth codes migration |

### Chrome Extension

| File | Purpose |
|------|---------|
| `browser-extension/manifest.json` | Manifest V3 config with Side Panel API |
| `browser-extension/service-worker.js` | Background message handling, auth, side panel behavior |
| `browser-extension/lib/api.js` | API client module |
| `browser-extension/content/content.js` | Product extraction from pages |
| `browser-extension/sidepanel/sidepanel.html` | Side panel UI |
| `browser-extension/sidepanel/sidepanel.css` | Side panel styles (full-height layout) |
| `browser-extension/sidepanel/sidepanel.js` | Side panel logic with tab switching and history |
| `browser-extension/callback/callback.html` | OAuth callback handler |
| `browser-extension/icons/icon*.png` | Extension icons (16, 48, 128px) |

## Modified Files

### Models

| File | Change |
|------|--------|
| `app/models/user.rb` | Added `has_many :extension_tokens`, `has_many :extension_auth_codes`, extension lookup limit methods |

### Controllers

| File | Change |
|------|--------|
| `app/controllers/developer_controller.rb` | Added `@extension_tokens` to index, `revoke_extension_token` action |

### Configuration

| File | Change |
|------|--------|
| `config/routes.rb` | Added extension API routes and OAuth web routes |
| `config/initializers/rack_attack.rb` | Added extension endpoint rate limiting rules |
| `Gemfile` | Added `rack-cors` gem |

### Views

| File | Change |
|------|--------|
| `app/views/developer/index.html.erb` | Added "Browser Extension" section with token management |

## Routes

### API Routes

```
POST   /api/v1/extension/lookup    - Perform commodity code lookup
GET    /api/v1/extension/usage     - Check anonymous usage stats
POST   /api/v1/extension/token     - Exchange auth code for token
DELETE /api/v1/extension/token     - Revoke current token
```

### Web Routes

```
GET    /extension/auth             - Authorization consent page
POST   /extension/auth             - Create auth code and redirect
GET    /extension/auth/callback    - OAuth callback display
DELETE /developer/extension-tokens/:id - Revoke extension token
```

## Data Flow

### Anonymous Lookup Flow

```
Extension side panel opened
       │
       ▼
chrome.tabs.sendMessage → content.js
       │
       ▼
Extract product info (JSON-LD, OG, HTML)
       │
       ▼
POST /api/v1/extension/lookup
{ extension_id, url, product }
       │
       ▼
ExtensionLookupService.anonymous_lookup
       │
       ├─── Check ExtensionLookup.can_perform_anonymous_lookup?
       │         │
       │         ├─ No → Return 402 "free_lookups_exhausted"
       │         │
       │         └─ Yes → Continue
       │
       ├─── ApiCommodityService.suggest_from_url
       │
       └─── ExtensionLookup.record_anonymous_lookup
       │
       ▼
Return { commodity_code, confidence, extension_usage }
```

### OAuth Authentication Flow

```
User clicks "Sign In" in extension
       │
       ▼
chrome.tabs.create(authUrl)
       │
       ▼
/extension/auth?extension_id=...&redirect_uri=...
       │
       ├─── Not logged in → Redirect to Devise sign_in
       │
       └─── Logged in → Show authorize.html.erb
       │
       ▼
User clicks "Authorize"
       │
       ▼
POST /extension/auth
       │
       ├─── ExtensionAuthCode.create!(user, extension_id)
       │
       └─── Redirect to callback/callback.html?code=...
       │
       ▼
callback.html executes
       │
       ▼
chrome.runtime.sendMessage({ type: 'EXCHANGE_TOKEN', code })
       │
       ▼
service-worker.js → POST /api/v1/extension/token
       │
       ▼
ExtensionAuthCode.exchange(code, extension_id)
       │
       ├─── Verify code valid, not expired, not used
       │
       ├─── Mark code as used
       │
       └─── ExtensionToken.create!(user, extension_id)
       │
       ▼
Return { token, user: { email, tier, remaining } }
       │
       ▼
chrome.storage.local.set({ authToken, userInfo })
```

### Authenticated Lookup Flow

```
POST /api/v1/extension/lookup
Authorization: Bearer ext_tk_live_...
       │
       ▼
authenticate_extension_token!
       │
       ├─── ExtensionToken.authenticate(token)
       │
       └─── @current_user = token.user
       │
       ▼
ExtensionLookupService.authenticated_lookup
       │
       ├─── Check user.can_perform_extension_lookup?
       │         │
       │         ├─ No → Return 402 "monthly_limit_reached"
       │         │
       │         └─ Yes → Continue
       │
       ├─── ApiCommodityService.suggest_from_url
       │
       └─── ProductLookup.create! (save to user's history)
       │
       ▼
Return { commodity_code, confidence, product_lookup_id, user_usage }
```

## Subscription Tier Limits

| Tier | Monthly Extension Lookups |
|------|---------------------------|
| Anonymous | 3 lifetime (total) |
| Free (logged in) | 5/month |
| Starter | 100/month |
| Professional | Unlimited |
| Enterprise | Unlimited |

## Rate Limiting

| Endpoint | Limit | Key |
|----------|-------|-----|
| Anonymous lookup | 10/min | extension_id |
| Usage check | 30/min | IP address |
| Token exchange | 5/min | IP address |
| Authenticated lookup | Tier-based (10-100/min) | token_id |

## Content Script - Product Extraction

The content script extracts product information in this priority order:

1. **JSON-LD** - `<script type="application/ld+json">` with Product schema
2. **Open Graph** - `og:title`, `og:description`, `og:image`, `product:price:amount`
3. **Meta tags** - `<title>`, `<meta name="description">`
4. **Microdata** - `[itemtype*="schema.org/Product"]` attributes
5. **HTML fallback** - Common selectors like `.product-description`, `h1`

## Security Considerations

- **Token hashing**: Extension tokens use SHA256 digest (same as API keys)
- **OAuth codes**: 5-minute expiry, single-use, tied to extension_id
- **CORS**: Restricted to `chrome-extension://` origins
- **No credentials in extension**: OAuth redirect keeps passwords server-side
- **Rate limiting**: Prevents abuse of both anonymous and authenticated endpoints

## Testing

### Manual Testing Steps

1. **Load extension locally**:
   ```bash
   # Navigate to chrome://extensions
   # Enable "Developer mode"
   # Click "Load unpacked" and select browser-extension/
   ```

2. **Test anonymous lookup**:
   - Navigate to a product page (e.g., Amazon)
   - Click extension icon
   - Click "Look Up Commodity Code"
   - Verify result displays
   - Repeat 3 times, verify 4th is blocked

3. **Test authentication**:
   - Click "Sign In to Tariffik" in extension
   - Complete login in browser
   - Click "Authorize" on consent page
   - Verify callback shows success
   - Verify side panel shows user email/tier

4. **Test authenticated lookup**:
   - Perform lookup while signed in
   - Verify lookup saved to `/product_lookups`
   - Verify monthly usage counter decrements

5. **Test token revocation**:
   - Go to `/developer` on website
   - Click "Revoke" on extension token
   - Verify extension shows signed out

### Verification Commands

```bash
# Check routes
bin/rails routes | grep extension

# Check migrations applied
bin/rails runner "puts ExtensionLookup.table_name"

# Test anonymous lookup limit
bin/rails runner "
  ext_id = 'test_extension_123'
  3.times { ExtensionLookup.record_anonymous_lookup(extension_id: ext_id, url: 'https://example.com', commodity_code: '1234567890') }
  puts ExtensionLookup.can_perform_anonymous_lookup?(ext_id)  # false
"

# Test token authentication
bin/rails runner "
  user = User.first
  token = user.extension_tokens.create!(name: 'Test')
  puts token.raw_token
  puts ExtensionToken.authenticate(token.raw_token).user.email
"
```

## Limitations & Future Improvements

### Current Limitations

- **Single browser profile**: Token is per-browser-profile, not synced across devices
- **No offline support**: Requires network connection for all lookups
- **Product extraction**: May miss product info on JavaScript-heavy SPAs without JSON-LD

### Potential Future Improvements

1. **Firefox support**: Create Firefox version using browser namespace polyfill
2. **Safari support**: Safari Web Extension using same codebase
3. **Quick lookup history**: ~~Show recent lookups in popup~~ ✅ Already implemented in side panel
4. **Badge count**: Show remaining lookups as badge on extension icon
5. **Context menu**: Right-click product name/image to lookup
6. **Bulk lookup**: Select multiple products on a page

## Chrome Web Store Submission

Before publishing:

1. **Create privacy policy** at tariffik.com/extension-privacy
2. **Prepare screenshots** (1280x800) showing:
   - Side panel on product page
   - Lookup result
   - Sign-in flow
3. **Create promotional images** (440x280 small, 920x680 large)
4. **Set CHROME_EXTENSION_ID** env var after first publish
5. **Update CORS** to only allow specific extension ID in production

## Files Summary

### New Files (21)

**Backend (13)**
- `app/models/extension_lookup.rb`
- `app/models/extension_token.rb`
- `app/models/extension_auth_code.rb`
- `app/controllers/api/v1/extension_controller.rb`
- `app/controllers/extension_auth_controller.rb`
- `app/services/extension_lookup_service.rb`
- `app/views/extension_auth/authorize.html.erb`
- `app/views/extension_auth/callback.html.erb`
- `config/initializers/cors.rb`
- `db/migrate/20260118200000_create_extension_lookups.rb`
- `db/migrate/20260118200001_create_extension_tokens.rb`
- `db/migrate/20260118200002_create_extension_auth_codes.rb`

**Chrome Extension (9)**
- `browser-extension/manifest.json`
- `browser-extension/service-worker.js`
- `browser-extension/lib/api.js`
- `browser-extension/content/content.js`
- `browser-extension/sidepanel/sidepanel.html`
- `browser-extension/sidepanel/sidepanel.css`
- `browser-extension/sidepanel/sidepanel.js`
- `browser-extension/callback/callback.html`
- `browser-extension/icons/` (3 PNG files + README)

### Modified Files (6)

- `app/models/user.rb`
- `app/controllers/developer_controller.rb`
- `app/views/developer/index.html.erb`
- `config/routes.rb`
- `config/initializers/rack_attack.rb`
- `Gemfile`
