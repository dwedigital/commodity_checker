Rails.application.routes.draw do
  # Resend inbound email webhook endpoint
  mount ActionMailbox::Resend::Engine, at: "/rails/action_mailbox/resend"

  devise_for :users

  # Dashboard (authenticated)
  get "dashboard", to: "dashboard#index"

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
