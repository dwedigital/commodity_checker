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

ActiveRecord::Schema[8.0].define(version: 2026_01_18_200003) do
  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "message_id", null: false
    t.string "message_checksum", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ahoy_events", force: :cascade do |t|
    t.integer "visit_id"
    t.integer "user_id"
    t.string "name"
    t.text "properties"
    t.datetime "time"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "visit_token"
    t.string "visitor_token"
    t.integer "user_id"
    t.string "ip"
    t.text "user_agent"
    t.text "referrer"
    t.string "referring_domain"
    t.text "landing_page"
    t.string "browser"
    t.string "os"
    t.string "device_type"
    t.string "country"
    t.string "region"
    t.string "city"
    t.float "latitude"
    t.float "longitude"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_term"
    t.string "utm_content"
    t.string "utm_campaign"
    t.string "app_version"
    t.string "os_version"
    t.string "platform"
    t.datetime "started_at"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token", "started_at"], name: "index_ahoy_visits_on_visitor_token_and_started_at"
  end

  create_table "api_keys", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "key_digest", null: false
    t.string "key_prefix", null: false
    t.string "name"
    t.integer "tier", default: 0, null: false
    t.integer "requests_today", default: 0, null: false
    t.integer "requests_this_month", default: 0, null: false
    t.date "requests_reset_date"
    t.datetime "last_request_at"
    t.datetime "expires_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key_digest"], name: "index_api_keys_on_key_digest", unique: true
    t.index ["key_prefix"], name: "index_api_keys_on_key_prefix"
    t.index ["user_id", "revoked_at"], name: "index_api_keys_on_user_id_and_revoked_at"
    t.index ["user_id"], name: "index_api_keys_on_user_id"
  end

  create_table "api_requests", force: :cascade do |t|
    t.integer "api_key_id", null: false
    t.string "endpoint", null: false
    t.string "method"
    t.integer "status_code"
    t.integer "response_time_ms"
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key_id", "created_at"], name: "index_api_requests_on_api_key_id_and_created_at"
    t.index ["api_key_id"], name: "index_api_requests_on_api_key_id"
    t.index ["created_at"], name: "index_api_requests_on_created_at"
  end

  create_table "batch_job_items", force: :cascade do |t|
    t.integer "batch_job_id", null: false
    t.string "external_id"
    t.integer "input_type", default: 0, null: false
    t.text "description"
    t.string "url"
    t.integer "status", default: 0, null: false
    t.string "commodity_code"
    t.decimal "confidence", precision: 4, scale: 2
    t.string "reasoning"
    t.string "category"
    t.boolean "validated"
    t.text "error_message"
    t.text "scraped_product"
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_job_id", "status"], name: "index_batch_job_items_on_batch_job_id_and_status"
    t.index ["batch_job_id"], name: "index_batch_job_items_on_batch_job_id"
  end

  create_table "batch_jobs", force: :cascade do |t|
    t.integer "api_key_id", null: false
    t.string "public_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "total_items", default: 0, null: false
    t.integer "completed_items", default: 0, null: false
    t.integer "failed_items", default: 0, null: false
    t.string "webhook_url"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key_id", "status"], name: "index_batch_jobs_on_api_key_id_and_status"
    t.index ["api_key_id"], name: "index_batch_jobs_on_api_key_id"
    t.index ["public_id"], name: "index_batch_jobs_on_public_id", unique: true
  end

  create_table "extension_auth_codes", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "code_digest", null: false
    t.string "extension_id", null: false
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code_digest"], name: "index_extension_auth_codes_on_code_digest", unique: true
    t.index ["expires_at"], name: "index_extension_auth_codes_on_expires_at"
    t.index ["user_id"], name: "index_extension_auth_codes_on_user_id"
  end

  create_table "extension_lookups", force: :cascade do |t|
    t.string "extension_id", null: false
    t.string "lookup_type", default: "url"
    t.text "url"
    t.string "commodity_code"
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["extension_id", "created_at"], name: "index_extension_lookups_on_extension_id_and_created_at"
    t.index ["extension_id"], name: "index_extension_lookups_on_extension_id"
  end

  create_table "extension_tokens", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.string "extension_id"
    t.string "name"
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_extension_tokens_on_token_digest", unique: true
    t.index ["token_prefix"], name: "index_extension_tokens_on_token_prefix"
    t.index ["user_id", "revoked_at"], name: "index_extension_tokens_on_user_id_and_revoked_at"
    t.index ["user_id"], name: "index_extension_tokens_on_user_id"
  end

  create_table "guest_lookups", force: :cascade do |t|
    t.string "guest_token", null: false
    t.string "lookup_type", null: false
    t.text "url"
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_guest_lookups_on_created_at"
    t.index ["guest_token", "created_at"], name: "index_guest_lookups_on_guest_token_and_created_at"
    t.index ["guest_token"], name: "index_guest_lookups_on_guest_token"
  end

  create_table "inbound_emails", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "subject"
    t.string "from_address"
    t.text "body_text"
    t.datetime "processed_at"
    t.integer "processing_status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "body_html"
    t.integer "order_id"
    t.index ["order_id"], name: "index_inbound_emails_on_order_id"
    t.index ["user_id"], name: "index_inbound_emails_on_user_id"
  end

  create_table "order_items", force: :cascade do |t|
    t.integer "order_id", null: false
    t.text "description"
    t.integer "quantity"
    t.string "suggested_commodity_code"
    t.string "confirmed_commodity_code"
    t.decimal "commodity_code_confidence"
    t.text "llm_reasoning"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "product_url"
    t.text "scraped_description"
    t.integer "product_lookup_id"
    t.string "image_url"
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_lookup_id"], name: "index_order_items_on_product_lookup_id"
  end

  create_table "orders", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "source_email_id"
    t.string "order_reference"
    t.string "retailer_name"
    t.integer "status"
    t.date "estimated_delivery"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "product_lookups", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "order_item_id"
    t.string "url"
    t.string "retailer_name"
    t.string "title"
    t.text "description"
    t.string "brand"
    t.string "category"
    t.string "price"
    t.string "currency"
    t.string "material"
    t.string "image_url"
    t.json "structured_data"
    t.integer "scrape_status", default: 0
    t.text "scrape_error"
    t.datetime "scraped_at"
    t.string "suggested_commodity_code"
    t.decimal "commodity_code_confidence", precision: 5, scale: 4
    t.text "llm_reasoning"
    t.string "confirmed_commodity_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "lookup_type", default: 0, null: false
    t.text "image_description"
    t.index ["order_item_id"], name: "index_product_lookups_on_order_item_id"
    t.index ["url"], name: "index_product_lookups_on_url"
    t.index ["user_id", "created_at"], name: "index_product_lookups_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_product_lookups_on_user_id"
  end

  create_table "tracking_events", force: :cascade do |t|
    t.integer "order_id", null: false
    t.string "carrier"
    t.string "tracking_url"
    t.string "status"
    t.string "location"
    t.datetime "event_timestamp"
    t.json "raw_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_tracking_events_on_order_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "inbound_email_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "subscription_tier", default: 0, null: false
    t.datetime "subscription_expires_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["inbound_email_token"], name: "index_users_on_inbound_email_token", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "webhooks", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "url", null: false
    t.string "secret", null: false
    t.text "events"
    t.boolean "enabled", default: true, null: false
    t.integer "failure_count", default: 0, null: false
    t.datetime "last_success_at"
    t.datetime "last_failure_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "enabled"], name: "index_webhooks_on_user_id_and_enabled"
    t.index ["user_id"], name: "index_webhooks_on_user_id"
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
