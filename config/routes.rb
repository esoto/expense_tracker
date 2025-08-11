require "sidekiq/web"

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Mount Sidekiq Web UI with authentication
  # In production, you should implement proper authentication
  if Rails.env.development?
    mount Sidekiq::Web => "/sidekiq"
  else
    # Basic HTTP authentication for production
    # You should replace this with your actual authentication system
    Sidekiq::Web.use Rack::Auth::Basic do |username, password|
      # Use ActiveSupport::SecurityUtils.secure_compare to prevent timing attacks
      ActiveSupport::SecurityUtils.secure_compare(username, ENV.fetch("SIDEKIQ_WEB_USERNAME", "admin")) &&
        ActiveSupport::SecurityUtils.secure_compare(password, ENV.fetch("SIDEKIQ_WEB_PASSWORD", "change_me_in_production"))
    end
    mount Sidekiq::Web => "/sidekiq"
  end

  # Mount ActionCable for WebSocket connections
  mount ActionCable.server => "/cable"

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

    # Health check endpoints for monitoring and Kubernetes probes
    get "health", to: "health#index"
    get "health/ready", to: "health#ready"
    get "health/live", to: "health#live"
    get "health/metrics", to: "health#metrics"

    # Sync session status polling endpoint
    resources :sync_sessions, only: [] do
      member do
        get :status
      end
    end

    # Client error reporting endpoint
    resources :client_errors, only: [ :create ]

    # Queue monitoring and management endpoints
    resource :queue, only: [], controller: "queue" do
      get :status
      get :metrics
      get :health
      post :pause
      post :resume
      post :retry_all_failed

      member do
        post "jobs/:id/retry", action: :retry_job, as: :retry_job
        post "jobs/:id/clear", action: :clear_job, as: :clear_job
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


  resources :sync_sessions, only: [ :index, :show, :create ] do
    member do
      post :cancel
      post :retry
    end
    collection do
      get :status
    end
  end

  resources :sync_conflicts do
    member do
      post :resolve
      post :undo
      post :preview_merge
      get :row
    end
    collection do
      post :bulk_resolve
    end
  end

  # Performance monitoring dashboard
  get "sync_performance", to: "sync_performance#index"
  get "sync_performance/export", to: "sync_performance#export"
  get "sync_performance/realtime", to: "sync_performance#realtime"

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
