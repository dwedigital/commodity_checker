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
- **Redirect allowlist (Sep 2026 fix)**: `ExtensionAuthController#validate_redirect_uri` only accepts `chrome-extension://<CHROME_EXTENSION_ID>/callback/callback.html` (exact path, no query/fragment/userinfo/port) on both `authorize` and `create_code`. Previously any `redirect_uri` was followed with `allow_other_host: true`, so a crafted link could have sent a user's auth code to another site. Without `CHROME_EXTENSION_ID` (dev/test) any well-formed 32-char Chrome ID is accepted, mirroring `config/initializers/cors.rb`. Note `extension_id` in the request is the extension's random `ext_…` identifier, not its Chrome ID, so the check uses the env var. A blank `redirect_uri` still falls back to the manual-copy code page. Covered by `test/controllers/extension_auth_controller_test.rb`
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

## September 2026 design refresh (v1.2.0)

The side panel and OAuth callback page now match the website's `tf-*` refresh (warm paper, ink, red accents, mono eyebrows, 6px buttons, sentence case, split `6109 10 0010` codes).

| File | Change |
|---|---|
| `browser-extension/styles/brand.css` (new) | Shared tokens, `@font-face`, wordmark, eyebrow and button styles for extension pages |
| `browser-extension/fonts/` (new) | Latin woff2 subsets of Space Grotesk and Plus Jakarta Sans (OFL), bundled so extension pages never request Google Fonts |
| `browser-extension/sidepanel/*` | Paper header with `tariffik.` wordmark; "Find my code" button; result card mirrors the homepage label (split code, raw code, confidence bar, reasoning, Copy code / View history); history rows show split codes; sentence-case copy. All element ids unchanged |
| `browser-extension/callback/callback.html` | Connecting / connected / couldn't connect states on the dotted auth ground, matching the website's "Extension connected" page |
| `browser-extension/manifest.json` | Version 1.2.0 |

