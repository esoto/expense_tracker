require 'rails_helper'

RSpec.describe SyncProgressUpdater, type: :service do
  # Use build_stubbed to avoid database hits
  let(:sync_session) { build_stubbed(:sync_session, id: 1) }
  let(:email_account1) { build_stubbed(:email_account, id: 1) }
  let(:email_account2) { build_stubbed(:email_account, id: 2) }
  let(:service) { described_class.new(sync_session) }
  
  # Mock the batch collector to avoid thread creation overhead
  before do
    batch_collector = instance_double(ProgressBatchCollector)
    allow(ProgressBatchCollector).to receive(:new).and_return(batch_collector)
    allow(batch_collector).to receive(:add_progress_update)
    allow(batch_collector).to receive(:add_account_update)
    allow(batch_collector).to receive(:add_activity_update)
    allow(batch_collector).to receive(:add_critical_update)
    allow(batch_collector).to receive(:stop)
    allow(batch_collector).to receive(:stats).and_return({})
    
    # Mock sync_session methods
    allow(sync_session).to receive(:broadcast_dashboard_update)
  end

  describe '#call' do
    context 'with sync session accounts' do
      before do
        # Mock the pluck query result
        allow(sync_session).to receive(:sync_session_accounts).and_return(
          double(pluck: [[300, 200, 30]])
        )
      end

      it 'updates sync session with aggregated data' do
        expect(sync_session).to receive(:update!).with(
          total_emails: 300,
          processed_emails: 200,
          detected_expenses: 30
        ).and_return(true)

        service.call
      end

      it 'returns true on success' do
        allow(sync_session).to receive(:update!).and_return(true)

        expect(service.call).to be true
      end
    end

    context 'with no sync session accounts' do
      before do
        allow(sync_session).to receive(:sync_session_accounts).and_return(
          double(pluck: [[0, 0, 0]])
        )
      end
      
      it 'sets all counts to zero' do
        expect(sync_session).to receive(:update!).with(
          total_emails: 0,
          processed_emails: 0,
          detected_expenses: 0
        ).and_return(true)

        service.call
      end
    end

    context 'with stale object error' do
      before do
        allow(sync_session).to receive(:sync_session_accounts).and_return(
          double(pluck: [[300, 200, 30]])
        )
      end
      
      it 'handles the error and retries' do
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
      before do
        allow(sync_session).to receive(:sync_session_accounts).and_return(
          double(pluck: [[300, 200, 30]])
        )
      end
      
      it 'logs the error and returns false' do
        # Always raise stale object error
        allow(sync_session).to receive(:update!).and_raise(ActiveRecord::StaleObjectError)
        allow(sync_session).to receive(:reload)

        expect(Rails.logger).to receive(:warn).with(/Persistent stale object error/)
        expect(service.call).to be false
      end
    end

    context 'with unexpected error' do
      before do
        allow(sync_session).to receive(:sync_session_accounts).and_return(
          double(pluck: [[100, 50, 10]])
        )
        allow(sync_session).to receive(:update!).and_raise(StandardError, "Unexpected error")
      end

      it 'logs the error and returns false' do
        expect(Rails.logger).to receive(:error).with(/Error updating sync progress/)
        expect(service.call).to be false
      end
    end
  end

  describe '#update_account_progress' do
    let(:session_account) do
      build_stubbed(:sync_session_account,
                    sync_session: sync_session,
                    email_account: email_account1,
                    status: 'pending')
    end

    before do
      allow(sync_session).to receive(:sync_session_accounts).and_return(
        double(find_by: session_account, pluck: [[100, 50, 10]])
      )
    end

    it 'updates the account progress and triggers sync update' do
      expect(session_account).to receive(:update!).with(
        processed_emails: 50,
        total_emails: 100,
        detected_expenses: 10,
        status: "processing"
      ).and_return(true)

      # Mock the call method
      allow(sync_session).to receive(:update!).and_return(true)

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
      ).and_return(true)

      allow(sync_session).to receive(:update!).and_return(true)

      service.update_account_progress(
        email_account1.id,
        processed: 100,
        total: 100,
        detected: 20
      )
    end

    context 'when account not found' do
      it 'does nothing' do
        allow(sync_session).to receive(:sync_session_accounts).and_return(
          double(find_by: nil)
        )

        expect {
          service.update_account_progress(99999, processed: 10, total: 20, detected: 5)
        }.not_to raise_error
      end
    end
  end
end