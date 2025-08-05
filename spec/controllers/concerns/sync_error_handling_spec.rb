require 'rails_helper'

RSpec.describe SyncErrorHandling, type: :controller do
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
    routes.draw do
      get 'not_found' => 'anonymous#not_found'
      get 'validation_error' => 'anonymous#validation_error'
      get 'unexpected_error' => 'anonymous#unexpected_error'
      get 'sync_limit' => 'anonymous#sync_limit'
      get 'rate_limit' => 'anonymous#rate_limit'
    end

    allow(controller).to receive(:sync_sessions_path).and_return('/sync_sessions')
  end

  describe 'ActiveRecord::RecordNotFound handling' do
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

  describe 'ActiveRecord::RecordInvalid handling' do
    it 'redirects with validation errors for HTML' do
      get :validation_error
      expect(response).to redirect_to('/sync_sessions')
      expect(flash[:alert]).to include("Error de validación:")
      expect(flash[:alert]).to include("Amount can't be blank")
      expect(flash[:alert]).to include("Category must exist")
    end

    it 'returns validation errors for JSON' do
      get :validation_error, format: :json
      expect(response).to have_http_status(:unprocessable_entity)
      errors = JSON.parse(response.body)["errors"]
      expect(errors).to include("Amount can't be blank")
      expect(errors).to include("Category must exist")
    end
  end

  describe 'sync limit exceeded handling' do
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

  describe 'rate limit exceeded handling' do
    it 'redirects with rate limit message for HTML' do
      get :rate_limit
      expect(response).to redirect_to('/sync_sessions')
      expect(flash[:alert]).to eq("Has alcanzado el límite de sincronizaciones. Intenta nuevamente en unos minutos.")
    end

    it 'returns rate limit error for JSON' do
      get :rate_limit, format: :json
      expect(response).to have_http_status(:too_many_requests)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("Rate limit exceeded")
      expect(body["retry_after"]).to eq(300)
    end
  end

  context 'in production environment' do
    controller(ApplicationController) do
      include SyncErrorHandling

      def unexpected_error
        raise StandardError, "Something went wrong"
      end
    end

    before do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      routes.draw do
        get 'unexpected_error' => 'anonymous#unexpected_error'
      end
      allow(controller).to receive(:sync_sessions_path).and_return('/sync_sessions')
    end

    describe 'StandardError handling' do
      it 'logs the error and redirects for HTML' do
        skip "Production error handling is tested in integration tests"
        expect(Rails.logger).to receive(:error).with(/Unexpected error in/)
        expect(Rails.logger).to receive(:error).with(/Something went wrong/)

        get :unexpected_error
        expect(response).to redirect_to('/sync_sessions')
        expect(flash[:alert]).to eq("Ocurrió un error inesperado. Por favor intenta nuevamente.")
      end

      it 'returns internal server error for JSON' do
        skip "Production error handling is tested in integration tests"
        allow(Rails.logger).to receive(:error)

        get :unexpected_error, format: :json
        expect(response).to have_http_status(:internal_server_error)
        expect(JSON.parse(response.body)["error"]).to eq("Internal server error")
      end
    end
  end
end
