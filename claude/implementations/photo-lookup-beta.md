# Photo-Based Commodity Code Lookup (Beta)

**Date:** 2026-01-16
**Feature:** Photo-based product identification using Claude's vision API

## Overview

This implementation adds a beta feature for logged-in users to get commodity code suggestions by taking a photo of a physical product using their phone camera or webcam. Claude's vision API analyzes the image to identify the product, which then feeds into the existing commodity code suggestion flow.

## Design Decisions

- **Extended ProductLookup model** - Added `lookup_type` enum (url/photo) and Active Storage attachment rather than creating a new model
- **Vision-first description** - Claude vision API generates product description from image analysis
- **Reuse existing flow** - Vision description feeds into existing LlmCommoditySuggester (no changes needed there)
- **Camera-first UI** - Prioritizes camera capture on mobile with file upload fallback
- **Beta badge** - Marked as beta since image quality significantly affects accuracy
- **Logged-in users only** - Photo lookup requires authentication (no guest mode)

## Database Changes

### Migration: Add photo lookup fields to product_lookups

```ruby
# db/migrate/20260116164746_add_photo_lookup_to_product_lookups.rb
add_column :product_lookups, :lookup_type, :integer, default: 0, null: false  # url: 0, photo: 1
add_column :product_lookups, :image_description, :text  # Vision API result
```

Active Storage attachment added to model (no migration needed - Active Storage already configured).

## New Files Created

### Services

| File | Purpose |
|------|---------|
| `app/services/product_vision_service.rb` | Analyzes product images using Claude's vision API. Returns structured product info: title, description, brand, material, color, category. |

### Jobs

| File | Purpose |
|------|---------|
| `app/jobs/analyze_product_image_job.rb` | Background job that calls ProductVisionService, updates ProductLookup with image_description, then calls LlmCommoditySuggester for commodity code. Broadcasts Turbo Stream update. |

### JavaScript Controllers

| File | Purpose |
|------|---------|
| `app/javascript/controllers/camera_capture_controller.js` | Stimulus controller for camera access (getUserMedia), photo capture to canvas, camera switching (front/back), file upload fallback, and preview display. |

### Views

| File | Purpose |
|------|---------|
| `app/views/product_lookups/_photo_form.html.erb` | Camera capture UI with video preview, capture/retake buttons, camera switch, file upload fallback, and submit. |

## Modified Files

### Models

| File | Change |
|------|--------|
| `app/models/product_lookup.rb` | Added `enum :lookup_type`, `has_one_attached :product_image`, conditional validations, updated `display_description` to return `image_description` for photo lookups |

### Controllers

| File | Change |
|------|--------|
| `app/controllers/product_lookups_controller.rb` | Added `create_from_photo` action for handling photo uploads and queuing AnalyzeProductImageJob |

### Views

| File | Change |
|------|--------|
| `app/views/product_lookups/new.html.erb` | Added tabs for "URL Lookup" and "Photo Lookup (Beta)", photo tab shows for signed-in users only |
| `app/views/product_lookups/_product_lookup.html.erb` | Shows uploaded image for photo lookups, "Photo Lookup (Beta)" badge, different loading text, conditionally hides URL link |

### Routes

| File | Change |
|------|--------|
| `config/routes.rb` | Added `post :create_from_photo` collection route to product_lookups |

### Gemfile

| File | Change |
|------|--------|
| `Gemfile` | Uncommented `gem "image_processing", "~> 1.2"` for Active Storage variants |

## Routes

```
POST   /product_lookups/create_from_photo    product_lookups#create_from_photo
```

## Data Flow

```
User captures/uploads photo
         │
         ▼
ProductLookupsController#create_from_photo
         │
         ├─── Create ProductLookup (lookup_type: photo, status: pending)
         ├─── Attach image via Active Storage
         │
         └─── AnalyzeProductImageJob.perform_later
                      │
                      ▼
            ProductVisionService.analyze(image_blob)
                      │
                      ├─── Download image blob
                      ├─── Encode as base64
                      ├─── Send to Claude vision API
                      └─── Parse JSON response: {title, description, brand, material, color, category}
                      │
                      ▼
            Build image_description from analysis
                      │
                      ▼
            Update ProductLookup (title, description, brand, material, category, image_description)
                      │
                      ▼
            LlmCommoditySuggester.suggest(image_description)
                      │
                      ▼
            Update ProductLookup with commodity code + confidence + reasoning
                      │
                      ▼
            Broadcast Turbo Stream update
```

