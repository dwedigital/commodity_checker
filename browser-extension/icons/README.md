# Extension Icons

| File | Size | Used for |
|------|------|----------|
| `icon16.png` | 16×16 | Toolbar |
| `icon48.png` | 48×48 | Extensions page |
| `icon128.png` | 128×128 | Chrome Web Store |

## The mark

The September 2026 refresh's `↗` mark: a red (`#d93120`) rounded square with a
white north-east arrow, the same mark as `.tf-logo-mark` in the wordmark and as
the website favicon (`public/icon.svg`).

`icon48` and `icon128` are rendered from `public/icon.svg`. `icon16` uses a
tuned variant — a larger arrow, a heavier shaft and a tighter corner radius —
because the standard geometry turns to mush at 16px.

## Regenerating

```bash
# 48 and 128 come straight from the site favicon
rsvg-convert -w 48  -h 48  -o browser-extension/icons/icon48.png  public/icon.svg
rsvg-convert -w 128 -h 128 -o browser-extension/icons/icon128.png public/icon.svg

# 16 needs the tuned geometry
cat > /tmp/mark16.svg <<'SVG'
<svg width="512" height="512" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
  <rect width="512" height="512" rx="64" fill="#d93120"/>
  <g fill="#ffffff">
    <path d="M136 376 L288 224 L300 236 L148 388 Z" stroke="#ffffff" stroke-width="80" stroke-linejoin="round" stroke-linecap="butt"/>
    <path d="M186 130 L382 130 L382 326 Z" stroke="#ffffff" stroke-width="24" stroke-linejoin="round"/>
  </g>
</svg>
SVG
rsvg-convert -w 16 -h 16 -o browser-extension/icons/icon16.png /tmp/mark16.svg
```

`rsvg-convert` is librsvg (`brew install librsvg`). ImageMagick's own SVG
renderer produces a worse result, so go through librsvg.
