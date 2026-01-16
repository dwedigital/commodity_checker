# Implementation: Home Page Quick Lookup

## Overview

Added an inline product URL lookup feature to the home page hero section, allowing visitors to instantly get commodity code suggestions without signing up. Includes a limit of 3 free lookups per 72-hour period for unauthenticated users.

## User Flow

1. User visits home page
2. Sees "X free lookups left" indicator (guests only)
3. Pastes product URL into the input field
4. Clicks "Get Commodity Code"
5. Loading spinner appears while fetching
6. Results display inline with:
   - Product image, title, brand
   - Suggested commodity code with confidence
   - AI reasoning
7. CTA prompts user to sign up to save lookups
8. After 3 lookups, form is replaced with sign-up prompt

## Files Created

### `app/javascript/controllers/lookup_limit_controller.js`

Stimulus controller that manages free lookup limits using localStorage.

**Features:**
- Tracks lookup count in localStorage
- 72-hour expiration on the counter
- Shows remaining lookups count
- Hides form and shows sign-up prompt when limit reached
- Skips all limiting for authenticated users

```javascript
// Key localStorage structure
{
  count: 2,
  expiresAt: "2026-01-19T12:00:00.000Z"
}
```

**Stimulus Targets:**
- `form` - The lookup form wrapper (hidden when limit reached)
- `limitReached` - Sign-up prompt (shown when limit reached)
- `remaining` - Span showing remaining lookup count

**Stimulus Values:**
- `limit` - Number of free lookups (default: 3)
- `expiryHours` - Hours until counter resets (default: 72)
- `authenticated` - Boolean, skips limiting when true

### `app/views/pages/_lookup_result.html.erb`

Turbo Frame partial that displays lookup results inline on the home page.

**Key sections:**
- Error state (validation errors)
- Failed state (scraping errors)
- Success state with:
  - Product summary (image, title, brand, retailer)
  - Commodity code result with confidence percentage
  - AI reasoning
  - Sign-up CTA (for non-authenticated users)
  - Link to original product page

## Files Modified

### `app/views/pages/home.html.erb`

Updated hero section with:
- New headline: "Find the right commodity code"
- Product URL input field with link icon
- Submit button with `data-turbo-submits-with` for loading state
- Turbo frame target for inline results
- Updated "How it works" steps to mention product links
- Stimulus controller for lookup limiting
- "X free lookups left" indicator (guests only)
- Limit reached state with sign-up/sign-in CTAs

```erb
<div data-controller="lookup-limit" data-lookup-limit-authenticated-value="<%= user_signed_in? %>">
  <!-- Form wrapper -->
  <div data-lookup-limit-target="form">
    <%= form_with url: home_lookup_path, method: :post,
        data: { turbo_frame: "lookup_result", action: "submit->lookup-limit#submit" } do |f| %>
      <%= f.url_field :url, placeholder: "https://www.amazon.co.uk/dp/B08N5WRWNW" %>
      <p><span data-lookup-limit-target="remaining">3</span> free lookups left</p>
      <%= f.submit "Get Commodity Code", data: { turbo_submits_with: "Looking up..." } %>
    <% end %>
  </div>

  <!-- Limit reached state (hidden by default) -->
  <div class="hidden" data-lookup-limit-target="limitReached">
    <h3>Free lookups used</h3>
    <p>Sign up for unlimited access</p>
    <%= link_to "Sign up free", new_user_registration_path %>
  </div>

  <%= turbo_frame_tag "lookup_result" do %>
  <% end %>
</div>
```

### `app/controllers/pages_controller.rb`

Added `lookup` action:

```ruby
def lookup
  url = params[:url]

  if url.blank?
    @error = "Please enter a product URL"
    return render partial: "pages/lookup_result", formats: [:html]
  end

  # Scrape the product page
  scraper = ProductScraperService.new
  @scrape_result = scraper.scrape(url)

  # Get commodity code suggestion if scraping succeeded
  if @scrape_result[:status] == :completed || @scrape_result[:status] == :partial
    description = [
      @scrape_result[:title],
      @scrape_result[:description],
      @scrape_result[:brand],
      @scrape_result[:category],
      @scrape_result[:material]
    ].compact.reject(&:blank?).join(". ")

    if description.present?
      suggester = LlmCommoditySuggester.new
      @suggestion = suggester.suggest(description)
    end
  end

  render partial: "pages/lookup_result", formats: [:html]
end
```