**Homepage screenshot** (`public/images/chrome-extension-sidepanel.png`, 736×1196, shown at 368px): captured from the real `sidepanel.html` served over HTTP with a throwaway script that stubs `chrome.runtime/tabs/storage` with sample data (organic cotton T-shirt → 6109 10 0010) and clicks "Find my code", rendered by headless Chrome at 2× (`--force-device-scale-factor=2`, panel fixed at 368px inside a 500px window because headless won't go narrower, then cropped with ImageMagick). The stub is not committed; recreate it the same way when the panel changes.

**Icons:** `icons/*.png` are still the old red circle, and the website favicon is still the older "T" mark — neither uses the refresh's ↗ mark yet.

## September 2026 auth redo (Google-only sign-in)

`claude/implementations/google-oauth-only-login.md` removed passwords from the
app. The extension had not caught up: its "Create free account" button pointed
at `/users/sign_up`, which is now a 404, and the connect flow never survived the
trip through Google.

### The connect flow was broken

`/extension/auth` is the only route that issues a connection code, and it sits
behind `authenticate_user!`. A signed-out user was sent to `/users/sign_in`,
signed in with Google, and landed on the dashboard — the extension never got a
code and there was no way back to the page that issues one.

The cause was one line in `Users::SessionsController#new`. Devise's
`stored_location_for` **deletes as it reads** on navigational formats
(`devise-4.9.4/lib/devise/controllers/store_location.rb:18`), so rendering the
sign-in page consumed the location that the callback needed minutes later.
`@after_sign_in` was assigned and then never used.

Reproduced before fixing: driving `/extension/auth` → `/users/sign_in` → Google
redirected to `/`, while the same flow that skipped rendering the sign-in page
redirected correctly back to `/extension/auth`. Both paths are now covered in
`test/controllers/users/sessions_controller_test.rb`.

```
Extension "Continue with Google"
  │  chrome.tabs.create(authUrl)
  ▼
GET /extension/auth?extension_id=…&redirect_uri=chrome-extension://…
  │  signed out → session[:signup_source] = "extension"
  │            → Devise stores user_return_to, redirects
  ▼
GET /users/sign_in            reads the stored location AND PUTS IT BACK
  │  POST /users/auth/google_oauth2
  ▼
Google  ──►  /users/auth/google_oauth2/callback
  │  after_sign_in_path_for finds the stored location
  ▼
GET /extension/auth  (consent screen, names the Google account)
  │  POST /extension/auth → ExtensionAuthCode
  ▼
chrome-extension://…/callback/callback.html?code=…
  │  EXCHANGE_TOKEN → service worker stores the token
  ▼
AUTH_COMPLETE → side panel re-inits, tab closes itself
```

### Modified files

| File | Change |
|---|---|
| `app/controllers/users/sessions_controller.rb` | Re-stores the location it read, so the Google round trip keeps it; sets `@connecting_extension` |
| `app/views/users/sessions/new.html.erb` | Says "Sign in to connect the extension" when that is where the visitor was heading |
| `app/controllers/extension_auth_controller.rb` | `remember_extension_signup_source` stamps `session[:signup_source] = "extension"` ahead of `authenticate_user!`, because Devise's redirect cannot carry a `?source=` param |
| `app/views/extension_auth/authorize.html.erb` | Consent screen names the Google account: profile photo, `display_name`, email |
| `app/views/shared/_account_avatar.html.erb` (new) | Google profile photo with an initial fallback; shared with `/dashboard/account`, which renders it on `develop` but shipped without it — see below |
| `app/views/users/accounts/show.html.erb` | Uses the shared partial |
| `app/assets/stylesheets/tariffik_workspace.css` | `.tf-account-avatar` no longer shrinks in a flex row; `.tf-account-avatar-photo` crops to the circle |
| `config/locales/devise.en.yml` | `unauthenticated` no longer offers a sign-up that does not exist |
| `browser-extension/sidepanel/sidepanel.html` | Both panels carry the website's "Continue with Google" button and mark |
| `browser-extension/sidepanel/sidepanel.js` | Dropped the `/users/sign_up` URL; both CTAs run `signIn()`; `updateSignInVisibility()` |
| `browser-extension/styles/brand.css` | `.btn-google`, `.google-mark` mirroring the site's `.tf-google-button` |

### Both CTAs go through the connect flow

The limit panel used to link to `/users/sign_up` and the sign-in panel opened
the connect URL. Sending the limit panel to the website alone would leave a new
account signed in on the site with the extension still anonymous, so both now
open `/extension/auth`: one trip creates the account **and** connects it.

That made the two panels identical, and they were being shown together when the
free allowance ran out — two "Continue with Google" buttons stacked. Caught on a
rendered screenshot, not by reading the code. `updateSignInVisibility()` now
gives the limit panel precedence whenever it is up.

### Icons

`icons/*.png` were plain red circles matching neither the old "T" favicon nor
the refresh. All three are now the `↗` mark, and the website favicon
(`public/icon.svg`, `public/icon.png`, `public/apple-touch-icon.png`) moved to
the same mark so the toolbar, tab and wordmark agree. The favicon cache-buster
in `app/views/layouts/application.html.erb` and `app/views/pwa/manifest.json.erb`
went to `?v=3`.

`icon16` uses a tuned geometry — larger arrow, heavier shaft, tighter corner
radius — because the standard one turns to mush at 16px. See
`browser-extension/icons/README.md` for the regeneration commands.

### The account page had no coverage, and it cost us

`app/views/users/accounts/show.html.erb` renders `shared/account_avatar`. The
partial was written as part of this work, stayed untracked through a branch
switch, and the Google-OAuth commit shipped the `render` without the template —
so `/dashboard/account` raised `Missing partial shared/_account_avatar` on
`develop` until this branch restored it.

CI stayed green the whole time because **nothing in the suite rendered
`account_path`**. `test/controllers/users/accounts_controller_test.rb` now does,
including both avatar branches and account deletion. Confirmed non-vacuous by
moving the partial aside and watching the tests error with exactly the
production message.

It never reached production: the deploy of that period (PR #70) predated the
OAuth merge, and `origin/main` did not contain the account page at all.

### Verification

```bash
bin/rails test                                  # 395 runs, 0 failures
bundle exec rubocop                             # clean
bundle exec brakeman                            # 0 warnings
```

The side panel was rendered and screenshotted in all three states (anonymous,
allowance exhausted, signed-in result) by serving `browser-extension/` over HTTP
with a throwaway `stub.js` that fakes `chrome.runtime/tabs/storage`, then
capturing with headless Chrome at 2×. The stub is not committed; recreate it the
same way. The `callback/callback.html` success state and both `/users/sign_in`
variants were captured the same way against the dev server.

**Not verified:** the live Google round trip from a loaded extension, which
needs the extension installed and a real Google client. The Rails half of that
round trip is covered by the tests above.

### Still outstanding

`browser-extension.zip` at the repo root is untouched and still the January
**1.1.0** upload artifact, while the source is 1.2.0. It was not regenerated
here because its layout is questionable on two counts: it nests everything under
a `browser-extension/` folder rather than putting `manifest.json` at the zip
root, and it carries `__MACOSX/` resource forks, both signs it came from Finder's
Compress rather than a build step. Rebuild it deliberately before the next Web
Store upload rather than trusting what is committed.

### Gotchas met

- **`stored_location_for` deletes as it reads.** Anything that renders the
  sign-in page must put the location back, or every "sign in to continue" flow
  in the app silently loses its destination, not just the extension's.
- **Ahoy ignores bot user agents** (`Ahoy.track_bots = false`), and the
  integration test rig sends one, so `ahoy.track` is a no-op there. The
  `user_registered` event cannot be asserted in a controller test; the test
  asserts `session[:signup_source]` instead. The event itself works in the real
  app (the dev database holds 481 of them).
- **The dev server redirects to port 3000** while `bin/dev` listens on 3101, so
  `curl -L` through `/extension/auth` dies on a dead port. Drive the redirect by
  hand with a cookie jar when capturing the sign-in page.
