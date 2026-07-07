# PWA Support (Add to Home Screen)

## Overview

Wired up the Rails 8 PWA scaffold so Tariffik installs properly as a home-screen app on iOS and Android: a served web app manifest, a registered (minimal) service worker, correct meta tags, and a branded app icon replacing the Rails default red-dot placeholder.

## Design Decisions

- **Use the built-in Rails 8 PWA scaffold** (`Rails::PwaController` + `app/views/pwa/`) rather than static files in `public/` — the manifest stays an ERB template if we ever need per-environment values.
- **Minimal service worker, no caching/fetch handler.** Modern Chrome no longer requires a fetch handler for installability, and an empty one adds latency to every request. Turbo + cached HTML is also a footgun. The SW exists (and is registered) so Web Push can be added later by uncommenting the scaffold code in `app/views/pwa/service-worker.js`.
- **SW registration lives in `app/javascript/application.js`** — CSP blocks inline scripts (`script-src 'self'`), so registration must be in an external importmap-served file.
- **`theme_color`/`background_color` are white (`#ffffff`)** to match the white navbar/site chrome (a coloured status bar band above the white nav looks broken).
- **Icon is drawn geometry, not text** — a rounded white "T" on brand red `#E3170A`, built from two rounded rects so no font is needed at render time and the glyph sits inside the maskable safe zone (inner 80% circle) for Android adaptive icons. One 512×512 PNG serves `any` + `maskable` + apple-touch-icon.

## Database Changes

None.

## New Files Created

| File | Purpose |
|------|---------|
| _none_ | (scaffold files already existed) |

## Modified Files

| File | Change |
|------|--------|
| `config/routes.rb` | Added `GET /manifest` and `GET /service-worker` → `rails/pwa#*` |
| `app/views/pwa/manifest.json.erb` | Real values: name/short_name/description, `id`, `display: standalone`, white theme/background colours, icon entries (`any` + `maskable`) |
| `app/views/layouts/application.html.erb` | Added `<link rel="manifest" href="/manifest.json">`, `<meta name="theme-color">`, `<meta name="apple-mobile-web-app-title">` |
| `app/javascript/application.js` | Registers `/service-worker` when supported |
| `public/icon.png` | Branded 512×512 icon (white T on `#E3170A`), replaces Rails default red circle |
| `public/icon.svg` | Matching SVG favicon (red circle variant of the same mark) |

## Routes

| Method | Path | Controller |
|--------|------|-----------|
| GET | `/manifest(.json)` | `rails/pwa#manifest` |
| GET | `/service-worker` | `rails/pwa#service_worker` |

## Data Flow

```
Browser → GET /manifest.json → Rails::PwaController#manifest → app/views/pwa/manifest.json.erb
Browser → GET /service-worker → Rails::PwaController#service_worker → app/views/pwa/service-worker.js
application.js → navigator.serviceWorker.register("/service-worker")  (scope "/")
```

## Testing/Verification

```bash
bin/rails routes -g pwa                       # both routes present
curl -si localhost:3000/manifest.json         # 200 application/json
curl -si localhost:3000/service-worker        # 200 text/javascript
```

On a phone: Share → Add to Home Screen (iOS) / install prompt or ⋮ → Add to Home screen (Android). App should open standalone (no browser chrome) with the red T icon. In Chrome DevTools: Application → Manifest shows no warnings.

## Limitations & Future Improvements

- No offline support — the SW has no fetch handler by design. Add a cache strategy only if an offline page is genuinely wanted.
- Web Push is scaffolded but commented out in `service-worker.js`.
- Regenerate the icon via Pillow (two `rounded_rectangle` calls on `#E3170A`) if the brand mark changes; keep glyph inside the centre-40%-radius circle for maskable safety.