### `config/routes.rb`

Added route for home page lookup:

```ruby
post "lookup", to: "pages#lookup", as: :home_lookup
```

### `app/assets/stylesheets/application.css`

Added CSS for Turbo frame loading state:

```css
/* Turbo frame loading indicator */
turbo-frame[aria-busy="true"]::before {
  content: "";
  display: block;
  margin: 1.5rem auto;
  width: 2rem;
  height: 2rem;
  border: 3px solid #e5e7eb;
  border-top-color: #4f46e5;
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

turbo-frame[aria-busy="true"]::after {
  content: "Fetching product details...";
  display: block;
  text-align: center;
  font-size: 0.875rem;
  color: #6b7280;
  margin-top: 0.75rem;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

.line-clamp-2 {
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
```

## Technical Details

### Turbo Frames

The feature uses Turbo Frames for seamless inline updates:
- Form targets the `lookup_result` frame via `data: { turbo_frame: "lookup_result" }`
- Response partial wraps content in matching `turbo_frame_tag "lookup_result"`
- Turbo automatically replaces frame content without page reload

### Loading States

Two loading indicators:
1. **Button text**: Changes to "Looking up..." via `data-turbo-submits-with`
2. **Frame spinner**: CSS pseudo-elements on `turbo-frame[aria-busy="true"]`

### Services Used

- **ProductScraperService**: Fetches and parses product page (JSON-LD, OG tags, HTML)
- **LlmCommoditySuggester**: Gets commodity code suggestion from Claude AI

### No Authentication Required

The lookup action doesn't require authentication:
- Uses existing services synchronously
- Results are not persisted to database
- CTA encourages sign-up to save lookups

### Free Lookup Limiting

Client-side limiting using localStorage (not foolproof but sufficient for soft limiting):

**How it works:**
1. On page load, Stimulus controller checks localStorage for existing count
2. If expired (>72 hours from first lookup), counter resets
3. On form submit, checks if limit (3) reached
4. If at limit, prevents submission and shows sign-up prompt
5. Otherwise, increments counter and allows submission

**localStorage key:** `commodity_lookups`

**Data structure:**
```json
{
  "count": 2,
  "expiresAt": "2026-01-19T12:00:00.000Z"
}
```

**Limitations (intentional):**
- Users can clear localStorage to reset
- Different browsers/devices have separate counters
- This is a soft limit to encourage sign-ups, not a hard restriction

## UI Design

### Input Field
- Rounded corners (`rounded-xl`)
- Link icon prefix
- Placeholder with example Amazon URL
- Helper text listing supported retailers

### Results Card
- White background with shadow and ring
- Product image (64x64) with title and brand
- Green success indicator for commodity code
- Monospace font for code display
- Gradient CTA section for sign-up prompt

### Responsive
- Full-width input and button on mobile
- Two-column hero layout on desktop (lg breakpoint)

## Dependencies

Relies on existing services from product-url-lookup-and-scraping implementation:
- `ProductScraperService`
- `LlmCommoditySuggester`

## Testing

### Manual Testing
1. Visit home page (unauthenticated)
2. Verify "3 free lookups left" displays
3. Paste product URL (e.g., Amazon, eBay, ASOS)
4. Verify loading spinner appears
5. Verify product details and commodity code display
6. Verify sign-up CTA appears in results
7. Verify counter decrements to "2 free lookups left"
8. Test with invalid URL to verify error handling
9. Test while logged in to verify no counter or limiting

### Testing Lookup Limits
1. Perform 3 lookups as guest
2. Verify form is replaced with "Free lookups used" message
3. Verify sign-up and sign-in buttons appear
4. Clear localStorage (`localStorage.removeItem('commodity_lookups')`)
5. Refresh page - form should reappear with "3 free lookups left"

### Testing Expiration
1. Perform 1 lookup
2. In browser console, modify expiry:
   ```javascript
   const data = JSON.parse(localStorage.getItem('commodity_lookups'))
   data.expiresAt = new Date(Date.now() - 1000).toISOString()
   localStorage.setItem('commodity_lookups', JSON.stringify(data))
   ```
3. Refresh page - counter should reset to 3

### Edge Cases
- Empty URL submission
- Invalid/malformed URLs
- URLs that fail to scrape
- Products without images
- Products where commodity code can't be determined
- Corrupt localStorage data (should gracefully reset)
- Missing localStorage data (should start fresh)
