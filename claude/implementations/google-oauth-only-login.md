# Google-Only Login Implementation

**Date:** 2026-09-17
**Feature:** Sign in with Google replaces email and password as the only way into Tariffik

## Overview

Tariffik no longer has passwords. `/users/sign_in` offers one button, Google is
the only identity provider, and signing in and signing up are the same action.

Existing accounts are carried across by matching the Google address against the
account's email, so a user who signed up with a password keeps their orders,
lookups, API keys and forwarding address.

This is step one of moving the app onto OAuth. Step two is putting the MCP
endpoint (`claude/implementations/mcp-server.md`) behind OAuth rather than
static API keys, which needs Tariffik to act as its own authorization server;
Google sits behind that login rather than replacing it.

## Design Decisions

**Link existing accounts by verified email.** Chosen over a hard cut so nobody
loses their data. It is only safe because Google reports whether the address is
verified: linking on an unverified address would let anyone who can assert an
email take over an existing account. `User.from_google_omniauth` refuses an
unverified email outright, and a test covers it. An account already linked to a
different Google uid is also refused rather than relinked.

**Passwords are gone, not hidden.** `:database_authenticatable`,
`:registerable`, `:recoverable`, `:confirmable` and `:validatable` are removed
from the model, so `POST /users/sign_in` is not a route any more rather than
being an unadvertised endpoint. `:validatable` went with them because its
password rules assume `:database_authenticatable`; the email presence and
uniqueness validations it provided are now declared on the model.

**Existing password hashes are kept for now.** The migration only relaxes
`encrypted_password` to nullable. Dropping the password, reset and confirmation
columns is a separate migration to run once the Google flow is proven in
production, which follows the project's two-step column-removal rule and leaves
a rollback path.

**Session routes are declared by hand.** Devise only generates them for
`:database_authenticatable`, and removing that module would otherwise take sign
out with it. `Users::SessionsController` is a plain `ApplicationController`
rather than a `Devise::SessionsController`, because that class exists to accept
an email and password.

**Account settings survive.** The Devise registration edit page carried "delete
account" alongside the password form. Removing passwords should not remove a
user's ability to close their account, so `/dashboard/account` replaces it with
the linked Google account, the forwarding address, and account deletion.

**Every signup CTA points at sign-in.** There is no separate signup page, so the
homepage and lookup-limit CTAs link to `new_user_session_path(source: "...")`.
The source rides in the session and is recorded on the `user_registered` event
when the callback creates a user, which keeps signup attribution working.

## Database Changes

Migration `20260917150000_add_google_identity_to_users.rb`:

| Change | Column |
|--------|--------|
| Added | `provider`, `uid` (unique index on the pair) |
| Added | `name`, `avatar_url` from the Google profile |
| Relaxed | `encrypted_password` now nullable, default dropped |

No columns removed. `encrypted_password`, `reset_password_token`,
`reset_password_sent_at`, `confirmation_token`, `confirmed_at`,
`confirmation_sent_at` and `unconfirmed_email` are all unused but still present.

## New Files Created

| File | Purpose |
|------|---------|
| `app/controllers/users/omniauth_callbacks_controller.rb` | Google callback: signs in, links or creates, reports refusals |
| `app/controllers/users/sessions_controller.rb` | Sign-in page and sign out |
| `app/controllers/users/accounts_controller.rb` | Account settings and deletion |
| `app/views/users/sessions/new.html.erb` | The Google button page |
| `app/views/users/accounts/show.html.erb` | Account settings |
| `db/migrate/20260917150000_add_google_identity_to_users.rb` | Google identity columns |
| `test/support/omniauth_test_helper.rb` | Drives the flow through OmniAuth test mode |
| `test/controllers/users/omniauth_callbacks_controller_test.rb` | Signup, linking, and every refusal path |
| `test/controllers/users/sessions_controller_test.rb` | Sign-in page, sign out, removed routes |
| `test/models/user_google_auth_test.rb` | `from_google_omniauth` unit tests |

## Modified Files

