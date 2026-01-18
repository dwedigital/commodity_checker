# Security Headers & Content Security Policy Implementation

**Date:** 2026-01-17
**Feature:** Enable Content Security Policy and security headers for XSS/clickjacking protection

## Overview

This implementation adds two critical security layers to protect against common web vulnerabilities:

1. **Content Security Policy (CSP)** - Restricts which resources (scripts, styles, images, etc.) the browser can load, providing defense-in-depth against XSS attacks
2. **Security Headers** - Additional HTTP headers that instruct browsers to enable security features and restrict dangerous behaviors

## Design Decisions

- **Strict CSP defaults** - Only allow resources from same origin by default
- **Tailwind compatibility** - `unsafe-inline` for styles required by Tailwind CSS
- **Nonce support** - Script nonces enabled for future inline script security
- **No external CDNs** - App uses Rails importmaps (self-hosted), so no external script sources needed
- **Separate initializer** - Security headers in dedicated file for clarity and maintainability
- **HSTS via force_ssl** - Rely on Rails' built-in HSTS when `force_ssl = true`

## Database Changes

None - configuration only.

## New Files Created

| File | Purpose |
|------|---------|
| `config/initializers/secure_headers.rb` | Configures X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy |
| `app/javascript/controllers/tabs_controller.js` | Stimulus controller for tab switching (replaces inline JS blocked by CSP) |

## Modified Files

| File | Change |
|------|--------|
| `config/initializers/content_security_policy.rb` | Enabled and configured CSP (was commented out) |
| `app/views/product_lookups/new.html.erb` | Converted inline JS tabs to Stimulus controller |

## Configuration Details

### Content Security Policy

```ruby
# config/initializers/content_security_policy.rb
config.content_security_policy do |policy|
  policy.default_src :self
  policy.font_src    :self, :data
  policy.img_src     :self, :https, :http, :data, :blob, "http://localhost:3000", "http://127.0.0.1:3000"
  policy.object_src  :none
  policy.script_src  :self
  policy.style_src   :self, :unsafe_inline  # Tailwind CSS requires unsafe-inline
  policy.connect_src :self
  policy.frame_ancestors :none
  policy.base_uri    :self
  policy.form_action :self
end
```

**Note on img-src:** The extended `img-src` directive includes:
- `:blob` - Required for camera capture image previews (uses `URL.createObjectURL`)
- `:http` and explicit localhost URLs - Required for Active Storage in development (localhost vs 127.0.0.1 origin mismatch)

**Resulting Header:**
```
Content-Security-Policy: default-src 'self'; font-src 'self' data:; img-src 'self' https: http: data: blob: http://localhost:3000 http://127.0.0.1:3000; object-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'
```

### Security Headers

```ruby
# config/initializers/secure_headers.rb
Rails.application.config.action_dispatch.default_headers = {
  "X-Frame-Options" => "DENY",
  "X-Content-Type-Options" => "nosniff",
  "Referrer-Policy" => "strict-origin-when-cross-origin",
  "Permissions-Policy" => "accelerometer=(), camera=(self), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"
}
```

**Note:** `camera=(self)` is enabled to support the Photo Lookup feature which uses the device camera.

## Security Protections

| Header/Directive | Protection Against |
|------------------|-------------------|
| `script-src 'self'` | XSS via injected scripts |
| `frame-ancestors 'none'` | Clickjacking |
| `object-src 'none'` | Flash/plugin-based attacks |
| `base-uri 'self'` | Base tag injection |
| `form-action 'self'` | Form hijacking |
| `X-Frame-Options: DENY` | Clickjacking (legacy browsers) |
| `X-Content-Type-Options: nosniff` | MIME-type sniffing attacks |
| `Referrer-Policy` | Referrer information leakage |
| `Permissions-Policy` | Unauthorized feature access |

## Data Flow

```
Browser Request
       │
       ▼
Rails Middleware (ActionDispatch::ContentSecurityPolicy)
       │
       ├─── Adds Content-Security-Policy header
       │
       ▼
Rails Middleware (ActionDispatch::Response)
       │
       ├─── Adds X-Frame-Options header
       ├─── Adds X-Content-Type-Options header
       ├─── Adds Referrer-Policy header
       └─── Adds Permissions-Policy header
       │
       ▼
Response to Browser
       │
       ▼
Browser enforces all policies
```

## Testing/Verification

### Manual Testing Steps

1. Start the server: `bin/dev`
2. Open browser DevTools → Network tab
3. Load any page and inspect response headers
4. Verify all security headers are present

### Verification Commands

```bash
# Check CSP is configured
bin/rails runner "puts Rails.application.config.content_security_policy.build(nil)"

# Check security headers
bin/rails runner "puts Rails.application.config.action_dispatch.default_headers.to_json"

# Test in production (after deploy)
curl -I https://tariffik.com | grep -E "(Content-Security|X-Frame|X-Content-Type|Referrer-Policy|Permissions-Policy)"
```

### Expected Output

```
Content-Security-Policy: default-src 'self'; font-src 'self' data:; ...
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: accelerometer=(), camera=(), ...
```

## Troubleshooting

### If functionality breaks after enabling CSP

1. Uncomment report-only mode in `content_security_policy.rb`:
   ```ruby
   config.content_security_policy_report_only = true
   ```
2. Check browser console for CSP violation errors
3. Add necessary sources to the violated directive
4. Re-enable enforcement once fixed

### Common CSP Issues

| Error | Solution |
|-------|----------|
| Inline script blocked | Convert to Stimulus controller (preferred) or add nonce |
| Inline onclick handlers | Convert to Stimulus `data-action` attributes |
| Camera permission denied | Ensure `camera=(self)` in Permissions-Policy |
| Blob image preview broken | Add `:blob` to `img-src` |
| Active Storage image broken | Check localhost vs 127.0.0.1 origin mismatch |
| External font blocked | Add font CDN to `font_src` |
| Iframe embed blocked | Add source to `frame_src` (not currently configured) |

### Inline JS to Stimulus Migration

When CSP blocks inline JavaScript (onclick handlers, `<script>` tags), convert to Stimulus:

**Before (blocked by CSP):**
```html
<button onclick="switchTab('photo')">Photo</button>
<script>
  function switchTab(tab) { /* ... */ }
</script>
```

**After (CSP compliant):**
```html
<div data-controller="tabs">
  <button data-action="click->tabs#switch" data-tab="photo">Photo</button>
</div>
```

```javascript
// app/javascript/controllers/tabs_controller.js
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  switch(event) {
    const tab = event.currentTarget.dataset.tab
    // ...
  }
}
```

## Limitations & Future Improvements

### Current Limitations

- **Tailwind requires unsafe-inline** - Cannot fully lock down `style_src` without refactoring Tailwind usage
- **No CSP violation reporting** - Violations aren't logged (could add `/csp-violation-report` endpoint)
- **No subresource integrity** - External resources don't have SRI hashes (not needed since no CDN usage)

### Potential Future Improvements

1. **CSP reporting endpoint** - Log violations to detect attacks or misconfigurations
2. **Nonce for styles** - If Tailwind is compiled to external stylesheet, remove `unsafe-inline`
3. **HSTS preload** - Submit domain to HSTS preload list for maximum protection
4. **Report-To header** - Modern replacement for CSP report-uri
5. **Regular security audits** - Run `brakeman` and check headers periodically

## Files Summary

### New Files (2)
- `config/initializers/secure_headers.rb`
- `app/javascript/controllers/tabs_controller.js`

### Modified Files (2)
- `config/initializers/content_security_policy.rb`
- `app/views/product_lookups/new.html.erb`
