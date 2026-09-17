# Email/Password and Google Auth Implementation

**Date:** 2026-09-17
**Feature:** Email and password sign-in restored alongside Sign in with Google, with email verification

## Overview

Tariffik accepts two ways in: an email and password, or Sign in with Google. A
password signup has to confirm its address before the account works. A Google
signup does not, because Google has already verified it.

Supersedes the Google-only decision in `google-oauth-only-login.md`. That change
locked out every account that had not moved to Google; this restores them —
production had 11 accounts, 10 of which had a password and no Google identity.

## Design Decisions

**A Google-only account cannot get a password by email.** Password reset checks
first: if the account has a Google identity and no password, it says so instead
of sending a link. Otherwise anyone holding the inbox could set a password and
step around whatever protections Google has on that account, including 2FA.

**An address that already signs in with Google cannot be claimed by a signup.**
The registration is refused and points at the Google button. Knowing someone's
address should not be enough to attach a credential to their account. They add a
password from account settings instead, while signed in.

**Setting a first password needs no current password; changing one does.** A
Google user has nothing to prove with — the session is the proof, and Google
created it. Once a password exists, changing it requires the old one.

**No unconfirmed grace period.** Devise ships `allow_unconfirmed_access_for =
2.days`, which lets someone use the app before confirming and makes the
verification step advisory. It is now `0.days`.

**Google updates skip reconfirmation.** `:reconfirmable` would park a changed
Google address in `unconfirmed_email` and email a link, leaving the account on
its old address — when Google has already verified the new one. Linking Google
to an existing password account also sets `confirmed_at`, whether or not that
person ever clicked our email.

**`password_required?` and `confirmation_required?` are overridden**, because
`:validatable` demands a password from every new record and `:confirmable` would
hold a Google signup at the door for an email it never needs.

## Database Changes

None. The columns were deliberately left in place when the modules were removed,
and `encrypted_password` was already nullable, which is exactly what dual auth
needs.

## New Files Created

| File | Purpose |
|------|---------|
| `app/controllers/users/registrations_controller.rb` | Signup, with source attribution |
| `app/helpers/mailer_helper.rb` | Inline styles for email; clients strip `<style>` |
| `app/views/devise/sessions`… `registrations`, `passwords`, `confirmations` | Sign up, reset, resend confirmation |
| `app/views/devise/shared/_google_button.html.erb` | The Google button, shared by sign in and sign up |
| `app/views/devise/shared/_error_messages.html.erb` | Form errors |
| `app/views/devise/mailer/*` | Confirmation, reset, password changed, email changed, unlock |
| `config/locales/auth.en.yml` | The two refusal messages |
| `test/integration/password_auth_test.rb` | Signup, confirmation, reset, collisions, setting a password |

## Modified Files

| File | Change |
|------|--------|
| `app/models/user.rb` | Devise modules restored; `password_set?`, `google_linked?`, `google_only?`; `password_required?`, `confirmation_required?`, `send_reset_password_instructions` overrides; signup collision check; password strength rules |
| `app/controllers/users/sessions_controller.rb` | Back to `Devise::SessionsController`, keeping the stored-location handling the Google round trip needs and `@connecting_extension` |
| `app/controllers/users/accounts_controller.rb` | `update_password` |
| `app/views/users/sessions/new.html.erb` | Google button plus an email and password form |
| `app/views/users/accounts/show.html.erb` | Password panel; wording adapts to which methods the account has |
| `app/mailers/application_mailer.rb`, `config/initializers/devise.rb` | `parent_mailer`, so Devise's mail gets the Tariffik layout and helpers; no unconfirmed grace period |
| `app/views/layouts/mailer.html.erb` | Branded email shell |
| `config/locales/devise.en.yml` | Subjects name Tariffik |
| `config/routes.rb` | Session, registration, password and confirmation routes back; `account/password` |
| Home and lookup CTAs | Point at sign up again |

## Data Flow

```
Sign up (email + password)            Sign in with Google
      │                                     │
      ▼                                     ▼
 email already                        verified email?
 signs in with Google? ──yes──► refuse      │
      │ no                                  ▼
      ▼                          provider+uid match ──► sign in
 create, confirmed_at nil                   │
      │                          email matches ──► link, set confirmed_at,
      ▼                                            keep any existing password
 confirmation email                         │
      │                                     ▼
      ▼                                 create, confirmed_at set
 click link ──► confirmed ──► can sign in

Forgot password
      │
      ▼
 account has a password? ──no, Google-only──► "signs in with Google"
      │ yes
      ▼
 send reset link
```

## Testing / Verification

```bash
bin/rails test        # 402 runs, 0 failures
bundle exec rubocop   # clean
```

Driven locally in a browser: signed up through the form, confirmed the account
was created with `confirmed_at: nil` and `active_for_authentication?: false`,
took the link out of the confirmation email, visited it, and watched
`confirmed_at` fill in and `active_for_authentication?` flip to true. The
rendered email was reviewed in the browser.

Tests cover: signup sends one email and does not sign you in, an unconfirmed
account cannot reach the dashboard, confirming opens it, weak passwords are
refused, a signup on a Google address is refused, Google linking keeps an
existing password and confirms the address, reset works with a password and
refuses a Google-only account, a first password needs no current password, and
changing one does.

### Caught while building

- The sign-in page lives at `app/views/users/sessions/new.html.erb`, not
  `devise/sessions/new`, because `Users::SessionsController` sits earlier in the
  view lookup. A new `devise/sessions/new.html.erb` was silently ignored.
- `:reconfirmable` swallowed a changed Google email until a test caught it.
- Devise's `content_security_policy`-style DSLs and `require_no_authentication`
  run as before_actions, so the already-signed-in redirect needed
  `prepend_before_action`.

## Limitations & Future Improvements

- **Plain-text email parts are missing.** Every Devise mail is HTML only, which
  costs deliverability. Adding `.text.erb` alongside each template is small and
  worth doing.
- **Password reset tells you whether an address has an account.** Saying "this
  one signs in with Google" reveals the account exists. Devise's `paranoid` mode
  would hide it, at the cost of that guidance. The app already enumerated this
  way before, so it is not a regression.
- **No way to unlink Google** once linked, short of deleting the account.
- **7 production accounts have never confirmed.** They could not sign in before
  today either, so nothing changed for them, but they will need to confirm or be
  cleaned up.
