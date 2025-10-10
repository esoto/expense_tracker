require 'rails_helper'

RSpec.describe Services::EmailProcessing::Fetcher, 'error handling', type: :service, unit: true do
  let(:email_account) { create(:email_account, :bac) }
  let(:mock_imap_service) { instance_double(ImapConnectionService) }
  let(:mock_email_processor) { instance_double(EmailProcessing::Processor) }
  let(:metrics_collector) { instance_double(SyncMetricsCollector) }

  let(:fetcher) do
    described_class.new(
      email_account,
      imap_service: mock_imap_service,
      email_processor: mock_email_processor,
      metrics_collector: metrics_collector
    )
  end

  before do
    allow(mock_imap_service).to receive(:errors).and_return([])
    allow(mock_email_processor).to receive(:errors).and_return([])
  end

  describe 'error accumulation', unit: true do
    context 'when multiple validation errors occur' do
      let(:fetcher_nil) do
        described_class.new(nil, imap_service: mock_imap_service, email_processor: mock_email_processor)
      end

      it 'accumulates all validation errors' do
        # First make account nil
        allow(fetcher).to receive(:email_account).and_return(nil)

        result = fetcher.fetch_new_emails
        expect(result.failure?).to be true
        expect(result.errors).to include('Email account not provided')
      end

      it 'stops validation on first error' do
        # With nil account, should not check active or password
        result = fetcher_nil.fetch_new_emails
        expect(result.errors.size).to eq(1)
        expect(result.errors).to include('Email account not provided')
      end
    end

    context 'when account validation fails at different stages' do
      it 'handles inactive account' do
        email_account.update(active: false)

        result = fetcher.fetch_new_emails
        expect(result.failure?).to be true
        expect(result.errors).to include('Email account is not active')
      end

      it 'handles missing password' do
        allow(email_account).to receive(:encrypted_password?).and_return(false)

        result = fetcher.fetch_new_emails
        expect(result.failure?).to be true
        expect(result.errors).to include('Email account missing password')
      end

      it 'handles blank encrypted password' do
        allow(email_account).to receive(:encrypted_password).and_return('')
        allow(email_account).to receive(:encrypted_password?).and_return(false)

        result = fetcher.fetch_new_emails
        expect(result.failure?).to be true
        expect(result.errors).to include('Email account missing password')
      end
    end

    context 'with processing errors after successful search' do
      before do
        allow(metrics_collector).to receive(:track_operation).and_yield
        allow(mock_imap_service).to receive(:search_emails).and_return([ 1, 2, 3 ])
      end

      it 'preserves errors array through processing' do
        allow(mock_email_processor).to receive(:process_emails)
          .and_return({ processed_count: 2, total_count: 3 })

        # Add an error during processing
        fetcher.send(:add_error, 'Warning: Partial processing')

        result = fetcher.fetch_new_emails
        expect(result.success?).to be true
        expect(result.errors).to include('Warning: Partial processing')
        expect(result.processed_emails_count).to eq(2)
        expect(result.total_emails_found).to eq(3)
      end
    end
  end

  describe 'error recovery strategies', unit: true do
    context 'with transient IMAP errors' do
      before do
        allow(metrics_collector).to receive(:track_operation).and_yield

        call_count = 0
        allow(mock_imap_service).to receive(:search_emails) do
          call_count += 1
          if call_count == 1
            raise ImapConnectionService::ConnectionError, 'Temporary network issue'
          else
            [ 1, 2 ]
          end
        end
      end

      it 'does not retry automatically (single attempt)' do
        result = fetcher.fetch_new_emails
        expect(result.failure?).to be true
        expect(result.errors).to include('IMAP Error: Temporary network issue')
      end
    end

    context 'with authentication errors' do
      before do
        allow(metrics_collector).to receive(:track_operation).and_yield
        allow(mock_imap_service).to receive(:search_emails)
          .and_raise(ImapConnectionService::AuthenticationError, 'Invalid credentials')
      end

      it 'captures authentication errors correctly' do
        result = fetcher.fetch_new_emails
        expect(result.failure?).to be true
        expect(result.errors).to include('IMAP Error: Invalid credentials')
      end

      it 'logs authentication errors' do
        expect(Rails.logger).to receive(:error)
          .with("[EmailProcessing::Fetcher] #{email_account.email}: IMAP Error: Invalid credentials")

        fetcher.fetch_new_emails
      end
    end

    context 'with unexpected errors during search' do
      before do
        allow(metrics_collector).to receive(:track_operation).and_yield
        allow(mock_imap_service).to receive(:search_emails)
          .and_raise(StandardError, 'Unexpected database error')
      end

      it 'handles unexpected errors with proper message format' do
        result = fetcher.fetch_new_emails
        expect(result.failure?).to be true
        expect(result.errors).to include('Unexpected error: Unexpected database error')
      end
    end

    context 'with errors in metrics collection' do
      before do
        allow(metrics_collector).to receive(:track_operation)
          .and_raise(StandardError, 'Metrics service unavailable')
      end

      it 'catches metrics errors and returns failure response' do
        result = fetcher.fetch_new_emails
        expect(result.failure?).to be true
        expect(result.errors).to include('Unexpected error: Metrics service unavailable')
      end
    end
  end

  describe 'error logging', unit: true do
    it 'logs errors with email account context' do
      expect(Rails.logger).to receive(:error)
        .with("[EmailProcessing::Fetcher] #{email_account.email}: Test error message")

      fetcher.send(:add_error, 'Test error message')
    end

    it 'logs errors with Unknown when email account is nil' do
      fetcher_nil = described_class.new(nil, imap_service: mock_imap_service)

      expect(Rails.logger).to receive(:error)
        .with('[EmailProcessing::Fetcher] Unknown: Test error message')

      fetcher_nil.send(:add_error, 'Test error message')
    end

    it 'accumulates errors in the errors array' do
      fetcher.send(:add_error, 'Error 1')
      fetcher.send(:add_error, 'Error 2')
      fetcher.send(:add_error, 'Error 3')

      expect(fetcher.errors).to eq([ 'Error 1', 'Error 2', 'Error 3' ])
    end

    it 'maintains error order' do
      fetcher.send(:add_error, 'First')
      fetcher.send(:add_error, 'Second')
      fetcher.send(:add_error, 'Third')

      expect(fetcher.errors.first).to eq('First')
      expect(fetcher.errors.last).to eq('Third')
    end
  end

  describe 'FetcherResponse error states', unit: true do
    context 'with validation failures' do
      before do
        email_account.update(active: false)
      end

      it 'returns proper failure response structure' do
        result = fetcher.fetch_new_emails

        expect(result).to be_a(EmailProcessing::FetcherResponse)
        expect(result.failure?).to be true
        expect(result.success?).to be false
        expect(result.processed_emails_count).to eq(0)
        expect(result.total_emails_found).to eq(0)
        expect(result.has_errors?).to be true
        expect(result.error_messages).to eq('Email account is not active')
      end
    end

    context 'with IMAP errors' do
      before do
        allow(metrics_collector).to receive(:track_operation).and_yield
        allow(mock_imap_service).to receive(:search_emails)
          .and_raise(ImapConnectionService::ConnectionError, 'Network timeout')
      end

      it 'returns failure response with IMAP error details' do
        result = fetcher.fetch_new_emails

        expect(result.failure?).to be true
        expect(result.errors).to eq([ 'IMAP Error: Network timeout' ])
        expect(result.error_messages).to eq('IMAP Error: Network timeout')
      end
    end

    context 'with partial success (warnings)' do
      before do
        allow(metrics_collector).to receive(:track_operation).and_yield
        allow(mock_imap_service).to receive(:search_emails).and_return([ 1, 2, 3 ])
        allow(mock_email_processor).to receive(:process_emails)
          .and_return({ processed_count: 2, total_count: 3 })
      end

      it 'can return success with warnings in errors array' do
        # Manually add a warning
        fetcher.instance_variable_set(:@errors, [ 'Warning: 1 email skipped' ])

        result = fetcher.fetch_new_emails

        expect(result.success?).to be true
        expect(result.has_errors?).to be true
        expect(result.errors).to include('Warning: 1 email skipped')
        expect(result.processed_emails_count).to eq(2)
        expect(result.total_emails_found).to eq(3)
      end
    end
  end

  describe 'error handling with sync session', unit: true do
    let(:sync_session) { create(:sync_session, :running) }
    let(:sync_session_account) do
      create(:sync_session_account,
             sync_session: sync_session,
             email_account: email_account,
             status: 'processing')
    end

    let(:fetcher_with_sync) do
      described_class.new(
        email_account,
        imap_service: mock_imap_service,
        email_processor: mock_email_processor,
        sync_session_account: sync_session_account,
        metrics_collector: metrics_collector
      )
    end

    context 'when sync session update fails' do
      before do
        allow(metrics_collector).to receive(:track_operation).and_yield
        allow(mock_imap_service).to receive(:search_emails).and_return([ 1 ])

        allow(sync_session_account).to receive(:update!)
          .with(total_emails: 1)
          .and_raise(StandardError, 'Validation failed')
      end

      it 'catches sync session update errors and returns failure' do
        result = fetcher_with_sync.fetch_new_emails
        expect(result.failure?).to be true
        expect(result.errors).to include('Unexpected error: Validation failed')
      end
    end

    context 'when progress update fails during processing' do
      before do
        allow(metrics_collector).to receive(:track_operation).and_yield
        allow(mock_imap_service).to receive(:search_emails).and_return([ 1 ])
        allow(sync_session_account).to receive(:update!).with(total_emails: 1)

        allow(sync_session_account).to receive(:update_progress)
          .and_raise(StandardError, 'Progress update failed')

        allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
          block&.call(1, 0, nil) if block
          { processed_count: 1, total_count: 1 }
        end
      end

      it 'logs error but continues processing' do
        expect(Rails.logger).to receive(:error)
          .with('[EmailProcessing::Fetcher] Failed to update progress: Progress update failed')

        result = fetcher_with_sync.fetch_new_emails
        expect(result.success?).to be true
        expect(result.processed_emails_count).to eq(1)
      end
    end
  end

  describe 'error message formatting', unit: true do
    it 'formats IMAP connection errors correctly' do
      allow(metrics_collector).to receive(:track_operation).and_yield
      allow(mock_imap_service).to receive(:search_emails)
        .and_raise(ImapConnectionService::ConnectionError, 'Connection refused')

      result = fetcher.fetch_new_emails
      expect(result.errors.first).to eq('IMAP Error: Connection refused')
    end

    it 'formats IMAP authentication errors correctly' do
      allow(metrics_collector).to receive(:track_operation).and_yield
      allow(mock_imap_service).to receive(:search_emails)
        .and_raise(ImapConnectionService::AuthenticationError, 'Bad credentials')

      result = fetcher.fetch_new_emails
      expect(result.errors.first).to eq('IMAP Error: Bad credentials')
    end

    it 'formats unexpected errors correctly' do
      allow(metrics_collector).to receive(:track_operation).and_yield
      allow(mock_imap_service).to receive(:search_emails)
        .and_raise(StandardError, 'Something went wrong')

      result = fetcher.fetch_new_emails
      expect(result.errors.first).to eq('Unexpected error: Something went wrong')
    end

    it 'handles errors with special characters' do
      allow(metrics_collector).to receive(:track_operation).and_yield
      allow(mock_imap_service).to receive(:search_emails)
        .and_raise(StandardError, "Error with 'quotes' and \"double quotes\"")

      result = fetcher.fetch_new_emails
      expect(result.errors.first).to include('quotes')
      expect(result.errors.first).to include('double quotes')
    end
  end
end
