# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_23_205132) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message_checksum", null: false
    t.string "message_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ahoy_events", force: :cascade do |t|
    t.string "name"
    t.jsonb "properties", default: {}
    t.datetime "time"
    t.integer "user_id"
    t.integer "visit_id"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["properties"], name: "index_ahoy_events_on_properties_gin", using: :gin
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "app_version"
    t.string "browser"
    t.string "city"
    t.string "country"
    t.string "device_type"
    t.string "ip"
    t.text "landing_page"
    t.float "latitude"
    t.float "longitude"
    t.string "os"
    t.string "os_version"
    t.string "platform"
    t.text "referrer"
    t.string "referring_domain"
    t.string "region"
    t.datetime "started_at"
    t.text "user_agent"
    t.integer "user_id"
    t.string "utm_campaign"
    t.string "utm_content"
    t.string "utm_medium"
    t.string "utm_source"
    t.string "utm_term"
    t.string "visit_token"
    t.string "visitor_token"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token", "started_at"], name: "index_ahoy_visits_on_visitor_token_and_started_at"
  end

  create_table "api_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "key_digest", null: false
    t.string "key_prefix", null: false
    t.datetime "last_request_at"
    t.string "name"
    t.date "requests_reset_date"
    t.integer "requests_this_month", default: 0, null: false
    t.integer "requests_today", default: 0, null: false
    t.datetime "revoked_at"
    t.integer "tier", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["key_digest"], name: "index_api_keys_on_key_digest", unique: true
    t.index ["key_prefix"], name: "index_api_keys_on_key_prefix"
    t.index ["user_id", "revoked_at"], name: "index_api_keys_on_user_id_and_revoked_at"
  end

  create_table "api_requests", force: :cascade do |t|
    t.integer "api_key_id", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", null: false
    t.string "ip_address"
    t.string "method"
    t.integer "response_time_ms"
    t.integer "status_code"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["api_key_id", "created_at"], name: "index_api_requests_on_api_key_id_and_created_at"
    t.index ["created_at"], name: "index_api_requests_on_created_at"
  end

  create_table "batch_job_items", force: :cascade do |t|
    t.integer "batch_job_id", null: false
    t.string "category"
    t.string "commodity_code"
    t.decimal "confidence", precision: 4, scale: 2
    t.datetime "created_at", null: false
    t.text "description"
    t.text "error_message"
    t.string "external_id"
    t.integer "input_type", default: 0, null: false
    t.datetime "processed_at"
    t.string "reasoning"
    t.text "scraped_product"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.boolean "validated"
    t.index ["batch_job_id", "status"], name: "index_batch_job_items_on_batch_job_id_and_status"
  end

  create_table "batch_jobs", force: :cascade do |t|
    t.integer "api_key_id", null: false
    t.datetime "completed_at"
    t.integer "completed_items", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "failed_items", default: 0, null: false
    t.string "public_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "total_items", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "webhook_url"
    t.index ["api_key_id", "status"], name: "index_batch_jobs_on_api_key_id_and_status"
    t.index ["public_id"], name: "index_batch_jobs_on_public_id", unique: true
  end

  create_table "extension_auth_codes", force: :cascade do |t|
    t.string "code_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "extension_id", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.integer "user_id", null: false
    t.index ["code_digest"], name: "index_extension_auth_codes_on_code_digest", unique: true
    t.index ["expires_at"], name: "index_extension_auth_codes_on_expires_at"
    t.index ["user_id"], name: "index_extension_auth_codes_on_user_id"
  end

  create_table "extension_lookups", force: :cascade do |t|
    t.string "commodity_code"
    t.datetime "created_at", null: false
    t.string "extension_id", null: false
    t.string "ip_address"
    t.string "lookup_type", default: "url"
    t.datetime "updated_at", null: false
    t.text "url"
    t.index ["extension_id", "created_at"], name: "index_extension_lookups_on_extension_id_and_created_at"
  end

  create_table "extension_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "extension_id"
    t.datetime "last_used_at"
    t.string "name"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["token_digest"], name: "index_extension_tokens_on_token_digest", unique: true
    t.index ["token_prefix"], name: "index_extension_tokens_on_token_prefix"
    t.index ["user_id", "revoked_at"], name: "index_extension_tokens_on_user_id_and_revoked_at"
  end

  create_table "guest_lookups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "guest_token", null: false
    t.string "ip_address"
    t.string "lookup_type", null: false
    t.datetime "updated_at", null: false
    t.text "url"
    t.string "user_agent"
    t.index ["created_at"], name: "index_guest_lookups_on_created_at"
    t.index ["guest_token", "created_at"], name: "index_guest_lookups_on_guest_token_and_created_at"
  end

  create_table "inbound_emails", force: :cascade do |t|
    t.text "body_html"
    t.text "body_text"
    t.datetime "created_at", null: false
    t.string "from_address"
    t.integer "order_id"
    t.datetime "processed_at"
    t.integer "processing_status"
    t.string "subject"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["order_id"], name: "index_inbound_emails_on_order_id"
    t.index ["user_id"], name: "index_inbound_emails_on_user_id"
  end

  create_table "order_items", force: :cascade do |t|
    t.decimal "commodity_code_confidence"
    t.string "confirmed_commodity_code"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "image_url"
    t.text "llm_reasoning"
    t.integer "order_id", null: false
    t.integer "product_lookup_id"
    t.string "product_url"
    t.integer "quantity"
    t.text "scraped_description"
    t.string "suggested_commodity_code"
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_lookup_id"], name: "index_order_items_on_product_lookup_id"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "estimated_delivery"
    t.string "order_reference"
    t.string "retailer_name"
    t.integer "source_email_id"
    t.integer "status"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "product_lookups", force: :cascade do |t|
    t.string "brand"
    t.string "category"
    t.decimal "commodity_code_confidence", precision: 5, scale: 4
    t.string "confirmed_commodity_code"
    t.datetime "created_at", null: false
    t.string "currency"
    t.text "description"
    t.text "image_description"
    t.string "image_url"
    t.text "llm_reasoning"
    t.integer "lookup_type", default: 0, null: false
    t.string "material"
    t.integer "order_item_id"
    t.string "price"
    t.string "retailer_name"
    t.text "scrape_error"
    t.integer "scrape_status", default: 0
    t.datetime "scraped_at"
    t.json "structured_data"
    t.string "suggested_commodity_code"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url"
    t.integer "user_id", null: false
    t.index ["order_item_id"], name: "index_product_lookups_on_order_item_id"
    t.index ["url"], name: "index_product_lookups_on_url"
    t.index ["user_id", "created_at"], name: "index_product_lookups_on_user_id_and_created_at"
  end

  create_table "tracking_events", force: :cascade do |t|
    t.string "carrier"
    t.datetime "created_at", null: false
    t.datetime "event_timestamp"
    t.string "location"
    t.integer "order_id", null: false
    t.json "raw_data"
    t.string "status"
    t.string "tracking_url"
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_tracking_events_on_order_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "inbound_email_token"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "subscription_expires_at"
    t.integer "subscription_tier", default: 0, null: false
    t.string "unconfirmed_email"
    t.datetime "updated_at", null: false
    t.index ["admin"], name: "index_users_on_admin"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["inbound_email_token"], name: "index_users_on_inbound_email_token", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "webhooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.text "events"
    t.integer "failure_count", default: 0, null: false
    t.datetime "last_failure_at"
    t.datetime "last_success_at"
    t.string "secret", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "enabled"], name: "index_webhooks_on_user_id_and_enabled"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_keys", "users"
  add_foreign_key "api_requests", "api_keys"
  add_foreign_key "batch_job_items", "batch_jobs"
  add_foreign_key "batch_jobs", "api_keys"
  add_foreign_key "extension_auth_codes", "users"
  add_foreign_key "extension_tokens", "users"
  add_foreign_key "inbound_emails", "orders"
  add_foreign_key "inbound_emails", "users"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "product_lookups"
  add_foreign_key "orders", "users"
  add_foreign_key "product_lookups", "order_items"
  add_foreign_key "product_lookups", "users"
  add_foreign_key "tracking_events", "orders"
  add_foreign_key "webhooks", "users"
end
