# frozen_string_literal: true

# OAuth 2.1 authorization server backing the MCP endpoint.
#
# Three departures from Doorkeeper's generated migration, all required by the
# MCP authorization spec:
#
#   * `secret` is nullable. MCP clients register dynamically as public clients
#     and authenticate with PKCE rather than a secret.
#   * `code_challenge` / `code_challenge_method` on grants, for PKCE.
#   * `resource` on grants and tokens, for RFC 8707 audience binding. Doorkeeper
#     carries it from the authorize request through to the token (and through
#     refresh) via `custom_access_token_attributes`, and the MCP endpoint
#     refuses any token whose resource is not itself.
class CreateDoorkeeperTables < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_applications do |t|
      t.string  :name,    null: false
      t.string  :uid,     null: false
      t.string  :secret
      t.text    :redirect_uri, null: false
      t.string  :scopes,       null: false, default: ""
      t.boolean :confidential, null: false, default: true
      t.timestamps             null: false
    end

    add_index :oauth_applications, :uid, unique: true

    create_table :oauth_access_grants do |t|
      t.references :resource_owner,  null: false
      t.references :application,     null: false
      t.string   :token,             null: false
      t.integer  :expires_in,        null: false
      t.text     :redirect_uri,      null: false
      t.string   :scopes,            null: false, default: ""
      t.datetime :created_at,        null: false
      t.datetime :revoked_at

      t.string   :code_challenge
      t.string   :code_challenge_method
      t.string   :resource
    end

    add_index :oauth_access_grants, :token, unique: true
    add_foreign_key :oauth_access_grants, :oauth_applications, column: :application_id
    add_foreign_key :oauth_access_grants, :users, column: :resource_owner_id

    create_table :oauth_access_tokens do |t|
      t.references :resource_owner, index: true
      t.references :application,    null: false

      t.string   :token, null: false
      t.string   :refresh_token
      t.integer  :expires_in
      t.string   :scopes
      t.datetime :created_at, null: false
      t.datetime :revoked_at
      t.string   :previous_refresh_token, null: false, default: ""

      t.string   :resource
    end

    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :refresh_token, unique: true
    add_foreign_key :oauth_access_tokens, :oauth_applications, column: :application_id
    add_foreign_key :oauth_access_tokens, :users, column: :resource_owner_id
  end
end
