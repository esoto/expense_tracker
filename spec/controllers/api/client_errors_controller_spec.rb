require 'rails_helper'

RSpec.describe Api::ClientErrorsController, type: :controller, unit: true do
  describe 'POST #create', unit: true do
    let(:error_params) do
      {
        message: 'WebSocket connection failed',
        data: { error_code: 'NETWORK_ERROR' },
        sessionId: 123,
        timestamp: 1234567890,
        userAgent: 'Mozilla/5.0',
        url: 'http://example.com/sync',
        errorCount: 3,
        pollingMode: false,
        connectionState: 'disconnected'
      }
    end

    it 'accepts error reports and returns success' do
      post :create, params: error_params, format: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['status']).to eq('received')
    end

    it 'logs the error to Rails logger' do
      expect(Rails.logger).to receive(:error).with(/CLIENT_ERROR.*WebSocket connection failed/)
      expect(Rails.logger).to receive(:error).with(/CLIENT_ERROR.*Details:/)

      post :create, params: error_params, format: :json
    end

    it 'includes IP address in error data' do
      # Just verify that IP address is included in the log (whatever it is)
      expect(Rails.logger).to receive(:error) do |message|
        if message.include?('Details:')
          expect(message).to include('"ip_address"')
        end
      end.at_least(:once)

      post :create, params: error_params, format: :json
    end

    context 'with minimal parameters' do
      it 'still accepts the error report' do
        post :create, params: { message: 'Test error' }, format: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when error logging fails' do
      before do
        allow(Rails.logger).to receive(:error).with(/CLIENT_ERROR/).and_raise(StandardError, 'Logging failed')
      end

      it 'still returns success to client' do
        post :create, params: error_params, format: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('error')
      end
    end

    context 'when ClientError model exists' do
      before do
        client_error_class = Class.new do
          def self.create!(*args)
            # Mock create! method
          end
        end
        stub_const('ClientError', client_error_class)
      end

      it 'creates a ClientError record' do
        expect(ClientError).to receive(:create!).with(hash_including(
          message: 'WebSocket connection failed',
          session_id: '123',
          user_agent: 'Mozilla/5.0'
        ))

        post :create, params: error_params, format: :json
      end
    end

    context 'with error tracking service' do
      let(:error_tracker) { double('ErrorTracker') }
      let(:config) { Rails.application.config }

      before do
        # Define the error_tracker method on config
        config.singleton_class.send(:attr_accessor, :error_tracker)
        config.error_tracker = error_tracker
      end

      after do
        # Clean up the added method
        config.singleton_class.send(:remove_method, :error_tracker) if config.respond_to?(:error_tracker)
        config.singleton_class.send(:remove_method, :error_tracker=) if config.respond_to?(:error_tracker=)
      end

      it 'sends error to tracking service' do
        expect(error_tracker).to receive(:track_client_error).with(hash_including(
          message: 'WebSocket connection failed'
        ))

        post :create, params: error_params, format: :json
      end
    end
  end
end
