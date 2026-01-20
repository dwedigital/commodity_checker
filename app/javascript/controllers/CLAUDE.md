# Stimulus Controllers - AI Assistant Context

This directory contains Stimulus controllers for client-side interactivity.

## Important: CSP Compliance

**Content Security Policy blocks inline JavaScript.** Never use:
- `onclick="..."` attributes
- `<script>` tags in views
- `javascript:` URLs

Always use Stimulus controllers for interactivity.

## Brand Color Classes

When manipulating classes for visual states, use brand colors:

| State | Color Classes |
|-------|---------------|
| Active/Selected | `border-primary`, `text-primary` |
| Valid/Success | `text-brand-mint` |
| Invalid/Error | `text-gray-400`, `text-primary` |
| Hover | Add `-hover` suffix (e.g., `bg-primary-hover`) |

**Never use:** `indigo-*`, `blue-*`, `green-500` or other non-brand colors.

## Controller Overview

| Controller | Purpose | Brand Colors Used |
|------------|---------|-------------------|
| `tabs_controller.js` | Tab switching | `border-primary`, `text-primary` |
| `clipboard_controller.js` | Copy to clipboard | None (uses opacity) |
| `password_strength_controller.js` | Password validation | `text-brand-mint`, `text-gray-400` |
| `camera_capture_controller.js` | Photo capture for lookups | None |
| `auto_submit_controller.js` | Form auto-submission | None |

## tabs_controller.js

Handles tabbed interfaces with panel visibility toggling.

**Targets:**
- `tab` - Tab buttons
- `panel` - Content panels

**Data attributes:**
- `data-panel="panel-id"` - Links tab button to panel

**Active state classes:**
```javascript
// Remove from all tabs
btn.classList.remove("border-primary", "text-primary")
btn.classList.add("border-transparent", "text-gray-500")

// Add to active tab
activeBtn.classList.remove("border-transparent", "text-gray-500")
activeBtn.classList.add("border-primary", "text-primary")
```

**Usage in views:**
```erb
<div data-controller="tabs">
  <button data-tabs-target="tab"
          data-panel="panel-1"
          data-action="click->tabs#switch"
          class="border-b-2 border-primary text-primary ...">
    Tab 1
  </button>
  <div id="panel-1" data-tabs-target="panel">
    Content
  </div>
</div>
```

## password_strength_controller.js

Real-time password validation feedback.

**Targets:**
- `password` - Password input field
- `confirmation` - Password confirmation field
- `requirement` - Individual requirement indicators
- `match` - Password match indicator

**Color classes used:**
```javascript
// Valid requirement
element.classList.remove("text-gray-400")
element.classList.add("text-brand-mint")

// Invalid requirement
element.classList.remove("text-brand-mint")
element.classList.add("text-gray-400")
```

**Usage in views:**
```erb
<div data-controller="password-strength">
  <%= f.password_field :password, data: { password_strength_target: "password", action: "input->password-strength#validate" } %>

  <div data-password-strength-target="requirement" data-requirement="length" class="text-gray-400">
    8+ characters
  </div>
</div>
```

## clipboard_controller.js

Copy text to clipboard with visual feedback.

**Targets:**
- `source` - Element containing text to copy
- `button` - Copy button (optional, for feedback)

**Usage:**
```erb
<div data-controller="clipboard">
  <code data-clipboard-target="source">text-to-copy</code>
  <button data-action="click->clipboard#copy">Copy</button>
</div>
```

## camera_capture_controller.js

Handles camera access and photo capture for product lookups.

**Targets:**
- `video` - Video element for camera preview
- `canvas` - Canvas for capturing frame
- `preview` - Image element for captured photo preview
- `fileInput` - Hidden file input for form submission
- `submitButton` - Submit button (shown after capture)
- Various section visibility targets

**Key methods:**
- `startCamera()` - Request camera access
- `capturePhoto()` - Capture frame from video
- `retake()` - Return to camera view
- `useFallback()` - Switch to file upload

## Adding New Controllers

1. Create file: `app/javascript/controllers/<name>_controller.js`
2. Import in `controllers/index.js` (usually auto-registered)
3. Follow naming convention: `data-controller="name"` for `name_controller.js`

**Template:**
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["element"]
  static values = { option: String }

  connect() {
    // Called when controller connects to DOM
  }

  disconnect() {
    // Called when controller disconnects from DOM
  }

  action(event) {
    // Handle user interaction
  }
}
```

## Testing Controllers

Stimulus controllers are tested through system tests with Capybara:
```ruby
# test/system/tabs_test.rb
test "switching tabs shows correct panel" do
  visit product_lookups_new_path
  click_on "Photo Lookup"
  assert_selector "#photo-panel", visible: true
  assert_selector "#url-panel", visible: false
end
```
