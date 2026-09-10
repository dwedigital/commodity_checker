# Implementation: Home Page Quick Lookup

## September 2026 design refresh (current)

The public homepage now uses a warm paper background, dark ink typography, a restrained red accent, shipping-label details, and an inline SVG parcel illustration. This section supersedes the historical landing-page descriptions below. Guest allowance is **3 lifetime lookups**; free accounts receive **5 per month**, as defined by the existing backend.

### Design and implementation

The hero keeps the real Rails lookup form beside a clearly labelled illustrative result. Subsequent sections cover the workflow, order tools, photo lookup, browser extension, pricing, native FAQ disclosures, and a final lookup action. Existing testimonials were removed from the redesigned page. The parcel and example product illustration are inline SVG, with no new external asset or runtime dependency.

The global navigation and footer share a lowercase wordmark and arrow symbol. Public desktop and mobile menus link to features, pricing and the workflow. Authentication screens inherit the paper background and focus styling; authenticated dashboard navigation and existing forms remain available.

### Files

| File | Change |
|---|---|
| `app/assets/stylesheets/tariffik.css` | New scoped design tokens, responsive layout, focus and reduced-motion styles |
| `app/views/pages/home.html.erb` | Rebuilt homepage with existing Rails form and Stimulus targets |
| `app/views/layouts/application.html.erb` | Wordmark, public links, language, skip link, auth styling class |
| `app/views/shared/_footer.html.erb` | Shared footer design |
| `app/views/pages/_lookup_result.html.erb` | Bordered result card |
| `test/controllers/pages_controller_test.rb` | Guest, exhausted allowance, authenticated, validation, and mocked success coverage |

### Database, routes and data flow

No schema or route changes. Browser URL form → existing `PagesController#lookup` → scraper + classifier → existing `lookup_result` Turbo frame. The existing lookup-limit and lookup-progress Stimulus controllers are retained. The illustrative sample is static, explicitly labelled, and never presented as a live response.

### Verification

- Tailwind build and whitespace checks.
- Homepage + product lookup controller tests against temporary PostgreSQL: 14 tests, 53 assertions, no failures/errors.
- Browser review at desktop and 390px mobile width: hero, pricing, FAQ expansion, empty URL validation, mobile menu, and sign-in screen.
- Local preview: `USE_SQLITE=true bin/rails server -b 127.0.0.1 -p 3101` using installed Ruby 3.3.5. Existing SQLite development data renders successfully; the test schema requires PostgreSQL because it contains `jsonb`.

### Coherence pass (10 Sep 2026)

| File | Change |
|---|---|
| `app/views/layouts/application.html.erb` | Removed `bg-white` from `<html>` so the paper background covers the whole canvas (it used to stop after the first viewport, leaving later sections white); `theme-color` → `#f8f7f2` |
| `app/views/pwa/manifest.json.erb` | Theme/background colours → paper |
| `app/assets/stylesheets/tariffik_workspace.css` | Legacy Tailwind token remap moved from `.tf-workspace, .tf-auth-page` to `.tariffik-site`, so blog, legal, extension auth and flashes also use the refresh palette |
| `app/views/pages/_lookup_result.html.erb` + `.tf-result*` in `tariffik.css` | Live result restyled as the working version of the hero's sample label: `6109 10 0010` split code, raw 10-digit code kept for copying, confidence bar, ink sign-up strip |
| `app/helpers/application_helper.rb` | `commodity_code_display` splits a code into heading / subheading / national digits |
| `app/views/product_lookups/_limit_reached.html.erb` | Amber gradient card → `tf-limit` panel |
| `app/controllers/pages_controller.rb` | Guest limit copy now matches pricing (free account = 5 lookups/month, not "unlimited") |
| `app/assets/stylesheets/application.css` | Turbo loading spinner indigo → Tariffik red |

### Workspace completion (10 Sep 2026)