| File | Change |
|------|--------|
| `Gemfile` | `omniauth-google-oauth2`, `omniauth-rails_csrf_protection` |
| `app/models/user.rb` | Devise modules swapped; `from_google_omniauth`, `display_name`, email validation; password strength validation removed |
| `config/routes.rb` | `devise_for` reduced to OmniAuth callbacks; sign in/out and `/dashboard/account` declared |
| `config/initializers/devise.rb` | `config.omniauth :google_oauth2` |
| `config/initializers/content_security_policy.rb` | `form-action` allows `https://accounts.google.com` |
| `app/helpers/application_helper.rb` | `auth_page?` covers the new sessions controller; Settings nav points at `account_path` |
| `app/views/layouts/application.html.erb`, `pages/home.html.erb`, `pages/_lookup_result.html.erb`, `product_lookups/quick_result.html.erb` | Signup CTAs point at the Google sign-in page |
| `app/assets/stylesheets/tariffik.css` | `.tf-signin` block |
| `app/assets/stylesheets/tariffik_workspace.css` | `.tf-account-facts` added; password-guidance styles removed |
| `db/seeds.rb` | Admin seed no longer sets a password |
| `test/fixtures/users.yml` | `provider`/`uid` instead of a password digest |
| `test/test_helper.rb` | OmniAuth test mode; `reload_routes_unless_loaded` |
| `test/controllers/pages_controller_test.rb` | Homepage CTA assertions follow the moved destination |
| `.env.example`, `config/deploy.production.yml` | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` |

Deleted: all `app/views/devise/**` templates, `app/controllers/users/registrations_controller.rb`,
`app/javascript/controllers/password_strength_controller.js`.

## Routes

| Method | Path | Action |
|--------|------|--------|
| GET | `/users/sign_in` | `users/sessions#new` |
| DELETE | `/users/sign_out` | `users/sessions#destroy` |
| GET, POST | `/users/auth/google_oauth2` | OmniAuth request phase |
| GET, POST | `/users/auth/google_oauth2/callback` | `users/omniauth_callbacks#google_oauth2` |
| GET | `/dashboard/account` | `users/accounts#show` |
| DELETE | `/dashboard/account` | `users/accounts#destroy` |

Gone: `/users/sign_up`, `POST /users/sign_in`, `/users/password/*`, `/users/confirmation/*`.

## Data Flow

```
/users/sign_in  (Google button, POST — OmniAuth 2 refuses a GET request phase)
      │
      ▼
OmniAuth::Strategies::GoogleOauth2  ──►  accounts.google.com  ──►  /users/auth/google_oauth2/callback
                                                                          │
                                                                          ▼
                                                       User.from_google_omniauth(auth)
                                                             │
        ┌────────────────────────────────────────────────────┼──────────────────────────┐
        ▼                            ▼                       ▼                          ▼
  email unverified          provider + uid match      email matches, no uid        no match
        │                            │                       │                          │
        ▼                            ▼                       ▼                          ▼
  refuse, back to           update profile,           link uid to the            create user
  /users/sign_in            sign in                   existing account           + inbound token
                                     │                       │                          │
                                     └───────────────────────┴──────────────────────────┘
                                                             ▼
                                              sign_in_and_redirect  ──►  /  ──►  /dashboard
```

## Testing / Verification

```bash
bin/rails test                                  # 359 runs, 0 failures
bundle exec rubocop app/ test/ config/ db/      # clean
```

Covered: signup, linking a password-era account, case-insensitive email
matching, a returning user whose Google email changed, unverified email refused,
uid mismatch refused, missing email refused, cancelled sign-in, sign out, the
removed routes returning 404, and the sign-in page containing no password or
email field.

**Flake found and fixed.** The suite failed intermittently with
`404 Not Found` on the first `POST /users/auth/google_oauth2` in a process.
Devise sets `OmniAuth.config.path_prefix` while evaluating `devise_for`, Rails
loads routes lazily under `rails test`, and the OmniAuth middleware runs ahead
of the router — so on a process's first request the prefix was still nil, the
middleware declined the request, and it fell through to Devise's `passthru`.
`test/test_helper.rb` now calls `Rails.application.reload_routes_unless_loaded`.
Verified by reproducing deterministically (a single test run alone failed 3/3),
then 8 consecutive clean full runs. Production eager-loads routes at boot and is
not affected.

### Verified against the real Google flow

Driven in Chrome on 2026-09-17 against `http://localhost:3101` with a live
Google OAuth client:

| Step | Result |
|------|--------|
| `/users/sign_in` → Continue with Google | Redirected to Google with the derived `redirect_uri`, `scope=email profile`, `prompt=select_account` |
| Consent granted | Returned to the app, flash "Successfully authenticated from Google account" |
| **Existing `provider: nil` account** | **Linked, not duplicated** — still one user, same `id`, `created_at` and `inbound_email_token`; tier and admin flag intact; `provider`, `uid`, `name`, `avatar_url` populated from Google |
| `/dashboard/account` | Renders the linked Google account, name, forwarding address and delete control |
| Sign out | Session ended, navbar back to signed-out state |
| Sign in again | Matched on `provider` + `uid`, still one user |
| Consent screen branding | Reads "to continue to Tariffik" |

**Branding gotcha, hit and resolved during this work.** The first run showed
"Sign in to Wager" even though the OAuth client itself belonged to Tariffik. The
name on the consent screen comes from the project's *OAuth consent screen →
Branding → App name*, which is a separate record from both the project name and
the client name, so renaming or deleting things elsewhere does not touch it. The
project is identified by the number prefixing the client ID
(`963033507958-...`), and editing App name there fixed it, visible immediately
on the next request. Nothing in the app sends an app name — only the client ID —
so no code was involved either way.

The callback URL is not configured anywhere. `omniauth-google-oauth2` derives it
(`options[:redirect_uri] || (full_host + callback_path)`), so the same code
produces the localhost URL in development and the tariffik.com one in
production. Both go in Google's authorised redirect URI list; only
`GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` are environment variables.
Production sets `assume_ssl` and `force_ssl`, so `full_host` resolves to
`https://tariffik.com` behind kamal-proxy rather than `http://`, which would
otherwise fail Google's `redirect_uri` check.

### Before deploying

1. Create an OAuth 2.0 Client ID (type: Web application) at
   https://console.cloud.google.com/apis/credentials.
2. Authorised redirect URIs:
   - `http://localhost:3101/users/auth/google_oauth2/callback`
   - `https://tariffik.com/users/auth/google_oauth2/callback`
3. Put `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` in `.env` locally and in
   `.kamal/secrets.production`.
4. Configure the OAuth consent screen and publish it, or only test users can
   sign in. Fill in the homepage, privacy policy and terms URLs; Google requires
   them to move the consent screen out of Testing mode.

## Follow-up: the sign-in page was eating the return path

Found while bringing the browser extension onto this flow (2026-09-17).

`Users::SessionsController#new` called `stored_location_for(:user)`, which
**deletes as it reads** on navigational formats. Rendering the sign-in page
therefore threw away the destination Devise had just stored, and every visitor
sent to sign in from a protected page landed on the dashboard instead of where
they were going. `@after_sign_in` was assigned and never used by the view.

It went unnoticed because the dashboard is where most people wanted to be
anyway. The extension made it visible: `/extension/auth` is the only route that
issues a connection code, so losing the return path meant the extension could
never be connected by a signed-out user.

`new` now puts the location back, and a test walks `/dashboard` and
`/extension/auth` through the full Google round trip.

| File | Change |
|------|--------|
| `app/controllers/users/sessions_controller.rb` | Re-stores the location; sets `@connecting_extension` |
| `app/views/users/sessions/new.html.erb` | Extension-specific heading and lead when that is the destination |
| `app/controllers/extension_auth_controller.rb` | Stamps `session[:signup_source] = "extension"` before `authenticate_user!` |
| `config/locales/devise.en.yml` | `unauthenticated` said "sign in or sign up"; there is no sign-up |
| `test/controllers/users/sessions_controller_test.rb` | Return path, extension round trip, signup source |

Full detail, including the extension side, is in
`claude/implementations/chrome-browser-extension.md`.

## Limitations & Future Improvements

- **A user whose Tariffik email is not a Google account cannot get in.** They
  are not locked out of their data, but moving them needs a manual
  `provider`/`uid`/`email` update. Worth counting affected accounts in
  production before deploying.
- **Password and confirmation columns still exist.** Drop them in a follow-up
  migration once this is proven in production.
- **`render.yaml` was not updated.** It is already stale (it still references
  Cloudflare R2, which the Hetzner/Kamal setup replaced), so the Google
  credentials were added to `config/deploy.production.yml` only.
- **Google is the only provider.** `omniauth_providers` takes a list, so adding
  another is small, but every "sign in" affordance currently says Google.
- **No admin path for relinking.** Changing which Google account owns a Tariffik
  account means a console edit or deleting and starting again.
