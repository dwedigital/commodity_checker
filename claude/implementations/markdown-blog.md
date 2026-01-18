# Markdown Blog Implementation

## Overview

Added a lightweight, file-based blog system to Tariffik for marketing and SEO content around commodity codes. Blog posts are authored as markdown files with YAML front matter - no database or CMS required.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Content storage | `content/blog/` at repo root | Separate from app code, easy to find/edit |
| Markdown rendering | `redcarpet` gem | Fast, mature, GitHub-flavored markdown support |
| Syntax highlighting | `rouge` gem | Pure Ruby, no external dependencies, many themes |
| URL structure | `/blog`, `/blog/:slug` | Clean, SEO-friendly URLs |
| Images | `public/images/blog/` | Simple static files, no Active Storage overhead |
| Filtering | Production-only published filter | Allows preview of drafts in development |

## Database Changes

None - this feature is entirely file-based.

## New Files Created

| File | Purpose |
|------|---------|
| `app/services/blog_post_service.rb` | Service to load, parse, and render markdown blog posts |
| `app/helpers/blog_helper.rb` | Helper methods for SEO (JSON-LD, reading time, absolute URLs) |
| `app/controllers/blog_controller.rb` | Controller with index and show actions |
| `app/views/blog/index.html.erb` | Blog listing page (minimalist list design) |
| `app/views/blog/show.html.erb` | Single post view with hero image and SEO meta tags |
| `app/views/blog/_post_card.html.erb` | Partial for post list item (title, date, excerpt, tags) |
| `content/blog/.keep` | Placeholder to ensure directory is tracked in git |
| `content/blog/understanding-uk-commodity-codes.md` | Beginner's guide to commodity codes |
| `content/blog/commodity-codes-for-electronics.md` | Electronics-specific commodity code guide |
| `public/images/blog/.keep` | Placeholder for blog hero images directory |

## Modified Files

| File | Change |
|------|--------|
| `Gemfile` | Added `redcarpet` and `rouge` gems |
| `config/routes.rb` | Added `/blog` and `/blog/:slug` routes |
| `app/views/shared/_footer.html.erb` | Added "Blog" link |
| `app/views/layouts/application.html.erb` | Added flexbox sticky footer (min-h-screen, flex, grow) |

## Routes

| Method | Path | Controller#Action | Named Route |
|--------|------|-------------------|-------------|
| GET | `/blog` | `blog#index` | `blog_path` |
| GET | `/blog/:slug` | `blog#show` | `blog_post_path(slug)` |

## Data Flow

### Blog Post Rendering Flow

```
content/blog/*.md
        │
        ▼
BlogPostService.all / find_by_slug
        │
        ├─► Parse YAML front matter (title, date, description, tags, etc.)
        │
        ├─► Filter unpublished posts (production only)
        │
        ├─► Render markdown with Redcarpet
        │         │
        │         └─► RougeRenderer for syntax highlighting
        │
        └─► Return BlogPost struct(s)
                │
                ▼
        BlogController
                │
                ├─► index: @posts = BlogPostService.all
                │
                └─► show: @post = BlogPostService.find_by_slug!(slug)
                          │
                          └─► 404 if not found (ActiveRecord::RecordNotFound)
```

### Front Matter Format

```yaml
---
title: "Post Title"
slug: post-slug
date: 2026-01-17
description: "SEO description for the post"
hero_image: /images/blog/hero.jpg
author: Tariffik Team
published: true
tags:
  - commodity-codes
  - importing
---

Markdown content here...
```

## SEO Features

The blog includes comprehensive SEO support:

- **Dynamic `<title>`** - Post title + "Tariffik Blog"
- **Meta description** - From post front matter
- **Canonical URL** - Full URL to the post
- **Open Graph tags** - Title, description, image, type, URL, published time, author, tags
- **Twitter Card** - Summary large image with title, description, image
- **JSON-LD structured data** - BlogPosting schema for rich search results

## Testing/Verification

### Manual Testing Steps

1. Run `bundle install` to add gems
2. Start server with `bin/dev`
3. Visit `/blog` - should see post listing with card grid
4. Click a post card - should see full article with styling
5. Check page source for SEO meta tags and JSON-LD
6. Test 404: `/blog/nonexistent-slug` - should show Rails 404 page
7. Test mobile viewport for responsive layout
8. Verify footer shows "Blog" link

### Verification Commands

```bash
# Verify gems installed
bundle list | grep -E "redcarpet|rouge"

# Verify routes
bin/rails routes | grep blog

# Test service loads posts
bin/rails runner "puts BlogPostService.all.map(&:title)"

# Test finding by slug
bin/rails runner "puts BlogPostService.find_by_slug('understanding-uk-commodity-codes').title"
```

## Adding New Blog Posts

1. Create a new `.md` file in `content/blog/`
2. Add YAML front matter with required fields (title, slug, date, description)
3. Write content in markdown below the front matter
4. Optionally add a hero image to `public/images/blog/`
5. Set `published: true` when ready (false to keep as draft)

## Limitations & Future Improvements

### Current Limitations

- No pagination (fine for small number of posts)
- No tag filtering/archive pages
- No search functionality
- No RSS feed
- Hero images must be manually added to `public/images/blog/`

### Potential Future Enhancements

- Add pagination when post count exceeds 10-12
- Implement tag-based filtering (`/blog/tags/commodity-codes`)
- Add RSS/Atom feed for subscribers
- Archive page by year/month
- Related posts suggestions
- Reading progress indicator
- Social sharing buttons
- Comment system (Disqus, Utterances, or custom)
