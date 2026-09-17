Rails.application.routes.draw do
  # Resend inbound email webhook endpoint
  mount ActionMailbox::Resend::Engine, at: "/rails/action_mailbox/resend"

  # Admin-only routes
  authenticate :user, ->(user) { user.admin? } do
    # Analytics dashboard
    get "admin/analytics", to: "admin/analytics#index", as: :admin_analytics

    # Solid Queue job monitoring dashboard
    mount MissionControl::Jobs::Engine, at: "admin/jobs"

    # PgHero database monitoring (only in production with PostgreSQL)
    mount PgHero::Engine, at: "admin/pghero" if Rails.env.production?
  end

  # Model Context Protocol endpoint for AI agents (Claude Code, Claude Desktop,
  # Cursor). An OAuth 2.1 resource server: see app/controllers/oauth.
  post "/mcp", to: "mcp/server#handle"
  match "/mcp", to: "mcp/server#unsupported", via: [ :get, :delete ]

  # OAuth 2.1 authorization server. Doorkeeper provides /oauth/authorize,
  # /oauth/token, /oauth/revoke and /oauth/introspect. The applications CRUD is
  # skipped because clients register themselves through /oauth/register.
  use_doorkeeper do
    # Our own authorizations controller only to widen the CSP form-action for
    # the consent screen; see Oauth::AuthorizationsController.
    controllers authorizations: "oauth/authorizations"
    skip_controllers :applications
  end

  # RFC 7591 dynamic client registration.
  post "/oauth/register", to: "oauth/registrations#create"

  # RFC 8414 authorization server metadata and RFC 9728 protected resource
  # metadata. Both are served at the bare path and with the resource path
  # appended, because clients probe either form depending on the spec revision.
  get "/.well-known/oauth-authorization-server", to: "oauth/metadata#authorization_server"
  get "/.well-known/oauth-authorization-server/*resource_path", to: "oauth/metadata#authorization_server"
  get "/.well-known/oauth-protected-resource", to: "oauth/metadata#protected_resource"
  get "/.well-known/oauth-protected-resource/*resource_path", to: "oauth/metadata#protected_resource"

  # API v1 endpoints
  namespace :api do
    namespace :v1 do
      # Commodity code endpoints
      get "commodity-codes/search", to: "commodity_codes#search"
      get "commodity-codes/:id", to: "commodity_codes#show"
      post "commodity-codes/suggest", to: "commodity_codes#suggest"
      post "commodity-codes/suggest-from-url", to: "commodity_codes#suggest_from_url"
      post "commodity-codes/batch", to: "commodity_codes#batch"

      # Batch job polling
      resources :batch_jobs, only: [ :index, :show ], path: "batch-jobs"

      # Webhooks management
      resources :webhooks, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :test
        end
      end

      # Usage statistics
      get "usage", to: "usage#show"
      get "usage/history", to: "usage#history"

      # Browser extension endpoints
      scope :extension, controller: :extension do
        post "lookup", action: :lookup, as: :extension_lookup
        get "usage", action: :usage, as: :extension_usage
        post "token", action: :exchange_token, as: :extension_token
        delete "token", action: :revoke_token
      end
    end
  end

  # Extension OAuth flow (web pages)
  get "extension/auth", to: "extension_auth#authorize", as: :extension_auth
  post "extension/auth", to: "extension_auth#create_code", as: :extension_auth_create
  get "extension/auth/callback", to: "extension_auth#callback", as: :extension_auth_callback

  # Google is the only identity provider, so Devise generates just the OmniAuth
  # callbacks. Session routes normally come from :database_authenticatable,
  # which this app no longer uses, so sign in and sign out are declared here.
  devise_for :users,
             skip: [ :sessions, :registrations, :passwords, :confirmations ],
             controllers: { omniauth_callbacks: "users/omniauth_callbacks" }

  devise_scope :user do
    get "users/sign_in", to: "users/sessions#new", as: :new_user_session
    delete "users/sign_out", to: "users/sessions#destroy", as: :destroy_user_session
  end

  # Dashboard routes (authenticated user area)
  scope "/dashboard" do
    # Dashboard index
    get "", to: "dashboard#index", as: :dashboard

    # Account settings. Replaces the Devise registration edit page: with Google
    # as the only identity there is no email or password to change here, but
    # closing the account still has to be possible.
    get "account", to: "users/accounts#show", as: :account
    delete "account", to: "users/accounts#destroy"

    # Developer / API Dashboard
    get "developer", to: "developer#index", as: :developer
    post "developer/api-keys", to: "developer#create_api_key", as: :create_api_key
    delete "developer/api-keys/:id", to: "developer#revoke_api_key", as: :revoke_api_key
    delete "developer/extension-tokens/:id", to: "developer#revoke_extension_token", as: :revoke_extension_token

    # Orders
    resources :orders, only: [ :index, :show, :new, :create ] do
      member do
        post :confirm_commodity_code
        post :refresh_tracking
      end
      collection do
        get :export
      end
    end

    # Simulate email forwarding (for testing)
    resources :test_emails, only: [ :new, :create ]

    # Product URL lookups
    resources :product_lookups, only: [ :new, :create, :show, :index ] do
      collection do
        post :create_from_photo
      end
      member do
        post :confirm_commodity_code
        post :add_to_order
      end
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA manifest and service worker (views in app/views/pwa/)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Sitemap for SEO
  get "sitemap.xml", to: "sitemap#index", as: :sitemap, defaults: { format: "xml" }

  # Root path - redirect to dashboard if logged in
  root "pages#home"

  # Home page lookup (inline quick lookup)
  post "lookup", to: "pages#lookup", as: :home_lookup

  # Static pages
  get "privacy", to: "pages#privacy", as: :privacy
  get "terms", to: "pages#terms", as: :terms

  # Blog
  get "blog", to: "blog#index", as: :blog
  get "blog/:slug", to: "blog#show", as: :blog_post
end
