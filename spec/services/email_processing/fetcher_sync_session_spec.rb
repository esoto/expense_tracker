require 'rails_helper'

RSpec.describe Services::EmailProcessing::Fetcher, 'sync session integration', integration: true do
  let(:email_account) { create(:email_account) }
  let(:sync_session) { create(:sync_session, :running) }
  let(:sync_session_account) { create(:sync_session_account, sync_session: sync_session, email_account: email_account, status: 'processing') }
  let(:mock_imap_service) { instance_double(ImapConnectionService) }
  let(:mock_email_processor) { instance_double(EmailProcessing::Processor) }

  let(:fetcher) do
    EmailProcessing::Fetcher.new(
      email_account,
      imap_service: mock_imap_service,
      email_processor: mock_email_processor,
      sync_session_account: sync_session_account
    )
  end

  before do
    allow(mock_imap_service).to receive(:errors).and_return([])
    allow(mock_email_processor).to receive(:errors).and_return([])
  end

  describe 'when sync_session_account is provided', integration: true do
    let(:message_ids) { [ 1, 2, 3, 4, 5 ] }

    before do
      allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
    end

    context 'with successful processing' do
      before do
        allow(mock_email_processor).to receive(:process_emails) do |ids, service, &block|
          # Simulate progress callbacks
          block&.call(1, 0) # First email processed, no expenses
          block&.call(2, 1) # Second email processed, 1 expense
          block&.call(3, 1) # Third email processed, still 1 expense
          block&.call(4, 2) # Fourth email processed, 2 expenses
          block&.call(5, 3) # Fifth email processed, 3 expenses

          { processed_count: 5, total_count: 5, detected_expenses_count: 3 }
        end
      end

      it 'updates sync session account with total emails before processing' do
        expect(sync_session_account).to receive(:update!).with(total_emails: 5).ordered
        expect(sync_session_account).to receive(:update_progress).at_least(:once).ordered

        fetcher.fetch_new_emails
      end

      it 'calls update_progress with callback data' do
        # Expect multiple progress updates
        # The last parameter is the incremental detected count between calls
        expect(sync_session_account).to receive(:update!).with(total_emails: 5)
        expect(sync_session_account).to receive(:update_progress).with(1, 5, 0)
        expect(sync_session_account).to receive(:update_progress).with(2, 5, 1)
        expect(sync_session_account).to receive(:update_progress).with(3, 5, 0)
        expect(sync_session_account).to receive(:update_progress).with(4, 5, 1)
        expect(sync_session_account).to receive(:update_progress).with(5, 5, 1)

        fetcher.fetch_new_emails
      end

      it 'processes emails with progress callback' do
        expect(mock_email_processor).to receive(:process_emails).with(message_ids, mock_imap_service) do |_ids, _service, &block|
          expect(block).not_to be_nil # Ensure callback is provided
          { processed_count: 5, total_count: 5, detected_expenses_count: 3 }
        end

        fetcher.fetch_new_emails
      end
    end

    context 'with partial processing' do
      before do
        allow(mock_email_processor).to receive(:process_emails) do |_ids, _service, &block|
          # Simulate only processing 3 out of 5 emails
          block&.call(1, 0)
          block&.call(2, 1)
          block&.call(3, 1)

          { processed_count: 3, total_count: 5, detected_expenses_count: 1 }
        end
      end

      it 'updates progress for processed emails only' do
        expect(sync_session_account).to receive(:update!).with(total_emails: 5)
        expect(sync_session_account).to receive(:update_progress).exactly(3).times

        result = fetcher.fetch_new_emails
        expect(result.processed_emails_count).to eq(3)
        expect(result.total_emails_found).to eq(5)
      end
    end

    context 'when update_progress fails' do
      let(:message_ids) { [ 1 ] }  # Only 1 message

      before do
        allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
        allow(mock_email_processor).to receive(:process_emails) do |_ids, _service, &block|
          block&.call(1, 0)
          { processed_count: 1, total_count: 1, detected_expenses_count: 0 }
        end

        allow(sync_session_account).to receive(:update_progress).and_raise(StandardError, "Update failed")
      end

      it 'continues processing despite update errors' do
        expect(sync_session_account).to receive(:update!).with(total_emails: 1)

        # Should not raise error
        result = fetcher.fetch_new_emails
        expect(result.success?).to be true
        expect(result.processed_emails_count).to eq(1)
      end
    end

    context 'with no emails found' do
      before do
        allow(mock_imap_service).to receive(:search_emails).and_return([])
        allow(mock_email_processor).to receive(:process_emails).and_return(
          { processed_count: 0, total_count: 0, detected_expenses_count: 0 }
        )
      end

      it 'updates sync session account with zero total' do
        expect(sync_session_account).to receive(:update!).with(total_emails: 0)

        result = fetcher.fetch_new_emails
        expect(result.total_emails_found).to eq(0)
      end
    end
  end

  describe 'when sync_session_account is nil', integration: true do
    let(:fetcher_without_sync) do
      EmailProcessing::Fetcher.new(
        email_account,
        imap_service: mock_imap_service,
        email_processor: mock_email_processor,
        sync_session_account: nil
      )
    end

    before do
      allow(mock_imap_service).to receive(:search_emails).and_return([ 1, 2 ])
      allow(mock_email_processor).to receive(:process_emails).and_return(
        { processed_count: 2, total_count: 2, detected_expenses_count: 1 }
      )
    end

    it 'processes emails without sync session updates' do
      expect(mock_email_processor).to receive(:process_emails).with([ 1, 2 ], mock_imap_service)

      result = fetcher_without_sync.fetch_new_emails
      expect(result.success?).to be true
      expect(result.processed_emails_count).to eq(2)
    end

    it 'does not provide progress callback to processor' do
      expect(mock_email_processor).to receive(:process_emails) do |_ids, _service, &block|
        expect(block).to be_nil # No callback should be provided
        { processed_count: 2, total_count: 2, detected_expenses_count: 1 }
      end

      fetcher_without_sync.fetch_new_emails
    end
  end
end
