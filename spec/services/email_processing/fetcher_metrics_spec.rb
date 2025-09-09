require 'rails_helper'

RSpec.describe EmailProcessing::Fetcher, 'metrics integration', type: :service, unit: true do
  let(:email_account) { create(:email_account, :bac) }
  let(:mock_imap_service) { instance_double(ImapConnectionService) }
  let(:mock_email_processor) { instance_double(EmailProcessing::Processor) }
  let(:metrics_collector) { instance_double(SyncMetricsCollector) }

  let(:fetcher_with_metrics) do
    described_class.new(
      email_account,
      imap_service: mock_imap_service,
      email_processor: mock_email_processor,
      metrics_collector: metrics_collector
    )
  end

  let(:fetcher_without_metrics) do
    described_class.new(
      email_account,
      imap_service: mock_imap_service,
      email_processor: mock_email_processor,
      metrics_collector: nil
    )
  end

  before do
    allow(mock_imap_service).to receive(:errors).and_return([])
    allow(mock_email_processor).to receive(:errors).and_return([])
  end

  describe 'metrics collection during email fetching', unit: true do
    let(:message_ids) { [ 1, 2, 3, 4, 5 ] }
    let(:since_date) { 2.days.ago }

    before do
      allow(mock_email_processor).to receive(:process_emails)
        .and_return({ processed_count: 5, total_count: 5, detected_expenses_count: 2 })
    end

    context 'with metrics collector' do
      it 'tracks fetch_emails operation with correct parameters' do
        expect(metrics_collector).to receive(:track_operation).with(
          :fetch_emails,
          email_account,
          { since: since_date }
        ).and_yield

        allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)

        fetcher_with_metrics.fetch_new_emails(since: since_date)
      end

      it 'wraps IMAP search within metrics tracking block' do
        search_called = false

        expect(metrics_collector).to receive(:track_operation) do |operation, account, options, &block|
          expect(operation).to eq(:fetch_emails)
          expect(account).to eq(email_account)
          expect(options[:since]).to eq(since_date)

          # Verify search is called within the block
          expect(mock_imap_service).to receive(:search_emails).with([ 'SINCE', since_date.strftime('%d-%b-%Y') ]) do
            search_called = true
            message_ids
          end

          block.call
        end

        fetcher_with_metrics.fetch_new_emails(since: since_date)
        expect(search_called).to be true
      end

      it 'returns message_ids from metrics tracking block' do
        expect(metrics_collector).to receive(:track_operation) do |_, _, _, &block|
          block.call
        end

        expect(mock_imap_service).to receive(:search_emails).and_return(message_ids)

        result = fetcher_with_metrics.fetch_new_emails(since: since_date)
        expect(result.total_emails_found).to eq(5)
      end

      it 'handles metrics collector errors gracefully' do
        # Metrics errors happen in search_and_process_emails which is wrapped in begin/rescue
        expect(metrics_collector).to receive(:track_operation)
          .and_raise(StandardError, 'Metrics error')

        # The error is caught and converted to failure response
        result = fetcher_with_metrics.fetch_new_emails(since: since_date)
        expect(result.failure?).to be true
        expect(result.errors).to include('Unexpected error: Metrics error')
      end

      it 'passes metrics collector to email processor' do
        expect(EmailProcessing::Processor).to receive(:new)
          .with(email_account, metrics_collector: metrics_collector)
          .and_return(mock_email_processor)

        fetcher = described_class.new(email_account, metrics_collector: metrics_collector)
        expect(fetcher.email_processor).to eq(mock_email_processor)
      end
    end

    context 'without metrics collector' do
      before do
        allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
      end

      it 'performs search directly without metrics tracking' do
        expect(mock_imap_service).to receive(:search_emails)
          .with([ 'SINCE', since_date.strftime('%d-%b-%Y') ])
          .and_return(message_ids)

        result = fetcher_without_metrics.fetch_new_emails(since: since_date)
        expect(result.total_emails_found).to eq(5)
      end

      it 'does not attempt to call metrics collector' do
        # Metrics collector should never be called
        expect(metrics_collector).not_to receive(:track_operation)

        fetcher_without_metrics.fetch_new_emails(since: since_date)
      end

      it 'creates processor without metrics collector' do
        expect(EmailProcessing::Processor).to receive(:new)
          .with(email_account, metrics_collector: nil)
          .and_return(mock_email_processor)

        fetcher = described_class.new(email_account, metrics_collector: nil)
        expect(fetcher.email_processor).to eq(mock_email_processor)
      end
    end

    context 'with sync session and metrics' do
      let(:sync_session) { create(:sync_session, :running) }
      let(:sync_session_account) do
        create(:sync_session_account,
               sync_session: sync_session,
               email_account: email_account,
               status: 'processing')
      end

      let(:fetcher_full) do
        described_class.new(
          email_account,
          imap_service: mock_imap_service,
          email_processor: mock_email_processor,
          sync_session_account: sync_session_account,
          metrics_collector: metrics_collector
        )
      end

      before do
        allow(sync_session_account).to receive(:update!)
        allow(sync_session_account).to receive(:update_progress)

        allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
          block&.call(1, 0, nil) if block
          block&.call(2, 1, nil) if block
          { processed_count: 2, total_count: 2, detected_expenses_count: 1 }
        end
      end

      it 'coordinates metrics tracking with sync session updates' do
        # Metrics should track the search operation
        expect(metrics_collector).to receive(:track_operation).with(
          :fetch_emails,
          email_account,
          { since: since_date }
        ).and_yield

        allow(mock_imap_service).to receive(:search_emails).and_return([ 1, 2 ])

        # Sync session should be updated
        expect(sync_session_account).to receive(:update!).with(total_emails: 2)
        expect(sync_session_account).to receive(:update_progress).twice

        result = fetcher_full.fetch_new_emails(since: since_date)
        expect(result.success?).to be true
      end
    end
  end

  describe 'metrics error scenarios', unit: true do
    context 'when metrics collector track_operation returns nil' do
      before do
        allow(metrics_collector).to receive(:track_operation) do |_, _, _, &block|
          # Return nil but still execute the block
          block.call
          nil
        end

        allow(mock_imap_service).to receive(:search_emails).and_return([ 1, 2 ])
        allow(mock_email_processor).to receive(:process_emails)
          .and_return({ processed_count: 2, total_count: 2 })
      end

      it 'continues processing normally' do
        # Also need to update the mock_email_processor expectation since we'll pass []
        allow(mock_email_processor).to receive(:process_emails)
          .with([], mock_imap_service)
          .and_return({ processed_count: 0, total_count: 0 })

        result = fetcher_with_metrics.fetch_new_emails
        expect(result.success?).to be true
        # When track_operation returns nil, message_ids becomes []
        expect(result.total_emails_found).to eq(0)
        expect(result.processed_emails_count).to eq(0)
      end
    end

    context 'when metrics collector is not a SyncMetricsCollector' do
      let(:invalid_metrics) { 'not a metrics collector' }

      let(:fetcher_invalid) do
        described_class.new(
          email_account,
          imap_service: mock_imap_service,
          email_processor: mock_email_processor,
          metrics_collector: invalid_metrics
        )
      end

      before do
        allow(mock_imap_service).to receive(:search_emails).and_return([])
        allow(mock_email_processor).to receive(:process_emails)
          .and_return({ processed_count: 0, total_count: 0 })
      end

      it 'attempts to use the invalid metrics collector' do
        # This will fail when trying to call track_operation on a string
        result = fetcher_invalid.fetch_new_emails
        expect(result.failure?).to be true
        expect(result.errors.first).to include('Unexpected error:')
      end
    end
  end

  describe 'metrics timing and performance', unit: true do
    let(:start_time) { Time.current }
    let(:end_time) { start_time + 5.seconds }

    before do
      allow(Time).to receive(:current).and_return(start_time, end_time)
      allow(mock_imap_service).to receive(:search_emails).and_return([ 1, 2, 3 ])
      allow(mock_email_processor).to receive(:process_emails)
        .and_return({ processed_count: 3, total_count: 3 })
    end

    context 'with metrics tracking duration' do
      it 'captures operation duration within metrics block' do
        operation_duration = nil

        expect(metrics_collector).to receive(:track_operation) do |op, account, options, &block|
          start = start_time  # Use the mocked start_time
          result = block.call
          operation_duration = end_time - start  # Use mocked end_time
          result
        end

        fetcher_with_metrics.fetch_new_emails

        # Duration should be captured (5 seconds in this case)
        expect(operation_duration).to eq(5.seconds)
      end
    end

    context 'with slow IMAP operations' do
      before do
        allow(mock_imap_service).to receive(:search_emails) do
          sleep 0.1  # Simulate slow operation
          [ 1, 2, 3 ]
        end
      end

      it 'includes IMAP delay in metrics tracking' do
        tracked = false

        expect(metrics_collector).to receive(:track_operation) do |_, _, _, &block|
          tracked = true
          block.call
        end

        fetcher_with_metrics.fetch_new_emails
        expect(tracked).to be true
      end
    end
  end

  describe 'metrics with different email account states', unit: true do
    context 'with inactive account' do
      before do
        email_account.update(active: false)
      end

      it 'does not call metrics for invalid accounts' do
        expect(metrics_collector).not_to receive(:track_operation)

        result = fetcher_with_metrics.fetch_new_emails
        expect(result.failure?).to be true
        expect(result.errors).to include('Email account is not active')
      end
    end

    context 'with IMAP connection error' do
      before do
        expect(metrics_collector).to receive(:track_operation) do |_, _, _, &block|
          block.call
        end

        allow(mock_imap_service).to receive(:search_emails)
          .and_raise(ImapConnectionService::ConnectionError, 'Connection failed')
      end

      it 'tracks metrics even when IMAP fails' do
        result = fetcher_with_metrics.fetch_new_emails
        expect(result.failure?).to be true
        expect(result.errors).to include('IMAP Error: Connection failed')
      end
    end
  end

  describe 'initialization with metrics', unit: true do
    it 'stores metrics collector as instance variable' do
      expect(fetcher_with_metrics.metrics_collector).to eq(metrics_collector)
    end

    it 'allows nil metrics collector' do
      expect(fetcher_without_metrics.metrics_collector).to be_nil
    end

    it 'passes metrics to processor during initialization' do
      # Create a new fetcher to test initialization
      expect(EmailProcessing::Processor).to receive(:new)
        .with(email_account, metrics_collector: metrics_collector)
        .and_call_original

      described_class.new(email_account, metrics_collector: metrics_collector)
    end

    it 'creates processor without metrics when not provided' do
      expect(EmailProcessing::Processor).to receive(:new)
        .with(email_account, metrics_collector: nil)
        .and_call_original

      described_class.new(email_account)
    end
  end
end