## UI/UX Flow

### Desktop (Webcam)
1. User clicks "Photo Lookup (Beta)" tab
2. Browser requests camera permission
3. Video preview shows webcam feed
4. User clicks "Capture" → image freezes
5. User can "Retake" or click "Analyze Product"
6. On submit → redirects to show page with loading state

### Mobile (Phone Camera)
1. User taps "Photo Lookup (Beta)" tab
2. Camera opens (defaults to rear camera)
3. User can switch front/rear camera
4. Tap to capture → preview shown
5. "Retake" or "Analyze Product"
6. Submit → show page with loading

### Fallback (No Camera Access)
1. Error message shown if camera permission denied
2. File upload dropzone displayed
3. User selects image from gallery
4. Preview shown, submit available

## Camera Capture Controller Features

The Stimulus controller (`camera_capture_controller.js`) provides:

- **Camera access** via `navigator.mediaDevices.getUserMedia()`
- **Front/back camera switching** on mobile devices
- **Frame capture** to hidden canvas
- **Blob conversion** with JPEG encoding at 90% quality
- **DataTransfer API** to programmatically set file input
- **Graceful fallback** to file upload when camera unavailable
- **Error handling** for permission denied, no camera found, camera in use, etc.

## Testing

### Manual Testing Steps

1. Start the server: `bin/dev`
2. Sign in as a user
3. Go to "Lookup" in the navigation
4. Click "Photo Lookup (Beta)" tab
5. Test camera capture:
   - Allow camera permission
   - Capture a product photo
   - Click "Analyze Product"
   - Wait for results
6. Test file upload fallback:
   - Click upload area
   - Select an image file
   - Click "Analyze Product"
7. Verify the show page displays:
   - Uploaded image thumbnail
   - "Photo Lookup (Beta)" badge
   - Product details from vision analysis
   - Commodity code suggestion

### Verification Commands

```bash
# Check routes
bin/rails routes | grep product

# Check migration status
bin/rails db:migrate:status

# Test vision service manually (requires an existing photo lookup)
bin/rails runner "
  lookup = ProductLookup.where(lookup_type: :photo).last
  if lookup&.product_image&.attached?
    service = ProductVisionService.new
    result = service.analyze(lookup.product_image)
    puts result.inspect
  else
    puts 'No photo lookup found'
  end
"

# Check Active Storage attachment
bin/rails runner "
  lookup = ProductLookup.where(lookup_type: :photo).last
  if lookup
    puts 'Attached: ' + lookup.product_image.attached?.to_s
    puts 'URL: ' + (lookup.product_image.attached? ? lookup.product_image.url : 'N/A')
  end
"
```

## Limitations & Future Improvements

### Current Limitations

- **Image quality dependent** - Poor lighting, blur, or partial views significantly affect accuracy
- **No image preprocessing** - No automatic brightness/contrast adjustment or cropping
- **Single image only** - Cannot upload multiple angles of the same product
- **Logged-in users only** - No guest photo lookup (unlike URL lookup)
- **No offline support** - Requires internet for both upload and Claude API

### Potential Future Improvements

1. **Image cropping/adjustment** - Let users crop and adjust before submission
2. **Multi-image support** - Upload 2-3 angles for better identification
3. **Quality indicator** - Show image quality score before submission
4. **Cached results** - Cache vision results for identical images
5. **Example photos** - Show "good" vs "bad" product photo examples
6. **Guest photo lookup** - Allow limited free photo lookups for guests
7. **Barcode/QR scanning** - Detect and use product barcodes when visible

## Files Summary

### New Files (4)
- `app/services/product_vision_service.rb`
- `app/jobs/analyze_product_image_job.rb`
- `app/javascript/controllers/camera_capture_controller.js`
- `app/views/product_lookups/_photo_form.html.erb`
- `db/migrate/20260116164746_add_photo_lookup_to_product_lookups.rb`

### Modified Files (6)
- `app/models/product_lookup.rb`
- `app/controllers/product_lookups_controller.rb`
- `app/views/product_lookups/new.html.erb`
- `app/views/product_lookups/_product_lookup.html.erb`
- `config/routes.rb`
- `Gemfile`
