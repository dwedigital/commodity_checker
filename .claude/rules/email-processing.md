---
paths:
  - "app/services/email_*"
  - "app/services/product_info_finder*"
  - "app/mailboxes/**"
  - "app/jobs/process_inbound_email*"
---

# Email Processing

## Email Processing Flow

```
Email → Resend → Action Mailbox → TrackingMailbox → ProcessInboundEmailJob
                                                            ↓
                                              EmailClassifierService (AI classification)
                                                            ↓
                                              EmailParserService (tracking URLs, images)
                                                            ↓
                                    ┌───────────────────────┴───────────────────────┐
                                    ▼                                               ▼
                          Order Confirmation                              Shipping/Delivery
                                    ↓                                               ↓
                      OrderMatcherService                               OrderMatcherService
                      (find or create order)                            (find matching order)
                                    ↓                                               ↓
                      ProductInfoFinderService                          Add tracking URLs
                      (Tavily search if no URLs)                        Link email to order
                                    ↓
                      SuggestCommodityCodesJob
```

## AI Email Classification

**Email Types:**
- `order_confirmation` - Purchase confirmed, contains products
- `shipping_notification` - Package shipped, may have tracking
- `delivery_confirmation` - Package delivered
- `return_confirmation` - Return/refund processed
- `marketing` - Promotional emails (ignored)
- `other` - Doesn't fit categories (ignored)

**Processing Logic:**
- Order confirmations with products → Create order, extract product images, suggest codes
- Shipping notifications → Match to existing order by reference, add tracking
- Delivery confirmations → Update order status

**Image Extraction:**
- Product images are extracted from email HTML
- Filters out logos, icons, tracking pixels, social buttons
- Falls back to Tavily web search if no images in email

## Common Tasks

### Adding a new carrier for tracking
1. Add URL pattern to `EmailParserService::TRACKING_PATTERNS`
2. Add handler to `TrackingScraperService::CARRIER_HANDLERS`
3. Implement `scrape_<carrier>` method

### Improving email parsing
- Edit `EmailParserService#extract_product_descriptions`
- Use multiple strategies, avoid overfitting to one email format
- Test with `/dashboard/test_emails/new` interface

### Modifying commodity code suggestions
- Edit `LlmCommoditySuggester::SYSTEM_PROMPT` for different AI behavior
- The service combines tariff API results with Claude's interpretation
