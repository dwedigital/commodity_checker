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

## Database Changes

None - this is a configuration-only change. Active Storage blobs table already exists.

## New Files Created

None.

## Modified Files

| File | Change |
|------|--------|
| `Gemfile` | Added `aws-sdk-s3` gem |
| `Gemfile.lock` | Updated with aws-sdk dependencies |
| `config/storage.yml` | Added `cloudflare` service configuration for R2 |
| `config/environments/production.rb` | Changed `active_storage.service` from `:local` to `:cloudflare` |

## Routes

No new routes added.

## Data Flow

```
User uploads image (e.g., product lookup)
           │
           ▼
Active Storage receives file
           │
           ▼
(Production) Upload to Cloudflare R2 bucket
           │
           ▼
Blob record stored in active_storage_blobs table
           │
           ▼
Image request → Active Storage generates signed URL → R2 serves file
```

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
4. Verify image displays correctly in the app
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

- **No public URL configuration**: Using signed URLs for all images (default behavior)
- **No CDN in front of R2**: Could add Cloudflare CDN for caching if needed
- **Single bucket**: All environments use the same bucket (differentiate by key prefix if needed)

### Potential Future Improvements

1. **Public bucket with CDN**: Configure R2 public access with Cloudflare CDN for faster image delivery
2. **Separate staging bucket**: Create separate bucket for staging vs production
3. **Image variants**: Configure Active Storage variants for thumbnails
4. **Direct uploads**: Enable direct browser-to-R2 uploads for large files

## Files Summary

### Modified Files (4)
- `Gemfile`
- `Gemfile.lock`
- `config/storage.yml`
- `config/environments/production.rb`
