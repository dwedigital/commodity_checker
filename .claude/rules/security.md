---
paths:
  - "config/initializers/content_security*"
  - "config/initializers/secure_headers*"
---

# Security Configuration

## Content Security Policy (CSP)

Configured in `config/initializers/content_security_policy.rb`.

```
default-src 'self'; font-src 'self' data:; img-src 'self' https: http: data: blob: localhost;
object-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline';
connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'
```

Key protections:
- `script-src 'self'` - Only scripts from same origin (no inline JS allowed)
- `frame-ancestors 'none'` - Prevents clickjacking
- `object-src 'none'` - Blocks Flash/plugins
- `img-src` includes `blob:` for camera previews, `http:` and localhost for Active Storage

**Important:** CSP blocks inline JavaScript. Use Stimulus controllers instead of `onclick` handlers or `<script>` tags.

**Troubleshooting:** Check browser console for CSP errors. Enable report-only mode temporarily by uncommenting `config.content_security_policy_report_only = true`.

## Security Headers

Configured in `config/initializers/secure_headers.rb`.

| Header | Value | Purpose |
|--------|-------|---------|
| X-Frame-Options | DENY | Clickjacking protection |
| X-Content-Type-Options | nosniff | Prevent MIME sniffing |
| Referrer-Policy | strict-origin-when-cross-origin | Control referrer leakage |
| Permissions-Policy | camera=(self), others disabled | Control browser API access |

`camera=(self)` is enabled for the Photo Lookup feature. HSTS is automatically added by Rails when `force_ssl = true`.

## Verification

```bash
bin/rails runner "puts Rails.application.config.content_security_policy.build(nil)"
curl -I https://tariffik.com | grep -E "(Content-Security|X-Frame|X-Content-Type)"
```
