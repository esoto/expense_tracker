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


  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check


  # Defines the root path route ("/")
  root "expenses#dashboard"
end
