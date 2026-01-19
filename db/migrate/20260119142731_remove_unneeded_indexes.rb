class RemoveUnneededIndexes < ActiveRecord::Migration[8.0]
  def change
    remove_index :api_keys, name: "index_api_keys_on_user_id", column: :user_id
    remove_index :api_requests, name: "index_api_requests_on_api_key_id", column: :api_key_id
    remove_index :batch_job_items, name: "index_batch_job_items_on_batch_job_id", column: :batch_job_id
    remove_index :batch_jobs, name: "index_batch_jobs_on_api_key_id", column: :api_key_id
    remove_index :extension_lookups, name: "index_extension_lookups_on_extension_id", column: :extension_id
    remove_index :extension_tokens, name: "index_extension_tokens_on_user_id", column: :user_id
    remove_index :guest_lookups, name: "index_guest_lookups_on_guest_token", column: :guest_token
    remove_index :product_lookups, name: "index_product_lookups_on_user_id", column: :user_id
    remove_index :webhooks, name: "index_webhooks_on_user_id", column: :user_id
  end
end
