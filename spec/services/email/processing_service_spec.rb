# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Email::ProcessingService, type: :service, unit: true do
  include EmailProcessingTestHelper

  let(:email_account) { create(:email_account, :bac, :gmail) }
  let(:processing_service) { described_class.new(email_account, options) }
  let(:options) { {} }
  let(:mock_imap) { create_mock_imap }
  let(:mock_categorization_engine) { stub_processing_dependencies }

  before do
    stub_imap_connection(mock_imap)
    # Ensure MonitoringService is properly stubbed for all tests
    allow(Infrastructure::MonitoringService::ErrorTracker).to receive(:report)
  end

  describe 'initialization' do
    it 'initializes with email account and options' do
      service = described_class.new(email_account, auto_categorize: true)

      expect(service.email_account).to eq(email_account)
      expect(service.options).to eq(auto_categorize: true)
      expect(service.errors).to be_empty
      expect(service.metrics).to have_metrics_structure
    end

    it 'initializes metrics with zero values' do
      expect(processing_service.metrics).to eq({
        emails_found: 0,
        emails_processed: 0,
        expenses_created: 0,
        processing_time: 0
      })
    end

    it 'creates default categorization engine when none provided' do
      expect(Categorization::Engine).to receive(:create)
      described_class.new(email_account)
    end

    it 'accepts injected categorization engine' do
      custom_engine = double("custom_engine")
      service = described_class.new(email_account, categorization_engine: custom_engine)

      # Access the private instance variable to verify injection
      engine = service.instance_variable_get(:@categorization_engine)
      expect(engine).to eq(custom_engine)
    end
  end

  describe '#valid_account?' do
    context 'with valid email account' do
      it 'returns true for account with email and password' do
        expect(processing_service.send(:valid_account?)).to be true
      end

      it 'returns true for account with email and oauth configuration' do
        email_account.encrypted_password = nil
        email_account.encrypted_settings = { oauth: { access_token: "token123" } }.to_json

        expect(processing_service.send(:valid_account?)).to be true
      end
    end

    context 'with invalid email account' do
      it 'returns false when email_account is nil' do
        service = described_class.new(nil)
        expect(service.send(:valid_account?)).to be false
      end

      it 'returns false when email is blank' do
        email_account.email = ''
        expect(processing_service.send(:valid_account?)).to be false
        expect(processing_service.errors).to include("Email address is required")
      end

      it 'returns false when email is nil' do
        email_account.email = nil
        expect(processing_service.send(:valid_account?)).to be false
        expect(processing_service.errors).to include("Email address is required")
      end

      it 'returns false when password is blank and no oauth' do
        email_account.encrypted_password = ''
        expect(processing_service.send(:valid_account?)).to be false
        expect(processing_service.errors).to include("Password or OAuth configuration is required")
      end

      it 'returns false when password is nil and no oauth' do
        email_account.encrypted_password = nil
        expect(processing_service.send(:valid_account?)).to be false
        expect(processing_service.errors).to include("Password or OAuth configuration is required")
      end

      it 'reports first validation error encountered' do
        email_account.email = ''
        email_account.encrypted_password = ''

        expect(processing_service.send(:valid_account?)).to be false
        expect(processing_service.errors).to include("Email address is required")
        # Password validation is not reached because email validation fails first
        expect(processing_service.errors).not_to include("Password or OAuth configuration is required")
      end
    end

    context 'oauth configuration validation' do
      it 'validates oauth_configured? method behavior' do
        # No oauth settings
        expect(email_account.oauth_configured?).to be false

        # With access token
        email_account.encrypted_settings = { oauth: { access_token: "token" } }.to_json
        expect(email_account.oauth_configured?).to be true

        # With refresh token
        email_account.encrypted_settings = { oauth: { refresh_token: "refresh" } }.to_json
        expect(email_account.oauth_configured?).to be true
      end
    end
  end

  describe '#process_new_emails' do
    let(:since) { 1.week.ago }
    let(:until_date) { nil }

    context 'with invalid account' do
      let(:invalid_email_account) { build(:email_account, email: '') }
      let(:invalid_processing_service) { described_class.new(invalid_email_account, options) }

      it 'returns failure response without processing' do
        result = invalid_processing_service.process_new_emails(since: since)

        expect(result).to be_valid_processing_response
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Invalid email account")
        expect(result[:errors]).to include("Email address is required")
        expect(result[:metrics]).to have_metrics_structure
      end

      it 'does not attempt IMAP connection with invalid account' do
        expect(Net::IMAP).not_to receive(:new)
        invalid_processing_service.process_new_emails(since: since)
      end
    end

    context 'with valid account but IMAP errors' do
      it 'handles connection errors gracefully' do
        mock_imap.configure_connection_error(Email::ProcessingService::ConnectionError.new("Connection failed"))

        result = processing_service.process_new_emails(since: since)

        expect(result).to be_valid_processing_response
        expect(result[:success]).to be false
        expect(result[:error]).to include("Email processing failed")
        expect(Infrastructure::MonitoringService::ErrorTracker).to have_received(:report)
      end

      it 'handles authentication errors gracefully' do
        mock_imap.configure_auth_error(Email::ProcessingService::AuthenticationError.new("Auth failed"))

        result = processing_service.process_new_emails(since: since)

        expect(result).to be_valid_processing_response
        expect(result[:success]).to be false
        expect(result[:error]).to include("Email processing failed")
      end

      it 'handles generic IMAP errors' do
        allow(mock_imap).to receive(:examine).and_raise(StandardError.new("IMAP server error"))

        result = processing_service.process_new_emails(since: since)

        expect(result[:success]).to be false
        expect(result[:error]).to include("IMAP server error")
      end
    end

    context 'with successful IMAP connection' do
      let(:email_fixtures) { [ EmailProcessingTestHelper::EmailFixtures.bac_transaction_email ] }

      before do
        setup_imap_mock_with_emails(mock_imap, email_fixtures)
      end

      it 'tracks processing time in metrics' do
        start_time = Time.current
        result = processing_service.process_new_emails(since: since)

        # Processing time should be a small positive number
        expect(result[:metrics][:processing_time]).to be > 0
        expect(result[:metrics][:processing_time]).to be < 1.0 # Should complete in less than 1 second
      end

      it 'updates emails_found metric' do
        result = processing_service.process_new_emails(since: since)

        expect(result[:metrics][:emails_found]).to eq(1)
      end

      it 'calls IMAP methods in correct sequence' do
        processing_service.process_new_emails(since: since)

        expect(mock_imap.examined_folder).to eq("INBOX")
        expect(mock_imap.authenticated).to be true
        expect(mock_imap.disconnected).to be true
      end
    end
  end

  describe '#fetch_only' do
    context 'with invalid account' do
      let(:invalid_email_account) { build(:email_account, email: '') }
      let(:invalid_processing_service) { described_class.new(invalid_email_account, options) }

      it 'returns empty array for invalid account' do
        result = invalid_processing_service.fetch_only(since: 1.week.ago)
        expect(result).to eq([])
      end

      it 'does not attempt IMAP connection' do
        expect(Net::IMAP).not_to receive(:new)
        invalid_processing_service.fetch_only(since: 1.week.ago)
      end
    end

    context 'with valid account' do
      let(:email_fixtures) { [ EmailProcessingTestHelper::EmailFixtures.bcr_transaction_email ] }

      before do
        setup_imap_mock_with_emails(mock_imap, email_fixtures)
      end

      it 'applies limit option correctly' do
        result = processing_service.fetch_only(since: 1.week.ago, limit: 50)

        # Verify limit was set in options
        expect(processing_service.options[:limit]).to eq(50)
      end

      it 'fetches emails without processing them' do
        # Mock processed emails check to verify no processing
        allow(processing_service).to receive(:process_emails).and_call_original

        result = processing_service.fetch_only(since: 1.week.ago)

        expect(processing_service).not_to have_received(:process_emails)
        expect(result).to be_an(Array)
      end
    end
  end

  describe '#test_connection' do
    context 'with successful connection' do
      it 'returns success response' do
        result = processing_service.test_connection

        expect(result).to eq({ success: true, message: "Connection successful" })
        expect(mock_imap.examined_folder).to eq("INBOX")
      end
    end

    context 'with connection failure' do
      it 'returns failure response for connection error' do
        mock_imap.configure_connection_error(StandardError.new("Connection timeout"))

        result = processing_service.test_connection

        expect(result).to eq({ success: false, message: "Connection timeout" })
      end

      it 'returns failure response for authentication error' do
        mock_imap.configure_auth_error(StandardError.new("Invalid credentials"))

        result = processing_service.test_connection

        expect(result).to eq({ success: false, message: "IMAP authentication failed: Invalid credentials" })
      end
    end
  end

  describe 'error handling and metrics tracking' do
    describe '#add_error' do
      it 'adds error to errors array and logs it' do
        allow(Rails.logger).to receive(:error)

        processing_service.send(:add_error, "Test error message")

        expect(processing_service.errors).to include("Test error message")
        expect(Rails.logger).to have_received(:error).with("EmailProcessingService Error: Test error message")
      end
    end

    describe '#handle_error' do
      let(:test_error) { StandardError.new("Test error") }

      it 'adds error and reports to monitoring service' do
        processing_service.send(:handle_error, test_error)

        expect(processing_service.errors).to include("Test error")
        expect(Infrastructure::MonitoringService::ErrorTracker).to have_received(:report).with(
          test_error,
          context: {
            email_account_id: email_account.id,
            service: "EmailProcessingService"
          }
        )
      end
    end

    describe 'metrics initialization and structure' do
      it 'initializes with correct metrics structure' do
        service = described_class.new(email_account)

        expect(service.metrics).to match({
          emails_found: 0,
          emails_processed: 0,
          expenses_created: 0,
          processing_time: 0
        })
      end

      it 'all metric values are numeric' do
        expect(processing_service.metrics.values).to all(be_a(Numeric))
      end
    end
  end

  describe 'response format validation' do
    describe '#success_response' do
      it 'returns properly formatted success response' do
        results = { processed: 1, expenses_created: 2, errors: [] }
        response = processing_service.send(:success_response, results)

        expect(response).to be_valid_processing_response
        expect(response).to match({
          success: true,
          metrics: processing_service.metrics,
          details: results
        })
      end
    end

    describe '#failure_response' do
      it 'returns properly formatted failure response' do
        processing_service.send(:add_error, "Validation failed")
        response = processing_service.send(:failure_response, "Processing failed")

        expect(response).to be_valid_processing_response
        expect(response).to match({
          success: false,
          error: "Processing failed",
          errors: [ "Validation failed" ],
          metrics: processing_service.metrics
        })
      end

      it 'includes empty errors array when no errors present' do
        response = processing_service.send(:failure_response, "Simple failure")

        expect(response[:errors]).to eq([])
      end
    end

    describe 'response consistency' do
      it 'both success and failure responses include metrics' do
        success = processing_service.send(:success_response, {})
        failure = processing_service.send(:failure_response, "Error")

        expect(success[:metrics]).to have_metrics_structure
        expect(failure[:metrics]).to have_metrics_structure
      end

      it 'success response includes details, failure includes error' do
        details = { test: "data" }
        success = processing_service.send(:success_response, details)
        failure = processing_service.send(:failure_response, "Error message")

        expect(success[:details]).to eq(details)
        expect(success).not_to have_key(:error)

        expect(failure[:error]).to eq("Error message")
        expect(failure).not_to have_key(:details)
      end
    end
  end

  describe 'infrastructure integration' do
    it 'integrates with MonitoringService for error tracking' do
      error = StandardError.new("Integration test error")

      processing_service.send(:handle_error, error)

      expect(Infrastructure::MonitoringService::ErrorTracker).to have_received(:report).with(
        error,
        context: {
          email_account_id: email_account.id,
          service: "EmailProcessingService"
        }
      )
    end

    it 'supports categorization engine dependency injection' do
      custom_engine = double("custom_categorization_engine")
      service = described_class.new(email_account, categorization_engine: custom_engine)

      injected_engine = service.instance_variable_get(:@categorization_engine)
      expect(injected_engine).to eq(custom_engine)
    end

    it 'creates default categorization engine when not injected' do
      expect(Categorization::Engine).to receive(:create).and_return(mock_categorization_engine)

      service = described_class.new(email_account)
      expect(service.instance_variable_get(:@categorization_engine)).to eq(mock_categorization_engine)
    end
  end

  describe 'Costa Rican bank integration readiness' do
    context 'bank-specific email account configurations' do
      let(:bac_account) { create(:email_account, :bac, :gmail) }
      let(:bcr_account) { create(:email_account, :bcr, :outlook) }
      let(:scotia_account) { create(:email_account, :scotiabank, :custom) }

      it 'validates BAC account configuration' do
        service = described_class.new(bac_account)
        expect(service.send(:valid_account?)).to be true
        expect(bac_account.bank_name).to eq("BAC")
      end

      it 'validates BCR account configuration' do
        service = described_class.new(bcr_account)
        expect(service.send(:valid_account?)).to be true
        expect(bcr_account.bank_name).to eq("BCR")
      end

      it 'validates Scotiabank account configuration' do
        service = described_class.new(scotia_account)
        expect(service.send(:valid_account?)).to be true
        expect(scotia_account.bank_name).to eq("Scotiabank")
      end
    end

    context 'email fixtures validation' do
      it 'has comprehensive Costa Rican bank fixtures' do
        expect(EmailProcessingTestHelper::EmailFixtures.bac_transaction_email[:from]).to eq("notificacion@notificacionesbaccr.com")
        expect(EmailProcessingTestHelper::EmailFixtures.bcr_transaction_email[:from]).to eq("alertas@bncr.fi.cr")
        expect(EmailProcessingTestHelper::EmailFixtures.scotiabank_transaction_email[:from]).to eq("notificaciones@scotiabank.com")

        # Verify all fixtures have required structure
        [ EmailProcessingTestHelper::EmailFixtures.bac_transaction_email, EmailProcessingTestHelper::EmailFixtures.bcr_transaction_email,
         EmailProcessingTestHelper::EmailFixtures.scotiabank_transaction_email ].each do |fixture|
          expect(fixture).to include(:from, :subject, :date, :body, :raw_content)
          expect(fixture[:raw_content]).to be_present
        end
      end

      it 'includes promotional email detection fixtures' do
        expect(EmailProcessingTestHelper::EmailFixtures.promotional_email[:from]).to include("promociones")
        expect(EmailProcessingTestHelper::EmailFixtures.non_transaction_email[:from]).not_to include("bac")
      end
    end
  end

  # Performance and optimization tests
  describe 'performance characteristics', :aggregate_failures do
    it 'completes validation quickly' do
      start_time = Time.current
      1000.times { processing_service.send(:valid_account?) }
      duration = Time.current - start_time

      expect(duration).to be < 1.0 # Should complete 1000 validations in under 1 second
    end

    it 'handles error collection efficiently' do
      start_objects = GC.stat(:total_allocated_objects)
      100.times { |i| processing_service.send(:add_error, "Error #{i}") }
      end_objects = GC.stat(:total_allocated_objects)

      object_increase = end_objects - start_objects
      expect(object_increase).to be < 5000 # Should allocate fewer than 5000 objects for 100 errors (includes string creation, logging, etc.)
    end
  end
end
