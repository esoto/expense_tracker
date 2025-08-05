require 'rails_helper'

RSpec.describe SyncSession, type: :model do
  include ActiveSupport::Testing::TimeHelpers
  describe 'associations' do
    it { should have_many(:sync_session_accounts).dependent(:destroy) }
    it { should have_many(:email_accounts).through(:sync_session_accounts) }
  end

  describe 'validations' do
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[pending running completed failed cancelled]) }
  end

  describe 'scopes' do
    before do
      # Clear any existing sessions to avoid interference
      SyncSession.destroy_all
    end

    let!(:old_session) { create(:sync_session, created_at: 2.days.ago) }
    let!(:new_session) { create(:sync_session, created_at: 1.hour.ago) }
    let!(:pending_session) { create(:sync_session, status: 'pending', created_at: 30.minutes.ago) }
    let!(:running_session) { create(:sync_session, status: 'running', created_at: 20.minutes.ago) }
    let!(:completed_session) { create(:sync_session, status: 'completed', created_at: 10.minutes.ago) }
    let!(:failed_session) { create(:sync_session, status: 'failed', created_at: 5.minutes.ago) }

    describe '.recent' do
      it 'orders sessions by created_at descending' do
        # Get IDs in expected order
        expected_order = [ failed_session, completed_session, running_session, pending_session, new_session, old_session ]
        expect(SyncSession.recent.map(&:id)).to eq(expected_order.map(&:id))
      end
    end

    describe '.active' do
      it 'returns only pending and running sessions' do
        active_sessions = SyncSession.active
        expect(active_sessions.map(&:status).uniq.sort).to eq([ 'pending', 'running' ])
        expect(active_sessions).to include(pending_session, running_session)
        expect(active_sessions).not_to include(completed_session, failed_session)
      end
    end

    describe '.completed' do
      it 'returns only completed sessions' do
        expect(SyncSession.completed.to_a).to eq([ completed_session ])
      end
    end
  end

  describe '#progress_percentage' do
    subject(:sync_session) { build(:sync_session, total_emails: total, processed_emails: processed) }

    context 'when total_emails is zero' do
      let(:total) { 0 }
      let(:processed) { 0 }

      it 'returns 0' do
        expect(sync_session.progress_percentage).to eq(0)
      end
    end

    context 'when some emails are processed' do
      let(:total) { 100 }
      let(:processed) { 25 }

      it 'returns the correct percentage' do
        expect(sync_session.progress_percentage).to eq(25)
      end
    end

    context 'when all emails are processed' do
      let(:total) { 50 }
      let(:processed) { 50 }

      it 'returns 100' do
        expect(sync_session.progress_percentage).to eq(100)
      end
    end

    context 'with fractional percentages' do
      let(:total) { 3 }
      let(:processed) { 1 }

      it 'rounds to nearest integer' do
        expect(sync_session.progress_percentage).to eq(33)
      end
    end
  end

  describe '#estimated_time_remaining' do
    let(:sync_session) { create(:sync_session, status: status, started_at: started_at, total_emails: 100, processed_emails: processed) }
    let(:started_at) { 1.minute.ago }
    let(:processed) { 25 }
    let(:status) { 'running' }

    context 'when not running' do
      let(:status) { 'pending' }

      it 'returns nil' do
        expect(sync_session.estimated_time_remaining).to be_nil
      end
    end

    context 'when running but no emails processed' do
      let(:processed) { 0 }

      it 'returns nil' do
        expect(sync_session.estimated_time_remaining).to be_nil
      end
    end

    context 'when running with emails processed' do
      it 'calculates remaining time based on processing rate' do
        # 25 emails in 60 seconds = 0.417 emails/second
        # 75 remaining emails / 0.417 = ~180 seconds
        expect(sync_session.estimated_time_remaining).to be_within(5.seconds).of(180.seconds)
      end
    end

    context 'when all emails are processed' do
      let(:processed) { 100 }

      it 'returns zero seconds' do
        expect(sync_session.estimated_time_remaining.to_i).to eq(0)
      end
    end
  end

  describe 'status query methods' do
    subject(:sync_session) { build(:sync_session, status: status) }

    describe '#running?' do
      context 'when status is running' do
        let(:status) { 'running' }
        it { expect(sync_session).to be_running }
      end

      context 'when status is not running' do
        let(:status) { 'pending' }
        it { expect(sync_session).not_to be_running }
      end
    end

    describe '#completed?' do
      context 'when status is completed' do
        let(:status) { 'completed' }
        it { expect(sync_session).to be_completed }
      end

      context 'when status is not completed' do
        let(:status) { 'running' }
        it { expect(sync_session).not_to be_completed }
      end
    end

    describe '#failed?' do
      context 'when status is failed' do
        let(:status) { 'failed' }
        it { expect(sync_session).to be_failed }
      end

      context 'when status is not failed' do
        let(:status) { 'running' }
        it { expect(sync_session).not_to be_failed }
      end
    end

    describe '#cancelled?' do
      context 'when status is cancelled' do
        let(:status) { 'cancelled' }
        it { expect(sync_session).to be_cancelled }
      end

      context 'when status is not cancelled' do
        let(:status) { 'running' }
        it { expect(sync_session).not_to be_cancelled }
      end
    end

    describe '#pending?' do
      context 'when status is pending' do
        let(:status) { 'pending' }
        it { expect(sync_session).to be_pending }
      end

      context 'when status is not pending' do
        let(:status) { 'running' }
        it { expect(sync_session).not_to be_pending }
      end
    end
  end

  describe 'state transition methods' do
    let(:sync_session) { create(:sync_session, status: 'pending') }

    describe '#start!' do
      it 'changes status to running' do
        expect { sync_session.start! }.to change { sync_session.status }.from('pending').to('running')
      end

      it 'sets started_at timestamp' do
        travel_to Time.current do
          sync_session.start!
          expect(sync_session.started_at).to eq(Time.current)
        end
      end

      it 'persists changes' do
        sync_session.start!
        expect(sync_session.reload).to be_running
      end
    end

    describe '#complete!' do
      before { sync_session.start! }

      it 'changes status to completed' do
        expect { sync_session.complete! }.to change { sync_session.status }.from('running').to('completed')
      end

      it 'sets completed_at timestamp' do
        travel_to Time.current do
          sync_session.complete!
          expect(sync_session.completed_at).to eq(Time.current)
        end
      end

      it 'persists changes' do
        sync_session.complete!
        expect(sync_session.reload).to be_completed
      end
    end

    describe '#fail!' do
      before { sync_session.start! }

      it 'changes status to failed' do
        expect { sync_session.fail! }.to change { sync_session.status }.from('running').to('failed')
      end

      it 'sets completed_at timestamp' do
        travel_to Time.current do
          sync_session.fail!
          expect(sync_session.completed_at).to eq(Time.current)
        end
      end

      it 'stores error message when provided' do
        error_message = "Connection timeout"
        sync_session.fail!(error_message)
        expect(sync_session.error_details).to eq(error_message)
      end

      it 'allows nil error message' do
        sync_session.fail!
        expect(sync_session.error_details).to be_nil
      end

      it 'persists changes' do
        sync_session.fail!("Error")
        reloaded = sync_session.reload
        expect(reloaded).to be_failed
        expect(reloaded.error_details).to eq("Error")
      end
    end

    describe '#cancel!' do
      before { sync_session.start! }

      it 'changes status to cancelled' do
        expect { sync_session.cancel! }.to change { sync_session.status }.from('running').to('cancelled')
      end

      it 'sets completed_at timestamp' do
        travel_to Time.current do
          sync_session.cancel!
          expect(sync_session.completed_at).to eq(Time.current)
        end
      end

      it 'persists changes' do
        sync_session.cancel!
        expect(sync_session.reload).to be_cancelled
      end
    end
  end

  describe '#update_progress' do
    let(:sync_session) { create(:sync_session) }
    let!(:account1) { create(:sync_session_account, sync_session: sync_session, total_emails: 50, processed_emails: 25, detected_expenses: 10) }
    let!(:account2) { create(:sync_session_account, sync_session: sync_session, total_emails: 100, processed_emails: 75, detected_expenses: 20) }

    it 'sums total_emails from all session accounts' do
      sync_session.update_progress
      expect(sync_session.total_emails).to eq(150)
    end

    it 'sums processed_emails from all session accounts' do
      sync_session.update_progress
      expect(sync_session.processed_emails).to eq(100)
    end

    it 'sums detected_expenses from all session accounts' do
      sync_session.update_progress
      expect(sync_session.detected_expenses).to eq(30)
    end

    it 'persists the changes' do
      sync_session.update_progress
      reloaded = sync_session.reload
      expect(reloaded.total_emails).to eq(150)
      expect(reloaded.processed_emails).to eq(100)
      expect(reloaded.detected_expenses).to eq(30)
    end

    context 'with no session accounts' do
      let!(:empty_sync_session) { create(:sync_session) }

      it 'sets all counts to zero' do
        empty_sync_session.update_progress
        expect(empty_sync_session.total_emails).to eq(0)
        expect(empty_sync_session.processed_emails).to eq(0)
        expect(empty_sync_session.detected_expenses).to eq(0)
      end
    end
  end

  describe 'edge cases and error handling' do
    describe 'invalid status transitions' do
      let(:sync_session) { create(:sync_session, status: 'completed') }

      it 'allows starting a completed session (no validation prevents it)' do
        expect { sync_session.start! }.to change { sync_session.status }.to('running')
      end
    end

    describe 'concurrent updates' do
      let(:sync_session) { create(:sync_session, status: 'running') }

      it 'handles concurrent status updates gracefully' do
        # Simulate concurrent update
        another_instance = SyncSession.find(sync_session.id)

        sync_session.complete!

        # With optimistic locking, the stale instance will raise an error
        expect { another_instance.fail! }.to raise_error(ActiveRecord::StaleObjectError)

        # The first update wins
        expect(sync_session.reload).to be_completed
      end
    end
  end

  describe 'factory' do
    it 'has a valid factory' do
      expect(build(:sync_session)).to be_valid
    end

    it 'has a running factory trait' do
      session = build(:sync_session, :running)
      expect(session).to be_running
      expect(session.started_at).to be_present
    end

    it 'has a completed factory trait' do
      session = build(:sync_session, :completed)
      expect(session).to be_completed
      expect(session.started_at).to be_present
      expect(session.completed_at).to be_present
    end

    it 'has a failed factory trait' do
      session = build(:sync_session, :failed)
      expect(session).to be_failed
      expect(session.error_details).to be_present
    end
  end

  describe '#duration' do
    context 'when session has not started' do
      let(:sync_session) { build(:sync_session, started_at: nil) }

      it 'returns nil' do
        expect(sync_session.duration).to be_nil
      end
    end

    context 'when session is running' do
      let(:sync_session) { create(:sync_session, :running, started_at: 2.minutes.ago) }

      it 'calculates duration from start to current time' do
        expect(sync_session.duration).to be_within(1.second).of(120.seconds)
      end
    end

    context 'when session is completed' do
      let(:sync_session) do
        build(:sync_session, :completed,
              started_at: Time.current - 5.minutes,
              completed_at: Time.current - 2.minutes)
      end

      it 'calculates duration from start to completion' do
        expect(sync_session.duration).to be_within(1.second).of(180.seconds)
      end
    end
  end

  describe '#average_processing_time_per_email' do
    context 'with no processed emails' do
      let(:sync_session) { build(:sync_session, processed_emails: 0) }

      it 'returns nil' do
        expect(sync_session.average_processing_time_per_email).to be_nil
      end
    end

    context 'with processed emails and duration' do
      let(:sync_session) do
        build(:sync_session,
              started_at: Time.current - 10.minutes,
              completed_at: Time.current,
              processed_emails: 100)
      end

      it 'calculates average time per email' do
        expect(sync_session.average_processing_time_per_email).to be_within(0.1.seconds).of(6.seconds)
      end
    end
  end

  describe 'callbacks' do
    describe 'status change tracking' do
      let(:sync_session) { create(:sync_session, :running) }

      it 'sets completed_at when transitioning to completed' do
        expect {
          sync_session.update!(status: 'completed')
        }.to change { sync_session.completed_at }.from(nil)
      end

      it 'logs status changes' do
        allow(Rails.logger).to receive(:info)
        sync_session.update!(status: 'completed')
        expect(Rails.logger).to have_received(:info).with(/status changed from running to completed/)
      end

      it 'logs error details when failing' do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:error)

        sync_session.update!(status: 'failed', error_details: 'Test error')
        expect(Rails.logger).to have_received(:info).with(/SyncSession #{sync_session.id} status changed from running to failed/)
        expect(Rails.logger).to have_received(:error).with(/SyncSession #{sync_session.id} failed: Test error/)
      end
    end
  end

  describe 'additional scopes' do
    let!(:failed_session) { create(:sync_session, :failed) }
    let!(:completed_session) { create(:sync_session, :completed) }
    let!(:cancelled_session) { create(:sync_session, status: 'cancelled') }
    let!(:running_session) { create(:sync_session, :running) }

    describe '.failed' do
      it 'returns only failed sessions' do
        expect(SyncSession.failed).to eq([ failed_session ])
      end
    end

    describe '.finished' do
      it 'returns completed, failed, and cancelled sessions' do
        expect(SyncSession.finished).to match_array([ failed_session, completed_session, cancelled_session ])
      end
    end
  end
end
