Rails.application.routes.draw do
  # Resend inbound email webhook endpoint
  mount ActionMailbox::Resend::Engine, at: "/rails/action_mailbox/resend"

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
    end
  end

  devise_for :users

  # Dashboard (authenticated)
  get "dashboard", to: "dashboard#index"

  # Developer / API Dashboard
  get "developer", to: "developer#index", as: :developer
  post "developer/api-keys", to: "developer#create_api_key", as: :create_api_key
  delete "developer/api-keys/:id", to: "developer#revoke_api_key", as: :revoke_api_key

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

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

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
