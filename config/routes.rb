Rails.application.routes.draw do
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

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Root path - redirect to dashboard if logged in
  root "pages#home"
end
