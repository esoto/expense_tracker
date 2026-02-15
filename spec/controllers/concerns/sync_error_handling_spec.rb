# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncErrorHandling, type: :controller, unit: true do
  controller(ApplicationController) do
    include SyncErrorHandling

    def not_found
      raise ActiveRecord::RecordNotFound
    end

    def validation_error
      expense = Expense.new
      expense.errors.add(:amount, "can't be blank")
      expense.errors.add(:category, "must exist")
      raise ActiveRecord::RecordInvalid.new(expense)
    end

    def unexpected_error
      raise StandardError, "Something went wrong"
    end

    def sync_limit
      handle_sync_limit_exceeded
    end

    def rate_limit
      handle_rate_limit_exceeded
    end
  end

  before do
    allow(controller).to receive(:authenticate_user!).and_return(true)

    routes.draw do
      get 'not_found' => 'anonymous#not_found'
      get 'validation_error' => 'anonymous#validation_error'
      get 'unexpected_error' => 'anonymous#unexpected_error'
      get 'sync_limit' => 'anonymous#sync_limit'
      get 'rate_limit' => 'anonymous#rate_limit'
    end

    allow(controller).to receive(:sync_sessions_path).and_return('/sync_sessions')
  end

  # Note: Cannot use error handling concern shared examples as
  # they expect specific model setups and contexts

  describe 'ActiveRecord::RecordNotFound handling', unit: true do
    it 'redirects to sync sessions with alert for HTML' do
      get :not_found
      expect(response).to redirect_to('/sync_sessions')
      expect(flash[:alert]).to eq("Sincronización no encontrada")
    end

    it 'returns not found status for JSON' do
      get :not_found, format: :json
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("Not found")
    end
  end

  describe 'ActiveRecord::RecordInvalid handling', unit: true do
    it 'redirects with validation errors for HTML' do
      get :validation_error
      expect(response).to redirect_to('/sync_sessions')
      expect(flash[:alert]).to include("Error de validación:")
      expect(flash[:alert]).to include("Amount can't be blank")
      expect(flash[:alert]).to include("Category must exist")
    end

    it 'returns validation errors for JSON' do
      get :validation_error, format: :json
      expect(response).to have_http_status(:unprocessable_content)
      errors = JSON.parse(response.body)["errors"]
      expect(errors).to include("Amount can't be blank")
      expect(errors).to include("Category must exist")
    end
  end

  describe 'sync limit exceeded handling', unit: true do
    it 'redirects with appropriate message for HTML' do
      get :sync_limit
      expect(response).to redirect_to('/sync_sessions')
      expect(flash[:alert]).to eq("Ya hay una sincronización activa. Espera a que termine antes de iniciar otra.")
    end

    it 'returns too many requests status for JSON' do
      get :sync_limit, format: :json
      expect(response).to have_http_status(:too_many_requests)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("Sync limit exceeded")
      expect(body["message"]).to eq("Active sync already in progress")
    end
  end

  describe 'rate limit exceeded handling', unit: true do
    it 'redirects with rate limit message for HTML' do
      get :rate_limit
      expect(response).to redirect_to('/sync_sessions')
      expect(flash[:alert]).to eq("Has alcanzado el límite de sincronizaciones. Intenta nuevamente en unos minutos.")
    end

    it 'returns rate limit error for JSON' do
      get :rate_limit, format: :json
      expect(response).to have_http_status(:too_many_requests)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("Too many requests")
      expect(body["message"]).to eq("You have exceeded the rate limit. Please try again later.")
      expect(body["retry_after"]).to be_a(String)
    end
  end

  describe 'StandardError handling in development', unit: true do
    it 'does not handle unexpected errors (lets them bubble up)' do
      expect { get :unexpected_error }.to raise_error(StandardError, "Something went wrong")
    end
  end

  describe 'production environment behavior', unit: true do
    before do
      # Mock Rails.logger for unexpected error logging
      allow(Rails.logger).to receive(:error)
    end

    it 'logs unexpected errors with details' do
      exception = StandardError.new("Test error")
      exception.set_backtrace([ "line1", "line2" ])

      # Mock the Rails.env check and respond_to call to avoid complexity
      allow(controller).to receive(:respond_to)
      allow(controller).to receive(:controller_name).and_return('Test')

      controller.send(:handle_unexpected_error, exception)

      expect(Rails.logger).to have_received(:error).with("Unexpected error in Test: Test error")
      expect(Rails.logger).to have_received(:error).with("line1\nline2")
    end

    it 'logs error message and backtrace separately' do
      exception = StandardError.new("Database connection failed")
      exception.set_backtrace([ "app/models/user.rb:10", "app/controllers/users_controller.rb:15" ])

      # Mock the controller name and respond_to to avoid complex setup
      allow(controller).to receive(:controller_name).and_return('User')
      allow(controller).to receive(:respond_to)

      controller.send(:handle_unexpected_error, exception)

      expect(Rails.logger).to have_received(:error).with("Unexpected error in User: Database connection failed")
      expect(Rails.logger).to have_received(:error).with("app/models/user.rb:10\napp/controllers/users_controller.rb:15")
    end
  end
end
