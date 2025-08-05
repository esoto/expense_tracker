require 'rails_helper'

RSpec.describe SyncSessionMonitorJob, type: :job do
  include ActiveJob::TestHelper

  let(:sync_session) { create(:sync_session, :running) }
  let!(:account1) { create(:sync_session_account, sync_session: sync_session, status: 'processing') }
  let!(:account2) { create(:sync_session_account, sync_session: sync_session, status: 'processing') }

  describe '#perform' do
    context 'when sync session is not found' do
      it 'returns early without error' do
        expect { described_class.new.perform(999999) }.not_to raise_error
      end
    end

    context 'when sync session is already completed' do
      before { sync_session.update!(status: 'completed') }

      it 'returns early without processing' do
        expect(sync_session).not_to receive(:complete!)
        expect(described_class).not_to receive(:perform_later)

        described_class.new.perform(sync_session.id)
      end
    end

    context 'when all accounts are completed' do
      before do
        account1.update!(status: 'completed')
        account2.update!(status: 'completed')
      end

      it 'marks sync session as completed' do
        expect {
          described_class.new.perform(sync_session.id)
        }.to change { sync_session.reload.status }.from('running').to('completed')
      end

      it 'does not reschedule itself' do
        expect(described_class).not_to receive(:set).with(wait: 5.seconds)
        described_class.new.perform(sync_session.id)
      end
    end

    context 'when some accounts are still processing' do
      before do
        account1.update!(status: 'completed')
        # account2 remains processing
      end

      it 'does not mark sync session as completed' do
        described_class.new.perform(sync_session.id)
        expect(sync_session.reload).to be_running
      end

      it 'reschedules itself to check again in 5 seconds' do
        expect(described_class).to receive(:set).with(wait: 5.seconds).and_return(
          double(perform_later: true)
        )
        described_class.new.perform(sync_session.id)
      end
    end

    context 'when some accounts failed' do
      before do
        account1.update!(status: 'failed', last_error: 'Connection error')
        account2.update!(status: 'completed')
      end

      it 'marks sync session as completed (partial success)' do
        expect {
          described_class.new.perform(sync_session.id)
        }.to change { sync_session.reload.status }.from('running').to('completed')
      end
    end

    context 'when all accounts failed' do
      before do
        account1.update!(status: 'failed', last_error: 'Error 1')
        account2.update!(status: 'failed', last_error: 'Error 2')
      end

      it 'marks sync session as failed' do
        expect {
          described_class.new.perform(sync_session.id)
        }.to change { sync_session.reload.status }.from('running').to('failed')
      end

      it 'aggregates error messages' do
        described_class.new.perform(sync_session.id)
        expect(sync_session.reload.error_details).to include('Error 1', 'Error 2')
      end
    end

    context 'when sync session has no accounts' do
      before { sync_session.sync_session_accounts.destroy_all }

      it 'marks sync session as completed' do
        expect {
          described_class.new.perform(sync_session.id)
        }.to change { sync_session.reload.status }.from('running').to('completed')
      end
    end

    context 'with mixed statuses including waiting' do
      let!(:account3) { create(:sync_session_account, sync_session: sync_session, status: 'waiting') }

      it 'continues monitoring until all are done' do
        expect(described_class).to receive(:set).with(wait: 5.seconds).and_return(
          double(perform_later: true)
        )
        described_class.new.perform(sync_session.id)
      end
    end
  end

  describe 'job queue configuration' do
    it 'uses the default queue' do
      expect(described_class.new.queue_name).to eq('default')
    end
  end

  describe 'ActiveJob integration' do
    it 'can be enqueued with perform_later' do
      expect {
        described_class.perform_later(sync_session.id)
      }.to have_enqueued_job(described_class).with(sync_session.id)
    end

    it 'can be performed immediately' do
      expect {
        described_class.perform_now(sync_session.id)
      }.not_to raise_error
    end
  end
end
