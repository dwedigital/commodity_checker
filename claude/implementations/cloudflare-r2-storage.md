# Cloudflare R2 Persistent Image Storage

**Date:** 2026-01-16
**Feature:** Configure Cloudflare R2 as persistent storage backend for Active Storage images

## Overview

This implementation configures Cloudflare R2 as the production storage backend for Active Storage. R2 is S3-compatible, so we use the `aws-sdk-s3` gem with R2's endpoint. This replaces the ephemeral local disk storage that was being wiped on every Render deploy.

## Design Decisions

- **R2 over AWS S3**: Cloudflare R2 has no egress fees, making it cost-effective for image serving
- **S3-compatible API**: Uses standard `aws-sdk-s3` gem - no custom integration needed
- **Environment-based config**: Credentials stored in environment variables, not Rails credentials
- **Local storage in development**: Development continues to use disk storage for simplicity
- **Proxy mode**: Files served through Rails (not direct R2 URLs) since R2 endpoint isn't publicly accessible
- **Checksum compatibility**: Disabled extra checksum headers that R2 doesn't support

## Database Changes

None - this is a configuration-only change. Active Storage blobs table already exists.

## New Files Created

None.

## Modified Files

| File | Change |
|------|--------|
| `Gemfile` | Added `aws-sdk-s3` gem |
| `Gemfile.lock` | Updated with aws-sdk dependencies |
| `config/storage.yml` | Added `cloudflare` service configuration for R2 with checksum settings |
| `config/environments/production.rb` | Changed storage service to `:cloudflare` and enabled proxy mode |

## Routes

No new routes added. Active Storage's built-in proxy routes are used:
- `/rails/active_storage/blobs/proxy/:signed_id/*filename`
- `/rails/active_storage/representations/proxy/:signed_blob_id/:variation_key/*filename`

## Data Flow

```
User uploads image (e.g., product lookup)
           │
           ▼
Active Storage receives file
           │
           ▼
Upload to Cloudflare R2 bucket (via aws-sdk-s3)
           │
           ▼
Blob record stored in active_storage_blobs table
           │
           ▼
Image request → Rails proxy → Fetches from R2 → Serves to browser
```

**Note**: We use proxy mode instead of redirect mode because R2's endpoint isn't publicly accessible. This means images are served through the Rails app rather than directly from R2.

## Configuration

### storage.yml

```yaml
cloudflare:
  service: S3
  access_key_id: <%= ENV["CLOUDFLARE_R2_ACCESS_KEY_ID"] %>
  secret_access_key: <%= ENV["CLOUDFLARE_R2_SECRET_ACCESS_KEY"] %>
  region: auto
  bucket: <%= ENV["CLOUDFLARE_R2_BUCKET"] %>
  endpoint: <%= ENV["CLOUDFLARE_R2_ENDPOINT"] %>
  request_checksum_calculation: when_required
  response_checksum_validation: when_required
```

### production.rb

```ruby
# Store uploaded files in Cloudflare R2
config.active_storage.service = :cloudflare
# Proxy files through Rails instead of redirecting to R2 (R2 endpoint isn't public)
config.active_storage.resolve_model_to_route = :rails_storage_proxy
```

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | R2 API token access key | `abc123...` |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | R2 API token secret | `xyz789...` |
| `CLOUDFLARE_R2_BUCKET` | R2 bucket name | `commodity-checker-images` |
| `CLOUDFLARE_R2_ENDPOINT` | R2 endpoint URL | `https://<account_id>.r2.cloudflarestorage.com` |

## Cloudflare R2 Setup (Manual Steps)

1. **Create R2 bucket** in Cloudflare dashboard:
   - Go to R2 > Create bucket
   - Name: `commodity-checker-images` (or similar)
   - Location: Automatic

2. **Create API token**:
   - Go to R2 > Manage R2 API Tokens
   - Create token with "Object Read & Write" permission for the bucket
   - Save Access Key ID and Secret Access Key

3. **Get endpoint URL**:
   - Format: `https://<account_id>.r2.cloudflarestorage.com`
   - Account ID is in your Cloudflare dashboard URL

4. **Add environment variables to Render**:
   - Go to Render dashboard > your service > Environment
   - Add all 4 environment variables

## Troubleshooting

### Issue: `Aws::S3::Errors::InvalidRequest - You can only specify one non-default checksum at a time`

**Cause**: AWS SDK v3 sends multiple checksum headers (MD5 + SHA256/CRC32) by default, which R2 doesn't support.

**Solution**: Add to storage.yml:
```yaml
request_checksum_calculation: when_required
response_checksum_validation: when_required
```

### Issue: Images upload successfully but URLs don't work (404 or access denied)

**Cause**: R2's S3-compatible endpoint isn't publicly accessible. The default redirect mode sends browsers directly to R2, which fails.

**Solution**: Enable proxy mode in production.rb:
```ruby
config.active_storage.resolve_model_to_route = :rails_storage_proxy
```

This makes Rails fetch images from R2 and serve them, rather than redirecting browsers to R2 directly.

### Issue: `ActionController::Redirecting::UnsafeRedirectError`

**Cause**: When `default_url_options` sets a host (e.g., `localhost:3000`) but the request comes from a different host (e.g., `127.0.0.1:3000`), Rails blocks the redirect.

**Solution**: Use path helpers instead of record-based redirects:
```ruby
# Instead of:
redirect_to @product_lookup

# Use:
redirect_to product_lookup_path(@product_lookup)
```

## Testing/Verification

### Local Testing (optional)

```bash
# Add R2 credentials to .env file
CLOUDFLARE_R2_ACCESS_KEY_ID=your-key
CLOUDFLARE_R2_SECRET_ACCESS_KEY=your-secret
CLOUDFLARE_R2_BUCKET=your-bucket
CLOUDFLARE_R2_ENDPOINT=https://account-id.r2.cloudflarestorage.com

# Temporarily update development.rb to use cloudflare
# config.active_storage.service = :cloudflare

# Upload an image and verify it appears in R2 bucket
```

### Production Testing

1. Deploy to staging first
2. Upload a product image via `/product_lookups/new`
3. Check R2 bucket in Cloudflare dashboard for the uploaded file
4. Verify image displays correctly in the app (URL should contain `/proxy/` not `/redirect/`)
5. Redeploy the app and confirm image still displays (persistence test)

### Verification Commands

```bash
# Verify gem is installed
bundle show aws-sdk-s3

# Check storage configuration
bin/rails runner "puts ActiveStorage::Blob.service.class"

# In production, should output: ActiveStorage::Service::S3Service
```

## Rollback Plan

If issues occur in production:

1. Update `config/environments/production.rb`:
   ```ruby
   config.active_storage.service = :local
   ```
2. Deploy the change
3. Note: Any images uploaded to R2 will still exist but won't be accessible until switching back

## Limitations & Future Improvements

### Current Limitations

- **Proxy mode latency**: Images pass through Rails, adding slight latency vs direct serving
- **No CDN caching**: Could add Cloudflare CDN in front for better performance
- **Single bucket**: All environments use the same bucket (differentiate by key prefix if needed)

### Potential Future Improvements

1. **Public bucket with custom domain**: Configure R2 public access via custom domain, switch to redirect mode with `public: true` for faster delivery
2. **CDN caching**: Add Cloudflare CDN in front of R2 for edge caching
3. **Separate staging bucket**: Create separate bucket for staging vs production
4. **Direct uploads**: Enable direct browser-to-R2 uploads for large files

## Files Summary

### Modified Files (4)
- `Gemfile`
- `Gemfile.lock`
- `config/storage.yml`
- `config/environments/production.rb`
