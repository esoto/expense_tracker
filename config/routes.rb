Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # API routes for iPhone Shortcuts and webhooks
  namespace :api do
    resources :webhooks, only: [] do
      collection do
        post :process_emails
        post :add_expense
        get :recent_expenses
        get :expense_summary
      end
    end
  end

  # Web interface routes
  resources :expenses do
    collection do
      get :dashboard
      post :sync_emails
    end
  end

  resources :email_accounts

  # UX Mockups routes (development only)
  if Rails.env.development?
    get "ux_mockups", to: "ux_mockups#index"
    get "ux_mockups/mobile_expense_cards", to: "ux_mockups#mobile_expense_cards"
    get "ux_mockups/sync_status_dashboard", to: "ux_mockups#sync_status_dashboard"
    get "ux_mockups/inline_categorization", to: "ux_mockups#inline_categorization"
    get "ux_mockups/color_palettes", to: "ux_mockups#color_palettes"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check


  # Defines the root path route ("/")
  root "expenses#dashboard"
end
