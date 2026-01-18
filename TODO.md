# Tariffik - Potential Developments & Feature Enhancements

This document tracks potential future developments for Tariffik, organized by priority and category.

---

## High Priority - Revenue & Growth

### Stripe Integration for Subscriptions
- [ ] Set up Stripe account and webhooks
- [ ] Implement subscription checkout flow
- [ ] Handle subscription lifecycle (upgrades, downgrades, cancellations)
- [ ] Replace "Contact us" with pricing and checkout buttons
- [ ] Add billing portal for customers to manage subscriptions

### MCP Server for Agentic Integration
- [ ] Build Model Context Protocol (MCP) server
- [ ] Expose commodity code lookup as MCP tool
- [ ] Support batch lookups via MCP
- [ ] Create documentation for AI agent developers
- [ ] Add to Claude Desktop, Cursor, and other MCP-compatible tools

### API Documentation Page
- [ ] Interactive API explorer with try-it-now functionality
- [ ] Code examples in multiple languages (curl, Python, JavaScript, Ruby)
- [ ] Authentication flow walkthrough
- [ ] Rate limit explanation by tier
- [ ] Webhook setup guide

---

## Medium Priority - User Experience

### Photo Lookup Improvements
- [ ] Image cropping/adjustment before submission
- [ ] Multi-image support (2-3 angles for better identification)
- [ ] Image quality indicator before submission
- [ ] Example photos showing "good" vs "bad" product photos
- [ ] Guest photo lookup (limited free lookups)
- [ ] Barcode/QR code scanning when visible

### Browser Extension
- [ ] Chrome extension for quick lookups while browsing
- [ ] Right-click context menu on product pages
- [ ] Popup showing commodity code suggestions
- [ ] Link to full Tariffik account for history

### Bulk Import
- [ ] CSV upload of multiple product URLs/descriptions
- [ ] Progress tracking for bulk imports
- [ ] Download results as CSV/Excel
- [ ] Template file downloads

### Email Notifications
- [ ] Notify at 4/5 free lookups used
- [ ] Notify when monthly limit reached
- [ ] Delivery updates for tracked orders
- [ ] Weekly digest of order activity

---

## Medium Priority - Blog & SEO

### Blog Enhancements
- [ ] Pagination when post count exceeds 10-12
- [ ] Tag-based filtering (`/blog/tags/commodity-codes`)
- [ ] Archive pages by year/month
- [ ] RSS/Atom feed for subscribers
- [ ] Related posts suggestions
- [ ] Reading progress indicator
- [ ] Social sharing buttons

### SEO Improvements
- [ ] Structured data for product lookups
- [ ] Dynamic meta descriptions based on content
- [ ] Internal linking strategy
- [ ] Performance optimization (Core Web Vitals)

---

## Medium Priority - API & Technical

### API Improvements
- [ ] Add X-RateLimit-* headers to responses
- [ ] API versioning strategy (plan for v2)
- [ ] Cache tariff API results for common queries
- [ ] Batch prioritization (premium tiers get faster processing)
- [ ] More webhook events (lookup.completed, limit.reached, etc.)

### Caching Strategy
- [ ] Cache scrape results for same URL within timeframe
- [ ] Cache Tavily product info to avoid repeated searches
- [ ] Cache vision results for identical images
- [ ] Redis or Solid Cache for session/fragment caching

### Email Processing
- [ ] Smarter image-product matching using AI
- [ ] More carrier tracking patterns (international)
- [ ] Email threading detection for better order matching
- [ ] Batch email classification (multiple emails per API call)

---

## Lower Priority - Analytics & Admin

### Analytics Dashboard
- [ ] Custom admin dashboard for analytics
- [ ] Cohort analysis queries
- [ ] Funnel visualization
- [ ] Client-side tracking with ahoy.js
- [ ] A/B testing support
- [ ] Data retention job to purge old events

### Admin Features
- [ ] User management dashboard
- [ ] Manual subscription tier changes
- [ ] API usage monitoring
- [ ] Email processing queue monitoring

---

## Lower Priority - Nice to Have

### Misc Features
- [ ] Order search/filtering
- [ ] Purchase additional lookup packs (one-time)
- [ ] Rollover unused lookups for premium tiers
- [ ] Usage analytics dashboard for users
- [ ] Comment system for blog (Disqus/Utterances)
- [ ] Dark mode

### Security Enhancements
- [ ] Script nonces for inline scripts
- [ ] Subresource Integrity (SRI) for external assets
- [ ] Security audit and penetration testing

---

## Technical Debt

- [ ] Smarter URL-to-item matching (text similarity)
- [ ] Improve AI classification accuracy for edge cases
- [ ] Better image preprocessing (brightness/contrast)
- [ ] Rate limiting for web scraping
- [ ] Monitor ScrapingBee credit usage

---

## Completed Features

- [x] Free user lookup limits (5/month)
- [x] Guest lookup limits (3 total)
- [x] Premium tier pricing page
- [x] iOS Safari mobile menu fix
- [x] Photo lookup (beta)
- [x] API layer with tiers
- [x] Webhooks for batch processing
- [x] Ahoy analytics
- [x] Markdown blog with SEO
- [x] Security headers and CSP
- [x] Cloudflare R2 storage

---

*Last updated: 2026-01-18*
