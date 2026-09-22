# The arrow is drawn, not typed

**Date:** 2026-09-22
**Feature:** U+2197 replaced by an SVG everywhere it was rendered

## Overview

Every north-east arrow on the site — the square in the wordmark, the oversized
mark behind the final CTA, and the small arrows trailing button and link labels
— was the character `↗` (U+2197). On iPhone they all rendered as a blue **colour
emoji**, including inside the red brand square.

They are now drawn: an inline SVG through the `tf_arrow` helper, a background
SVG for `.tf-logo-mark`, and a CSS mask for the one pseudo-element that cannot
hold markup. Nothing depends on a font having the glyph.

## Root cause, verified

Two facts have to line up, and both did:

| Font | Contains U+2197? |
|------|------------------|
| Arial (`.tf-logo-mark` asked for it by name) | **no** |
| Helvetica | **no** |
| Space Grotesk / Plus Jakarta Sans (Google Fonts latin subsets) | no — arrows are not in the latin subset |
| Apple Color Emoji | **yes** |

Checked with fontTools against the macOS system fonts. So the character always
fell through to OS fallback. U+2197 also carries an emoji presentation, and on
iOS the first fallback font that has it is Apple Color Emoji — hence a blue
emoji arrow. macOS has monochrome fallbacks that win first, which is why desktop
screenshots looked fine and this survived review.

A full sweep of non-ASCII characters in the views and stylesheets found only two
other emoji-capable codepoints: `©`, which is safe because Arial has it, and `⚠`,
which only appears in a CLAUDE.md. `↳ ✓ ⧉ ◎` are also missing from Arial but have
no emoji form, so they fall back to a monochrome symbol font — off-font, not
wrong. Left alone.

## New Files Created

| File | Purpose |
|------|---------|
| `claude/implementations/drawn-arrow-mark.md` | This document |

## Modified Files

| File | Change |
|------|--------|
| `app/helpers/application_helper.rb` | `tf_arrow(classes:)` returns the inline SVG; `currentColor` and a 1em box make it a drop-in for the character |
| `app/assets/stylesheets/tariffik.css` | `.tf-logo-mark` draws the arrow as a background SVG (the favicon's own outline, so tab icon and wordmark agree); `.tf-arrow` sizing; `--tf-arrow-mask` for pseudo-elements; `.tf-cta-mark` and the consent mark sized in px rather than font-size |
| 16 view templates | Every `↗` replaced by `tf_arrow`, `safe_join` where the arrow rode inside a `link_to` label string |
| `browser-extension/styles/brand.css` | Same `.tf-logo-mark` background and `.tf-arrow` rule |
| `browser-extension/sidepanel/sidepanel.html`, `callback/callback.html` | Inline SVG in place of the character |
| `CLAUDE.md`, `app/views/CLAUDE.md` | The rule: use `tf_arrow`, never the character |

## Two things that bit during the work

**Tailwind preflight sets `svg { display: block }.`** Every arrow jumped onto its
own line — the footer read "Say hello" with the arrow stranded underneath.
`.tf-arrow` carries an explicit `display: inline-block`, which is load-bearing;
do not remove it.

**A label and its arrow are one unit.** The space between them is now `&nbsp;`
(19 sites), so a narrow column breaks earlier in the label instead of orphaning
the arrow. Caught on a 390px render, not by reading the code.

## Testing / Verification

```bash
bin/rails test        # 458 runs, 0 failures
bundle exec rubocop   # clean
```

The decisive check is that the character cannot reach the browser at all:

```bash
curl -s localhost:3101/ | grep -c $'↗'   # 0
```

`/`, `/blog`, `/users/sign_in` and `/users/sign_up` all return 200 with zero
U+2197 and the expected count of `class="tf-arrow"` SVGs. Rendered at 390px
(iPhone width) and 1280px and inspected: wordmark square, trust strip, footer
link and the CTA mark all draw correctly.

**Not verified:** the result on a real iPhone. The fix removes the character
entirely, so there is no glyph left to fall back to an emoji font — but the
original report came from a device I cannot test on.

**Unrelated finding:** the long-running dev server on port 3101 returns 500 on
`/users/sign_in` with `undefined method 'session_path'`. It booted on 17 Sep at
16:27, before `024e793` re-added `:database_authenticatable` that evening, so its
routes are stale. A restart clears it; nothing in the app is wrong.

## Limitations & Future Improvements

- `↳ ✓ ⧉ ◎` still rely on font fallback. They cannot become emoji, but they do
  render in whatever symbol font the OS picks, so they will not match the brand
  typeface. Worth the same treatment if they ever look wrong.
- The arrow outline is now written out in three places: the helper, the
  `.tf-logo-mark` background, and `--tf-arrow-mask`. They are deliberately
  different weights (text, mark, mask) but share a shape; change them together.
