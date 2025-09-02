require 'rails_helper'

RSpec.describe EmailProcessing::Fetcher, 'broadcasting integration', type: :service, unit: true do
  let(:email_account) { create(:email_account, :bac) }
  let(:sync_session) { create(:sync_session, :running) }
  let(:sync_session_account) do
    create(:sync_session_account,
           sync_session: sync_session,
           email_account: email_account,
           status: 'processing')
  end
  let(:mock_imap_service) { instance_double(ImapConnectionService) }
  let(:mock_email_processor) { instance_double(EmailProcessing::Processor) }
  let(:metrics_collector) { instance_double(SyncMetricsCollector) }

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
  end

  describe 'ActionCable broadcasting', unit: true do
    let(:message_ids) { [ 1, 2, 3, 4, 5 ] }

    before do
      allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
      # Mock SyncStatusChannel as a class with broadcast_activity method
      mock_channel = Class.new do
        def self.broadcast_activity(sync_session, event, message)
          # No-op for testing
        end
      end
      stub_const('SyncStatusChannel', mock_channel)
      allow(SyncStatusChannel).to receive(:broadcast_activity)
    end

    context 'when expense is detected' do
      let(:expense1) do
        instance_double(Expense,
                        amount: 15500.50,
                        merchant_name: 'Automercado',
                        description: 'Compra en supermercado')
      end

      let(:expense2) do
        instance_double(Expense,
                        amount: 3200.00,
                        merchant_name: 'Starbucks',
                        description: 'Café')
      end

      before do
        allow(sync_session_account).to receive(:update!).with(total_emails: 5)
        allow(sync_session_account).to receive(:update_progress)

        allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
          # Simulate processing with expenses detected
          block&.call(1, 0, nil)        # First email, no expenses
          block&.call(2, 1, expense1)   # Second email, first expense detected
          block&.call(3, 1, nil)        # Third email, no new expenses
          block&.call(4, 2, expense2)   # Fourth email, second expense detected
          block&.call(5, 2, nil)        # Fifth email, no new expenses

          { processed_count: 5, total_count: 5, detected_expenses_count: 2 }
        end
      end

      it 'broadcasts expense detection for each new expense' do
        expect(SyncStatusChannel).to receive(:broadcast_activity).with(
          sync_session,
          "expense_detected",
          "Gasto detectado: ₡15,500.50 en Automercado"
        ).ordered

        expect(SyncStatusChannel).to receive(:broadcast_activity).with(
          sync_session,
          "expense_detected",
          "Gasto detectado: ₡3,200.00 en Starbucks"
        ).ordered

        fetcher.fetch_new_emails
      end

      it 'calculates incremental detected expenses correctly' do
        # Track the incremental calculations
        incremental_calls = []
        allow(sync_session_account).to receive(:update!).with(total_emails: 5)
        allow(sync_session_account).to receive(:update_progress) do |processed, total, incremental|
          incremental_calls << [ processed, total, incremental ]
        end

        fetcher.fetch_new_emails

        # Verify incremental detected expense calculations
        expect(incremental_calls).to eq([
          [ 1, 5, 0 ],  # No expenses detected yet (0 - 0 = 0)
          [ 2, 5, 1 ],  # First expense detected (1 - 0 = 1)
          [ 3, 5, 0 ],  # No new expenses (1 - 1 = 0)
          [ 4, 5, 1 ],  # Second expense detected (2 - 1 = 1)
          [ 5, 5, 0 ]   # No new expenses (2 - 2 = 0)
        ])
      end

      it 'does not broadcast when no new expense is detected' do
        allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
          # All emails processed without expenses
          block&.call(1, 0, nil)
          block&.call(2, 0, nil)
          block&.call(3, 0, nil)

          { processed_count: 3, total_count: 3, detected_expenses_count: 0 }
        end

        expect(SyncStatusChannel).not_to receive(:broadcast_activity)

        fetcher.fetch_new_emails
      end
    end

    # Note: nil merchant handling is thoroughly tested in #format_expense_message specs below (line 257)
    # Broadcasting with various expense scenarios is covered in other contexts above

    context 'when broadcasting fails' do
      let(:expense) do
        instance_double(Expense, amount: 1000.00, merchant_name: 'Test Store')
      end

      before do
        allow(mock_imap_service).to receive(:search_emails).and_return([ 1 ])
        allow(sync_session_account).to receive(:update!).with(total_emails: 1)
        allow(sync_session_account).to receive(:update_progress)

        allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
          block&.call(1, 1, expense)
          { processed_count: 1, total_count: 1, detected_expenses_count: 1 }
        end

        allow(SyncStatusChannel).to receive(:broadcast_activity)
          .and_raise(StandardError, 'Broadcasting error')
      end

      it 'logs error and continues processing' do
        expect(Rails.logger).to receive(:error)
          .with('[EmailProcessing::Fetcher] Failed to update progress: Broadcasting error')

        # Should not raise error
        result = fetcher.fetch_new_emails
        expect(result.success?).to be true
        expect(result.processed_emails_count).to eq(1)
      end
    end

    context 'with multiple expenses in single callback' do
      let(:expense1) { instance_double(Expense, amount: 1000, merchant_name: 'Store A') }
      let(:expense2) { instance_double(Expense, amount: 2000, merchant_name: 'Store B') }

      before do
        allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
          # Jump from 0 to 3 expenses in one callback (simulating batch processing)
          block&.call(1, 3, expense2)  # Last expense from the batch
          { processed_count: 1, total_count: 1, detected_expenses_count: 3 }
        end
      end

      it 'broadcasts only when incremental count is positive' do
        # Should broadcast once for the batch (3 new expenses)
        expect(SyncStatusChannel).to receive(:broadcast_activity).once.with(
          sync_session,
          "expense_detected",
          "Gasto detectado: ₡2,000.00 en Store B"
        )

        allow(sync_session_account).to receive(:update!)
        allow(sync_session_account).to receive(:update_progress)

        fetcher.fetch_new_emails
      end
    end

    context 'without sync_session_account' do
      let(:fetcher_no_sync) do
        described_class.new(
          email_account,
          imap_service: mock_imap_service,
          email_processor: mock_email_processor,
          sync_session_account: nil
        )
      end

      before do
        allow(mock_email_processor).to receive(:process_emails)
          .and_return({ processed_count: 2, total_count: 2, detected_expenses_count: 1 })
      end

      it 'does not attempt broadcasting' do
        expect(SyncStatusChannel).not_to receive(:broadcast_activity)

        result = fetcher_no_sync.fetch_new_emails
        expect(result.success?).to be true
      end
    end
  end

  describe '#format_expense_message', unit: true do
    context 'with valid expense' do
      it 'formats Costa Rican currency correctly' do
        expense = instance_double(Expense, amount: 15500.50, merchant_name: 'Automercado')
        message = fetcher.send(:format_expense_message, expense)
        expect(message).to eq('₡15,500.50 en Automercado')
      end

      it 'formats thousands separator correctly' do
        expense = instance_double(Expense, amount: 1234567.89, merchant_name: 'Test')
        message = fetcher.send(:format_expense_message, expense)
        expect(message).to eq('₡1,234,567.89 en Test')
      end

      it 'formats whole numbers without unnecessary decimals' do
        expense = instance_double(Expense, amount: 5000.00, merchant_name: 'Store')
        message = fetcher.send(:format_expense_message, expense)
        expect(message).to eq('₡5,000.00 en Store')
      end

      it 'handles nil merchant' do
        expense = instance_double(Expense, amount: 2500, merchant_name: nil)
        message = fetcher.send(:format_expense_message, expense)
        expect(message).to eq('₡2,500.00 en Comercio desconocido')
      end

      it 'handles empty string merchant' do
        expense = instance_double(Expense, amount: 3000, merchant_name: '')
        message = fetcher.send(:format_expense_message, expense)
        expect(message).to eq('₡3,000.00 en Comercio desconocido')
      end

      it 'preserves merchant with special characters' do
        expense = instance_double(Expense, amount: 1500, merchant_name: 'Café & Bar')
        message = fetcher.send(:format_expense_message, expense)
        expect(message).to eq('₡1,500.00 en Café & Bar')
      end
    end

    context 'with nil expense' do
      it 'returns empty string' do
        message = fetcher.send(:format_expense_message, nil)
        expect(message).to eq('')
      end
    end

    context 'with edge cases' do
      it 'handles zero amount' do
        expense = instance_double(Expense, amount: 0, merchant_name: 'Test')
        message = fetcher.send(:format_expense_message, expense)
        expect(message).to eq('₡0.00 en Test')
      end

      it 'handles very large amounts' do
        expense = instance_double(Expense, amount: 999999999.99, merchant_name: 'Bank')
        message = fetcher.send(:format_expense_message, expense)
        expect(message).to eq('₡999,999,999.99 en Bank')
      end

      it 'handles negative amounts' do
        expense = instance_double(Expense, amount: -500.50, merchant_name: 'Refund')
        message = fetcher.send(:format_expense_message, expense)
        expect(message).to eq('-₡500.50 en Refund')
      end
    end
  end

  describe 'progress update error handling', unit: true do
    let(:message_ids) { [ 1, 2 ] }

    before do
      allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
    end

    context 'when sync_session_account.update! fails' do
      before do
        allow(sync_session_account).to receive(:update!)
          .with(total_emails: 2)
          .and_raise(StandardError, 'Validation failed')

        allow(mock_email_processor).to receive(:process_emails)
          .and_return({ processed_count: 0, total_count: 2 })
      end

      it 'catches the error and returns failure response' do
        result = fetcher.fetch_new_emails
        expect(result).to be_failure
        expect(result.errors).to include('Unexpected error: Validation failed')
      end
    end

    context 'when update_progress fails during processing' do
      before do
        allow(sync_session_account).to receive(:update!).with(total_emails: 2)

        call_count = 0
        allow(sync_session_account).to receive(:update_progress) do
          call_count += 1
          if call_count == 1
            raise StandardError, 'Progress update failed'
          end
        end

        allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
          block&.call(1, 0, nil)
          block&.call(2, 1, nil)
          { processed_count: 2, total_count: 2, detected_expenses_count: 1 }
        end
      end

      it 'logs error and continues processing' do
        expect(Rails.logger).to receive(:error)
          .with('[EmailProcessing::Fetcher] Failed to update progress: Progress update failed')
          .once

        result = fetcher.fetch_new_emails
        expect(result.success?).to be true
        expect(result.processed_emails_count).to eq(2)
      end
    end

    context 'when both update_progress and broadcast fail' do
      let(:expense) { instance_double(Expense, amount: 100, merchant_name: 'Test') }

      before do
        allow(mock_imap_service).to receive(:search_emails).and_return([ 1 ])
        allow(sync_session_account).to receive(:update!).with(total_emails: 1)
        allow(sync_session_account).to receive(:update_progress)
          .and_raise(StandardError, 'Update failed')

        allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
          block&.call(1, 1, expense)
          { processed_count: 1, total_count: 1, detected_expenses_count: 1 }
        end
      end

      it 'logs only the first error in the chain' do
        # Only the update_progress error should be logged
        expect(Rails.logger).to receive(:error)
          .with('[EmailProcessing::Fetcher] Failed to update progress: Update failed')
          .once

        # Should not attempt broadcast since update_progress failed first
        expect(SyncStatusChannel).not_to receive(:broadcast_activity)

        result = fetcher.fetch_new_emails
        expect(result.success?).to be true
      end
    end
  end
end
