require 'rails_helper'

RSpec.describe Services::EmailProcessing::Fetcher, 'progress tracking', type: :service, unit: true do
  let(:email_account) { create(:email_account, :bac) }
  let(:sync_session) { create(:sync_session, :running) }
  let(:sync_session_account) do
    create(:sync_session_account,
           sync_session: sync_session,
           email_account: email_account,
           status: 'processing',
           total_emails: 0,
           processed_emails: 0,
           detected_expenses: 0)
  end
  let(:mock_imap_service) { instance_double(Services::ImapConnectionService) }
  let(:mock_email_processor) { instance_double(EmailProcessing::Processor) }
  let(:metrics_collector) { instance_double(Services::SyncMetricsCollector) }

  let(:fetcher) do
    described_class.new(
      email_account,
      imap_service: mock_imap_service,
      email_processor: mock_email_processor,
      sync_session_account: sync_session_account,
      metrics_collector: metrics_collector
    )
  end

  before do
    allow(mock_imap_service).to receive(:errors).and_return([])
    allow(mock_email_processor).to receive(:errors).and_return([])
    allow(metrics_collector).to receive(:track_operation).and_yield

    # Mock broadcasting
    stub_const('SyncStatusChannel', double('SyncStatusChannel'))
    allow(SyncStatusChannel).to receive(:broadcast_activity)
  end

  describe 'incremental progress calculations', unit: true do
    context 'with linear expense detection' do
      let(:message_ids) { (1..10).to_a }
      let(:expenses) do
        (1..5).map do |i|
          instance_double(Expense, amount: i * 1000, merchant_name: "Store #{i}")
        end
      end

      before do
        allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
      end

      it 'calculates incremental detected expenses correctly' do
        progress_updates = []

        allow(sync_session_account).to receive(:update!).with(total_emails: 10)
        allow(sync_session_account).to receive(:update_progress) do |processed, total, incremental|
          progress_updates << { processed: processed, total: total, incremental: incremental }
        end

        allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
          # Simulate gradual expense detection
          block&.call(1, 0, nil)           # Email 1: no expenses (0 total)
          block&.call(2, 1, expenses[0])   # Email 2: 1 expense (1 total)
          block&.call(3, 1, nil)           # Email 3: no new expenses (1 total)
          block&.call(4, 2, expenses[1])   # Email 4: 1 expense (2 total)
          block&.call(5, 2, nil)           # Email 5: no new expenses (2 total)
          block&.call(6, 3, expenses[2])   # Email 6: 1 expense (3 total)
          block&.call(7, 3, nil)           # Email 7: no new expenses (3 total)
          block&.call(8, 4, expenses[3])   # Email 8: 1 expense (4 total)
          block&.call(9, 4, nil)           # Email 9: no new expenses (4 total)
          block&.call(10, 5, expenses[4])  # Email 10: 1 expense (5 total)

          { processed_count: 10, total_count: 10, detected_expenses_count: 5 }
        end

        fetcher.fetch_new_emails

        # Verify incremental calculations
        expect(progress_updates).to eq([
          { processed: 1, total: 10, incremental: 0 },   # 0 - 0 = 0
          { processed: 2, total: 10, incremental: 1 },   # 1 - 0 = 1
          { processed: 3, total: 10, incremental: 0 },   # 1 - 1 = 0
          { processed: 4, total: 10, incremental: 1 },   # 2 - 1 = 1
          { processed: 5, total: 10, incremental: 0 },   # 2 - 2 = 0
          { processed: 6, total: 10, incremental: 1 },   # 3 - 2 = 1
          { processed: 7, total: 10, incremental: 0 },   # 3 - 3 = 0
          { processed: 8, total: 10, incremental: 1 },   # 4 - 3 = 1
          { processed: 9, total: 10, incremental: 0 },   # 4 - 4 = 0
          { processed: 10, total: 10, incremental: 1 }   # 5 - 4 = 1
        ])
      end
    end

    context 'with batch expense detection' do
      let(:message_ids) { [ 1, 2, 3 ] }
      let(:expense1) { instance_double(Expense, amount: 1000, merchant_name: 'Store A') }
      let(:expense2) { instance_double(Expense, amount: 2000, merchant_name: 'Store B') }

      before do
        allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
        allow(sync_session_account).to receive(:update!).with(total_emails: 3)
      end

      it 'handles multiple expenses detected in single email' do
        progress_updates = []

        allow(sync_session_account).to receive(:update_progress) do |processed, total, incremental|
          progress_updates << incremental
        end

        allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
          # Email contains multiple expenses (jump from 0 to 3)
          block&.call(1, 3, expense2)  # 3 expenses detected in first email
          block&.call(2, 3, nil)       # No new expenses
          block&.call(3, 5, expense1)  # 2 more expenses in third email

          { processed_count: 3, total_count: 3, detected_expenses_count: 5 }
        end

        fetcher.fetch_new_emails

        # Verify incremental calculations for batch detection
        expect(progress_updates).to eq([
          3,  # First email: 3 - 0 = 3 expenses
          0,  # Second email: 3 - 3 = 0 new expenses
          2   # Third email: 5 - 3 = 2 new expenses
        ])
      end
    end

    context 'with no expenses detected' do
      let(:message_ids) { [ 1, 2, 3, 4, 5 ] }

      before do
        allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
        allow(sync_session_account).to receive(:update!).with(total_emails: 5)
      end

      it 'reports zero incremental for all emails' do
        progress_updates = []

        allow(sync_session_account).to receive(:update_progress) do |processed, total, incremental|
          progress_updates << incremental
        end

        allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
          # No expenses detected in any email
          (1..5).each { |i| block&.call(i, 0, nil) }

          { processed_count: 5, total_count: 5, detected_expenses_count: 0 }
        end

        fetcher.fetch_new_emails

        expect(progress_updates).to eq([ 0, 0, 0, 0, 0 ])
        expect(SyncStatusChannel).not_to have_received(:broadcast_activity)
      end
    end
  end

  describe 'last_detected tracking', unit: true do
    let(:message_ids) { [ 1, 2, 3 ] }
    let(:expense) { instance_double(Expense, amount: 1500, merchant_name: 'Test') }

    before do
      allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
      allow(sync_session_account).to receive(:update!).with(total_emails: 3)
      allow(sync_session_account).to receive(:update_progress)
    end

    it 'maintains last_detected state across callbacks' do
      last_detected_values = []

      allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
        # Capture the last_detected variable state through broadcasts
        allow(SyncStatusChannel).to receive(:broadcast_activity) do |session, type, message|
          # Extract the amount from the message to verify state
          if message =~ /₡(\d+)/
            last_detected_values << $1.to_i
          end
        end

        block&.call(1, 2, expense)  # Jump to 2 expenses
        block&.call(2, 2, nil)      # Stay at 2
        block&.call(3, 4, expense)  # Jump to 4 expenses

        { processed_count: 3, total_count: 3, detected_expenses_count: 4 }
      end

      fetcher.fetch_new_emails

      # Should broadcast twice (when incrementals are > 0)
      expect(SyncStatusChannel).to have_received(:broadcast_activity).twice
    end

    it 'resets last_detected for each fetch_new_emails call' do
      allow(sync_session_account).to receive(:update_progress)

      # First call
      allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
        block&.call(1, 3, expense)
        { processed_count: 1, total_count: 1, detected_expenses_count: 3 }
      end

      fetcher.fetch_new_emails

      # Second call should start fresh with last_detected = 0
      allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
        block&.call(1, 2, expense)  # If last_detected wasn't reset, incremental would be -1
        { processed_count: 1, total_count: 1, detected_expenses_count: 2 }
      end

      expect(sync_session_account).to receive(:update_progress).with(1, 3, 2)  # Should be 2, not -1
      fetcher.fetch_new_emails
    end
  end

  describe 'progress callback edge cases', unit: true do
    context 'when processor does not provide last_expense' do
      let(:message_ids) { [ 1 ] }

      before do
        allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
        allow(sync_session_account).to receive(:update!).with(total_emails: 1)
        allow(sync_session_account).to receive(:update_progress)
      end

      it 'handles nil last_expense gracefully' do
        allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
          # Provide detected count but nil expense
          block&.call(1, 1, nil)
          { processed_count: 1, total_count: 1, detected_expenses_count: 1 }
        end

        # Should not broadcast when last_expense is nil even with incremental > 0
        expect(SyncStatusChannel).not_to receive(:broadcast_activity)

        fetcher.fetch_new_emails
      end
    end

    context 'when detected count decreases (data inconsistency)' do
      let(:message_ids) { [ 1, 2 ] }
      let(:expense) { instance_double(Expense, amount: 1000, merchant_name: 'Store') }

      before do
        allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
        allow(sync_session_account).to receive(:update!).with(total_emails: 2)
      end

      it 'handles negative incremental gracefully' do
        progress_updates = []

        allow(sync_session_account).to receive(:update_progress) do |processed, total, incremental|
          progress_updates << incremental
        end

        allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
          # Simulate decreasing count (shouldn't happen but handle it)
          block&.call(1, 5, expense)  # 5 expenses
          block&.call(2, 3, nil)      # Down to 3 expenses (weird but possible)

          { processed_count: 2, total_count: 2, detected_expenses_count: 3 }
        end

        fetcher.fetch_new_emails

        # Should calculate negative incremental correctly
        expect(progress_updates).to eq([
          5,   # 5 - 0 = 5
          -2   # 3 - 5 = -2 (negative incremental)
        ])

        # Should only broadcast for positive incremental
        expect(SyncStatusChannel).to have_received(:broadcast_activity).once
      end
    end

    context 'with very large numbers' do
      let(:message_ids) { (1..1000).to_a }

      before do
        allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
        allow(sync_session_account).to receive(:update!).with(total_emails: 1000)
      end

      it 'handles large scale processing correctly' do
        allow(sync_session_account).to receive(:update_progress)

        allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
          # Simulate processing 1000 emails with 250 expenses
          current_expenses = 0
          ids.each_with_index do |id, index|
            # Every 4th email has an expense
            if (index + 1) % 4 == 0
              current_expenses += 1
              expense = instance_double(Expense, amount: 100 * (index + 1), merchant_name: "Store #{index}")
              block&.call(index + 1, current_expenses, expense)
            else
              block&.call(index + 1, current_expenses, nil)
            end
          end

          { processed_count: 1000, total_count: 1000, detected_expenses_count: 250 }
        end

        result = fetcher.fetch_new_emails
        expect(result.success?).to be true
        expect(result.processed_emails_count).to eq(1000)
        expect(result.total_emails_found).to eq(1000)

        # Should have broadcasted 250 times (once per expense)
        expect(SyncStatusChannel).to have_received(:broadcast_activity).exactly(250).times
      end
    end
  end

  describe 'progress updates without sync session', unit: true do
    let(:fetcher_no_sync) do
      described_class.new(
        email_account,
        imap_service: mock_imap_service,
        email_processor: mock_email_processor,
        sync_session_account: nil,
        metrics_collector: metrics_collector
      )
    end

    let(:message_ids) { [ 1, 2, 3 ] }

    before do
      allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
    end

    it 'processes without progress callbacks' do
      expect(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
        # Block should be nil when no sync_session_account
        expect(block).to be_nil
        { processed_count: 3, total_count: 3, detected_expenses_count: 1 }
      end

      result = fetcher_no_sync.fetch_new_emails
      expect(result.success?).to be true
      expect(result.processed_emails_count).to eq(3)
    end

    it 'does not attempt any progress updates' do
      allow(mock_email_processor).to receive(:process_emails)
        .and_return({ processed_count: 3, total_count: 3 })

      # Should not call any sync session methods
      expect(sync_session_account).not_to receive(:update!)
      expect(sync_session_account).not_to receive(:update_progress)
      expect(SyncStatusChannel).not_to receive(:broadcast_activity)

      fetcher_no_sync.fetch_new_emails
    end
  end

  describe 'progress calculation precision', unit: true do
    let(:message_ids) { [ 1 ] }
    let(:expense) { instance_double(Expense, amount: 1234.56, merchant_name: 'Test') }

    before do
      allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
      allow(sync_session_account).to receive(:update!).with(total_emails: 1)
    end

    it 'maintains integer precision for incremental calculations' do
      incremental_value = nil

      allow(sync_session_account).to receive(:update_progress) do |processed, total, incremental|
        incremental_value = incremental
      end

      allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
        # Pass integer detected count
        block&.call(1, 1, expense)
        { processed_count: 1, total_count: 1, detected_expenses_count: 1 }
      end

      fetcher.fetch_new_emails

      expect(incremental_value).to be_a(Integer)
      expect(incremental_value).to eq(1)
    end
  end
end
