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
    # API v1 routes
    namespace :v1 do
      # Categories endpoint
      resources :categories, only: [ :index ]

      # Categorization patterns management
      resources :patterns do
        collection do
          get :statistics
        end
      end

      # Categorization suggestions and feedback
      namespace :categorization do
        post :suggest
        post :feedback
        post :batch_suggest
        get :statistics
      end
    end

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

  # Admin routes
  namespace :admin do
    # Authentication routes
    get "login", to: "sessions#new"
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy"
    get "logout", to: "sessions#destroy"  # Allow GET for logout links

    # Pattern testing and management operations (must come before resources :patterns)
    get "patterns/test", to: "pattern_testing#test"
    post "patterns/test_pattern", to: "pattern_testing#test_pattern"
    get "patterns/:id/test_single", to: "pattern_testing#test_single", as: :test_single_pattern

    post "patterns/import", to: "pattern_management#import"
    get "patterns/export", to: "pattern_management#export"
    get "patterns/statistics", to: "pattern_management#statistics"
    get "patterns/performance", to: "pattern_management#performance"
    post "patterns/:id/toggle_active", to: "pattern_management#toggle_active", as: :toggle_active_pattern

    resources :patterns
    resources :composite_patterns do
      member do
        post :toggle_active
        get :test
      end
    end
    root "patterns#index"
  end

  # Categories route for JSON endpoint
  resources :categories, only: [:index]
  
  # Bulk operations routes (must come before general resources to avoid conflicts)
  scope "/expenses", controller: :expenses do
    post "bulk_categorize", action: :bulk_categorize, as: :bulk_categorize_expenses
    post "bulk_update_status", action: :bulk_update_status, as: :bulk_update_status_expenses
    delete "bulk_destroy", action: :bulk_destroy, as: :bulk_destroy_expenses
  end
  # Core expense CRUD routes
  resources :expenses, except: [] do
    collection do
      get :dashboard
      post :sync_emails
    end
    member do
      post :duplicate
    end
  end

  # Expense categorization routes (separated for clarity)
  scope "/expenses/:id", controller: :expenses do
    post "correct_category", action: :correct_category, as: :correct_category_expense
    post "accept_suggestion", action: :accept_suggestion, as: :accept_suggestion_expense
    post "reject_suggestion", action: :reject_suggestion, as: :reject_suggestion_expense
    patch "update_status", action: :update_status, as: :update_status_expense
  end

  resources :budgets do
    member do
      post :duplicate
      post :deactivate
    end
    collection do
      get :quick_set
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

  # Bulk categorization routes
  resources :bulk_categorizations, only: [ :index, :show ]

  # Bulk categorization actions
  post "bulk_categorizations/categorize", to: "bulk_categorization_actions#categorize"
  post "bulk_categorizations/suggest", to: "bulk_categorization_actions#suggest"
  post "bulk_categorizations/preview", to: "bulk_categorization_actions#preview"
  post "bulk_categorizations/auto_categorize", to: "bulk_categorization_actions#auto_categorize"
  get "bulk_categorizations/export", to: "bulk_categorization_actions#export"
  post "bulk_categorizations/:id/undo", to: "bulk_categorization_actions#undo", as: :undo_bulk_categorization

  # Analytics routes
  namespace :analytics do
    resources :pattern_dashboard, only: [ :index ], controller: "pattern_dashboard" do
      collection do
        get :trends
        get :heatmap
        get :export
        post :refresh
      end
    end
  end

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
