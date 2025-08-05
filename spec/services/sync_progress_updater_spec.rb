require 'rails_helper'

RSpec.describe SyncProgressUpdater do
  let(:sync_session) { create(:sync_session) }
  let(:email_account1) { create(:email_account) }
  let(:email_account2) { create(:email_account) }
  let(:service) { described_class.new(sync_session) }

  describe '#call' do
    context 'with sync session accounts' do
      let!(:account1) do
        create(:sync_session_account,
               sync_session: sync_session,
               email_account: email_account1,
               total_emails: 100,
               processed_emails: 50,
               detected_expenses: 10)
      end

      let!(:account2) do
        create(:sync_session_account,
               sync_session: sync_session,
               email_account: email_account2,
               total_emails: 200,
               processed_emails: 150,
               detected_expenses: 20)
      end

      it 'updates sync session with aggregated data' do
        # Mock the update to avoid transaction issues
        aggregated_data = double(total: 300, processed: 200, detected: 30)
        allow(sync_session.sync_session_accounts).to receive(:select).and_return([ aggregated_data ])

        expect(sync_session).to receive(:update!).with(
          total_emails: 300,
          processed_emails: 200,
          detected_expenses: 30
        ).and_return(true)

        service.call
      end

      it 'returns true on success' do
        # Mock the aggregated query and update
        aggregated_data = double(total: 300, processed: 200, detected: 30)
        allow(sync_session.sync_session_accounts).to receive(:select).and_return([ aggregated_data ])
        allow(sync_session).to receive(:update!).and_return(true)

        expect(service.call).to be true
      end
    end

    context 'with no sync session accounts' do
      it 'sets all counts to zero' do
        aggregated_data = double(total: 0, processed: 0, detected: 0)
        allow(sync_session.sync_session_accounts).to receive(:select).and_return([ aggregated_data ])

        expect(sync_session).to receive(:update!).with(
          total_emails: 0,
          processed_emails: 0,
          detected_expenses: 0
        ).and_return(true)

        service.call
      end
    end

    context 'with stale object error' do
      it 'handles the error and retries' do
        aggregated_data = double(total: 300, processed: 200, detected: 30)
        allow(sync_session.sync_session_accounts).to receive(:select).and_return([ aggregated_data ])

        # First call raises error, second succeeds
        call_count = 0
        allow(sync_session).to receive(:update!) do
          call_count += 1
          if call_count == 1
            raise ActiveRecord::StaleObjectError
          else
            true
          end
        end

        expect(sync_session).to receive(:reload)
        expect(service.call).to be true
      end
    end

    context 'with persistent stale object error' do
      it 'logs the error and returns false' do
        aggregated_data = double(total: 300, processed: 200, detected: 30)
        allow(sync_session.sync_session_accounts).to receive(:select).and_return([ aggregated_data ])

        # Always raise stale object error
        allow(sync_session).to receive(:update!).and_raise(ActiveRecord::StaleObjectError)
        allow(sync_session).to receive(:reload)

        expect(Rails.logger).to receive(:warn).with(/Persistent stale object error/)
        expect(service.call).to be false
      end
    end

    context 'with unexpected error' do
      before do
        allow(sync_session).to receive(:update!).and_raise(StandardError, "Unexpected error")
      end

      it 'logs the error and returns false' do
        expect(Rails.logger).to receive(:error).with(/Error updating sync progress/)
        expect(service.call).to be false
      end
    end
  end

  describe '#update_account_progress' do
    let!(:session_account) do
      create(:sync_session_account,
             sync_session: sync_session,
             email_account: email_account1,
             status: 'pending')
    end

    it 'updates the account progress and triggers sync update' do
      expect(session_account).to receive(:update!).with(
        processed_emails: 50,
        total_emails: 100,
        detected_expenses: 10,
        status: "processing"
      )

      allow(sync_session.sync_session_accounts).to receive(:find_by).and_return(session_account)
      expect(service).to receive(:call)

      service.update_account_progress(
        email_account1.id,
        processed: 50,
        total: 100,
        detected: 10
      )
    end

    it 'determines completed status when all emails processed' do
      expect(session_account).to receive(:update!).with(
        processed_emails: 100,
        total_emails: 100,
        detected_expenses: 20,
        status: "completed"
      )

      allow(sync_session.sync_session_accounts).to receive(:find_by).and_return(session_account)
      expect(service).to receive(:call)

      service.update_account_progress(
        email_account1.id,
        processed: 100,
        total: 100,
        detected: 20
      )
    end

    context 'when account not found' do
      it 'does nothing' do
        allow(sync_session.sync_session_accounts).to receive(:find_by).and_return(nil)

        expect {
          service.update_account_progress(99999, processed: 10, total: 20, detected: 5)
        }.not_to raise_error
      end
    end
  end
end
