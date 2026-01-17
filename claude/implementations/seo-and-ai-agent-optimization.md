# SEO and AI Agent Optimization Implementation

## Overview

Added SEO improvements and AI agent accessibility features to improve search engine visibility and help AI assistants understand and accurately describe the site.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Sitemap | Dynamic route vs static file | Auto-includes new blog posts without manual updates |
| llms.txt | Plain text format | Follows emerging convention, easy for LLMs to parse |
| robots.txt | Allow all | No reason to block crawlers; site is public |

## Database Changes

None - all features are file-based or dynamic routes.

## New Files Created

| File | Purpose |
|------|---------|
| `app/controllers/sitemap_controller.rb` | Generates dynamic XML sitemap |
| `app/views/sitemap/index.xml.builder` | XML builder template for sitemap |
| `public/llms.txt` | Plain-text site description for AI agents |

## Modified Files

| File | Change |
|------|--------|
| `public/robots.txt` | Added sitemap reference and llms.txt comment |
| `config/routes.rb` | Added `/sitemap.xml` route |

## Routes

| Method | Path | Controller#Action | Purpose |
|--------|------|-------------------|---------|
| GET | `/sitemap.xml` | `sitemap#index` | Dynamic XML sitemap |

## Data Flow

### Sitemap Generation

```
Request to /sitemap.xml
        ↓
SitemapController#index
        ↓
├── Load static pages (root, blog, privacy, terms)
│
└── Load blog posts via BlogPostService.all
        ↓
Render XML via index.xml.builder
        ↓
Return sitemap with all URLs + lastmod dates
```

## File Contents

### robots.txt

```
User-agent: *
Allow: /

Sitemap: https://tariffik.com/sitemap.xml
```

### llms.txt Structure

The llms.txt file includes:
- Site name and tagline
- What Tariffik does
- Core features list
- How the service works
- Commodity code explanation
- Useful page URLs
- Blog topic overview
- Technical notes for AI agents

### Sitemap Structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://tariffik.com/</loc>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>https://tariffik.com/blog</loc>
    <changefreq>weekly</changefreq>
    <priority>0.8</priority>
  </url>
  <!-- Blog posts with lastmod dates -->
  <url>
    <loc>https://tariffik.com/blog/post-slug</loc>
    <lastmod>2026-01-17T00:00:00Z</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.7</priority>
  </url>
  <!-- Privacy, Terms with lower priority -->
</urlset>
```

## Testing/Verification

### Manual Testing Steps

1. Visit `/robots.txt` - should show sitemap reference
2. Visit `/sitemap.xml` - should show XML with all pages
3. Visit `/llms.txt` - should show plain text site description
4. Add a new blog post, refresh `/sitemap.xml` - should include new post

### Verification Commands

```bash
# Check routes
bin/rails routes | grep sitemap

# Verify sitemap controller exists
ls app/controllers/sitemap_controller.rb

# Check files exist
ls public/robots.txt public/llms.txt
```

### Testing with Search Console

1. Submit sitemap URL to Google Search Console
2. Check for crawl errors
3. Verify pages are being indexed

## SEO Checklist

- [x] robots.txt allows crawling
- [x] sitemap.xml includes all public pages
- [x] sitemap auto-updates with new blog posts
- [x] llms.txt describes site for AI agents
- [x] Blog posts have Open Graph meta tags
- [x] Blog posts have Twitter Card meta tags
- [x] Blog posts have JSON-LD structured data
- [x] Blog posts have canonical URLs

## Limitations & Future Improvements

### Current Limitations

- Sitemap doesn't include `<image:image>` tags for blog hero images
- No sitemap index (not needed until 50,000+ URLs)
- llms.txt is manually maintained

### Potential Future Enhancements

- Add image sitemap entries
- Auto-generate llms.txt sections from blog content
- Add hreflang tags if multi-language support added
- News sitemap for blog (if publishing frequently)
- Submit sitemap to Bing, Yandex, etc.