| File | Change |
|---|---|
| `product_lookups/new` + `_photo_form` + `_allowance` (new) + `tabs_controller.js` | Rebuilt on `tf-*`: aria-driven tabs, homepage-style input row ("Find my code"), allowance bar, notes. Free users at their limit now see the limit panel instead of a form whose submit silently did nothing (the `lookup_form` Turbo target never existed) |
| `product_lookups/show` + `_product_lookup` + `_status_badge` | Detail grid: code panel (split code, raw code, confidence, reasoning, confirm), product details, add-to-order picker. Partials carry their own ids so repeated Turbo broadcasts keep working |
| `orders/show`, `orders/new` | Same detail grid and breadcrumbs; order form uses settings-form fieldsets with sentence-case labels |
| `product_lookups/index`, `orders/index`, `dashboard/index` | Split codes everywhere, sentence-case badge helpers, `tf-empty-state` (orders empty state shows the forwarding address) |
| `shared/_page_header` | Optional `breadcrumbs:`; sets the page `<title>` on detail pages too |
| `application_helper.rb` | `order_status_badge`, `lookup_status_badge`, `lookup_type_label` (+ `test/helpers/application_helper_test.rb`) |
| `tariffik_workspace.css` | Workspace content now 1280px (aligns with the nav wordmark); tabs, detail grid, panels, notes, allowance bar, item list, processing state |
| `layouts/application` | Flash messages sit on the same `tf-wrap` grid |

### Blog, legal and extension consent (10 Sep 2026)

| File | Change |
|---|---|
| `blog/index`, `blog/_post_card`, `blog/show` | Full-width on `tf-wrap`; ruled post list (date / title + summary + tags / read); article column with mono meta line, `tf-prose` body and a "Find my code" note. Inline `<style>` removed |
| `pages/privacy`, `pages/terms` | `page_header` + sticky "On this page" contents (`tf-legal`), `tf-prose` body, sentence-case headings with anchor ids, callouts as `tf-note` / `tf-result-notice.is-warning`, contact as a `tf-panel`. Inline `<style>` removed; wording unchanged |
| `extension_auth/authorize`, `extension_auth/callback` | Consent screen on the dotted auth ground (`auth_page?` helper): permissions list, signed-in account row, "Connect extension" / "Cancel", manual code in the copy component |
| `tariffik.css` | `tf-page`, `tf-post-list`, `tf-article*`, `tf-prose` (tables, code, Rouge colours), `tf-legal*`, `tf-consent*` |
| `shared/_page_header` | Optional `page_title:` override |
| `test/controllers/public_pages_test.rb` | Blog index/show render, legal contents links match section ids, consent form posts extension details, callback renders |

### Limits

External scraper/AI calls are mocked in the integration test; no paid live lookup was used for design verification. The homepage, shared shell, authentication styling and the signed-in workspace (dashboard, lookups, orders, settings) are on the refresh. Blog, privacy, terms and the extension consent flow were migrated on 10 Sep 2026 (see below). The API upsell page, the sign-in screens' pill badges, admin analytics, the dev-only test-email page and the browser extension UI still use legacy markup (legacy colours are remapped, shapes are not). Production deployment is separate from preview review.


## Overview

Added an inline product URL lookup feature to the home page hero section, allowing visitors to instantly get commodity code suggestions without signing up. Includes a limit of 3 free lookups per 72-hour period for unauthenticated users.

## Landing Page Redesign (v2)

The home page was redesigned with more impactful content including:

### Page Sections

1. **Hero Section**
   - Attention-grabbing headline: "Stop guessing commodity codes"
   - Badge highlighting "3 free lookups - no account needed"
   - Centered lookup form with inline button
   - Trust indicators (UK Trade Tariff API, Claude AI, 10-digit codes)

2. **Problem Section**
   - Explains pain points: wrong duty rates, hours of research, shipment delays
   - Visual hierarchy with red warning icons
   - Image placeholder for Gemini-generated illustration

3. **How It Works**
   - 3-step process cards
   - Numbered badges with clear descriptions
   - Clean white card design

4. **Free vs Account Comparison**
   - Side-by-side pricing-style cards
   - Free tier: 3 lookups / 72 hours with limitations listed
   - Account tier: Unlimited lookups with full feature list
   - "Recommended" badge on account tier

5. **Features Grid**
   - 6 feature cards for account holders
   - Email forwarding, Order dashboard, AI explanations
   - Delivery tracking, CSV export, Official data validation

6. **Final CTA**
   - Indigo background section
   - "Try it free now" (scrolls to top) and "Create free account" buttons

### Image Placeholders

Gemini prompts included in HTML comments for generating:
- Hero background abstract pattern
- Problem section illustration (confused person with paperwork)
- Solution illustration (happy person with checkmarks)
- How it works step icons
- Feature icons (if custom needed)

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
