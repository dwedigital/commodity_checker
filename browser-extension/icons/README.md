# Extension Icons

This folder should contain PNG icons for the Chrome extension:

- `icon16.png` - 16x16 pixels (toolbar icon small)
- `icon48.png` - 48x48 pixels (extensions page)
- `icon128.png` - 128x128 pixels (Chrome Web Store)

## Creating Icons

Use the Tariffik logo/branding with the following specifications:

1. **Background**: Indigo gradient (#4f46e5 to #7c3aed)
2. **Symbol**: White "T" or barcode/tariff-related icon
3. **Border radius**: Rounded (16px for 128, 8px for 48, 4px for 16)

## Placeholder Generation

For development, you can generate placeholder icons using ImageMagick:

```bash
# Create 128x128 with indigo background
convert -size 128x128 xc:'#4f46e5' -fill white -pointsize 72 -gravity center -annotate 0 'T' icon128.png

# Create 48x48
convert -size 48x48 xc:'#4f46e5' -fill white -pointsize 32 -gravity center -annotate 0 'T' icon48.png

# Create 16x16
convert -size 16x16 xc:'#4f46e5' -fill white -pointsize 12 -gravity center -annotate 0 'T' icon16.png
```

Or use an online tool like:
- https://realfavicongenerator.net/
- https://www.favicon-generator.org/
