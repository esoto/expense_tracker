require 'rails_helper'

RSpec.describe SyncSession, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  describe 'associations' do
    # Performance: build_stubbed avoids DB for association reflection
    subject { build_stubbed(:sync_session) }

    it { should have_many(:sync_session_accounts).dependent(:destroy) }
    it { should have_many(:email_accounts).through(:sync_session_accounts) }
  end

  describe 'validations' do
    subject { build(:sync_session) }

    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[pending running completed failed cancelled]) }
  end

  describe 'scopes' do
    # Performance: removed destroy_all (transactional fixtures handle cleanup).
    # Converted let! to standard let! here because scope tests require records to exist —
    # but using a shared sync_session avoids the factory chain creating extra records.
    let!(:old_session)       { create(:sync_session, created_at: 2.days.ago) }
    let!(:new_session)       { create(:sync_session, created_at: 1.hour.ago) }
    let!(:pending_session)   { create(:sync_session, status: 'pending',   created_at: 30.minutes.ago) }
    let!(:running_session)   { create(:sync_session, status: 'running',   created_at: 20.minutes.ago) }
    let!(:completed_session) { create(:sync_session, status: 'completed', created_at: 10.minutes.ago) }
    let!(:failed_session)    { create(:sync_session, status: 'failed',    created_at: 5.minutes.ago) }

    describe '.recent' do
      it 'orders sessions by created_at descending' do
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
    # Performance: build avoids DB for pure calculation tests
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
    # Performance: share sync_session via lazy let; only tests that need the DB will trigger it
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
    # Performance: build avoids DB for predicate method tests
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
    # Performance: single lazy let; only created when used
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
    # Performance: share sync_session; let! only for the accounts that scope tests need
    let(:sync_session) { create(:sync_session) }
    let!(:account1) { create(:sync_session_account, sync_session: sync_session, total_emails: 50, processed_emails: 25, detected_expenses: 10) }
    let!(:account2) { create(:sync_session_account, sync_session: sync_session, total_emails: 100, processed_emails: 75, detected_expenses: 20) }

    it 'delegates to Services::SyncProgressUpdater service' do
      updater = instance_double(Services::SyncProgressUpdater)
      expect(Services::SyncProgressUpdater).to receive(:new).with(sync_session).and_return(updater)
      expect(updater).to receive(:call).and_return(true)

      sync_session.update_progress
    end

    it 'returns the result from the service' do
      allow_any_instance_of(Services::SyncProgressUpdater).to receive(:call).and_return(true)
      expect(sync_session.update_progress).to eq(true)
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
        another_instance = SyncSession.find(sync_session.id)

        sync_session.complete!

        expect { another_instance.fail! }.to raise_error(ActiveRecord::StaleObjectError)

        expect(sync_session.reload).to be_completed
      end
    end
  end

  describe 'factory' do
    # Performance: build for trait verification — no DB needed
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
      # Performance: build for nil-check
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
      # Performance: build for deterministic timestamp math
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
      # Performance: build for nil-check
      let(:sync_session) { build(:sync_session, processed_emails: 0) }

      it 'returns nil' do
        expect(sync_session.average_processing_time_per_email).to be_nil
      end
    end

    context 'with processed emails and duration' do
      # Performance: build for deterministic calculation
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

      it 'does not log info for status changes' do
        allow(Rails.logger).to receive(:info)
        sync_session.update!(status: 'completed')
        expect(Rails.logger).not_to have_received(:info).with(/status changed from running to completed/)
      end

      it 'logs error details when failing' do
        allow(Rails.logger).to receive(:error)

        sync_session.update!(status: 'failed', error_details: 'Test error')
        expect(Rails.logger).to have_received(:error).with(/SyncSession #{sync_session.id} failed: Test error/)
      end
    end
  end

  describe '#broadcast_status_badge', :unit do
    let(:sync_session) { create(:sync_session, :running) }

    before { SyncSession.enable_broadcasting! }
    after { SyncSession.disable_broadcasting! }

    it 'broadcasts replace to sync_sessions_index when status changes' do
      expect(sync_session).to receive(:broadcast_replace_to).with(
        "sync_sessions_index",
        target: "status_sync_session_#{sync_session.id}",
        partial: "sync_sessions/session_status_badge",
        locals: { session: sync_session }
      )
      # Also expect the session-specific broadcast
      allow(sync_session).to receive(:broadcast_replace_to).with(
        sync_session,
        target: "status_sync_session_#{sync_session.id}",
        partial: "sync_sessions/session_status_badge",
        locals: { session: sync_session }
      )
      # Allow the existing dashboard broadcast
      allow(sync_session).to receive(:broadcast_update_to).with(
        "dashboard_sync_updates",
        hash_including(target: "sync_status_widget")
      )

      sync_session.update!(status: "completed", completed_at: Time.current)
    end

    it 'broadcasts replace to session-specific stream when status changes' do
      expect(sync_session).to receive(:broadcast_replace_to).with(
        sync_session,
        target: "status_sync_session_#{sync_session.id}",
        partial: "sync_sessions/session_status_badge",
        locals: { session: sync_session }
      )
      # Allow other broadcasts
      allow(sync_session).to receive(:broadcast_replace_to).with(
        "sync_sessions_index",
        hash_including(target: "status_sync_session_#{sync_session.id}")
      )
      allow(sync_session).to receive(:broadcast_update_to).with(
        "dashboard_sync_updates",
        hash_including(target: "sync_status_widget")
      )

      sync_session.update!(status: "completed", completed_at: Time.current)
    end

    it 'does not broadcast when status has not changed' do
      expect(sync_session).not_to receive(:broadcast_replace_to).with(
        "sync_sessions_index",
        hash_including(target: "status_sync_session_#{sync_session.id}")
      )
      # Allow other broadcasts (dashboard update fires on any update)
      allow(sync_session).to receive(:broadcast_update_to).with(
        "dashboard_sync_updates",
        hash_including(target: "sync_status_widget")
      )

      sync_session.update!(processed_emails: 10)
    end
  end

  describe 'additional scopes' do
    # Performance: let! required — scope results depend on these records existing
    let!(:failed_session)    { create(:sync_session, :failed) }
    let!(:completed_session) { create(:sync_session, :completed) }
    let!(:cancelled_session) { create(:sync_session, status: 'cancelled') }
    let!(:running_session)   { create(:sync_session, :running) }

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

  describe '#add_job_id' do
    # Performance: share single sync_session across all add_job_id tests
    let(:sync_session) { create(:sync_session) }

    context 'when job_id is provided' do
      it 'initializes job_ids array if empty' do
        expect(sync_session.job_ids).to eq([])
        sync_session.add_job_id('job_123')
        expect(sync_session.reload.job_ids).to eq([ 'job_123' ])
      end

      it 'appends to existing job_ids array' do
        sync_session.update!(job_ids: [ 'existing_job' ])
        sync_session.add_job_id('job_456')
        expect(sync_session.reload.job_ids).to eq([ 'existing_job', 'job_456' ])
      end

      it 'converts job_id to string' do
        sync_session.add_job_id(789)
        expect(sync_session.reload.job_ids).to eq([ '789' ])
      end

      it 'persists the changes to the database' do
        sync_session.add_job_id('persistent_job')
        reloaded_session = SyncSession.find(sync_session.id)
        expect(reloaded_session.job_ids).to eq([ 'persistent_job' ])
      end

      it 'handles multiple job_ids correctly' do
        sync_session.add_job_id('job_1')
        sync_session.add_job_id('job_2')
        sync_session.add_job_id('job_3')
        expect(sync_session.reload.job_ids).to eq([ 'job_1', 'job_2', 'job_3' ])
      end
    end

    context 'when job_id is nil' do
      it 'does not modify job_ids array' do
        original_job_ids = sync_session.job_ids
        sync_session.add_job_id(nil)
        expect(sync_session.reload.job_ids).to eq(original_job_ids)
      end

      it 'does not save the record when job_id is nil' do
        original_updated_at = sync_session.updated_at
        sync_session.add_job_id(nil)
        expect(sync_session.reload.updated_at).to eq(original_updated_at)
      end
    end

    context 'when job_id is empty string' do
      it 'does not modify job_ids array' do
        original_job_ids = sync_session.job_ids
        sync_session.add_job_id('')
        expect(sync_session.reload.job_ids).to eq(original_job_ids)
      end
    end

    context 'error handling' do
      it 'raises error if update_column fails' do
        allow(sync_session).to receive(:update_column).and_raise(ActiveRecord::StatementInvalid)
        expect { sync_session.add_job_id('job_123') }.to raise_error(ActiveRecord::StatementInvalid)
      end
    end
  end

  describe '#cancel_all_jobs' do
    # Performance: share sync_session across cancel_all_jobs tests
    let(:sync_session) { create(:sync_session) }

    before do
      allow(SolidQueue::Job).to receive(:find_by).and_return(nil)
    end

    context 'when job_ids is blank' do
      it 'returns early without processing main jobs when empty' do
        sync_session.update!(job_ids: [])

        sync_session.cancel_all_jobs

        expect(true).to be true
      end

      it 'returns early when job_ids is blank and does not process account jobs' do
        email_account = create(:email_account)
        sync_session_account = create(:sync_session_account,
                                      sync_session: sync_session,
                                      email_account: email_account)
        sync_session_account.update!(job_id: 'account_job_123')

        sync_session.update!(job_ids: [])

        expect(SolidQueue::Job).not_to receive(:find_by)
        sync_session.cancel_all_jobs
      end
    end

    context 'when job_ids contains valid job IDs' do
      let(:mock_job) { double('SolidQueue::Job', scheduled?: true, ready?: false, destroy: true) }

      before do
        sync_session.update!(job_ids: [ 'job_1', 'job_2', 'job_3' ])
      end

      it 'attempts to find and cancel each main job and account jobs' do
        email_account = create(:email_account)
        sync_session_account = create(:sync_session_account,
                                      sync_session: sync_session,
                                      email_account: email_account)
        sync_session_account.update!(job_id: 'account_job_123')

        expect(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'job_1').and_return(mock_job)
        expect(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'job_2').and_return(nil)
        expect(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'job_3').and_return(mock_job)
        expect(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'account_job_123').and_return(nil)

        expect(mock_job).to receive(:destroy).twice

        sync_session.cancel_all_jobs
      end

      it 'only cancels scheduled or ready jobs' do
        running_job   = double('SolidQueue::Job', scheduled?: false, ready?: false)
        scheduled_job = double('SolidQueue::Job', scheduled?: true, ready?: false, destroy: true)
        ready_job     = double('SolidQueue::Job', scheduled?: false, ready?: true, destroy: true)

        email_account = create(:email_account)
        sync_session_account = create(:sync_session_account,
                                      sync_session: sync_session,
                                      email_account: email_account)
        sync_session_account.update!(job_id: 'account_job_123')

        allow(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'job_1').and_return(running_job)
        allow(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'job_2').and_return(scheduled_job)
        allow(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'job_3').and_return(ready_job)
        allow(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'account_job_123').and_return(nil)

        expect(running_job).not_to receive(:destroy)
        expect(scheduled_job).to receive(:destroy)
        expect(ready_job).to receive(:destroy)

        sync_session.cancel_all_jobs
      end
    end

    context 'when cancelling account-specific jobs' do
      let(:mock_account_job) { double('SolidQueue::Job', scheduled?: true, ready?: false, destroy: true) }

      before do
        sync_session.update!(job_ids: [ 'dummy_job' ])
      end

      it 'cancels jobs for all sync_session_accounts with job_ids' do
        email_account1 = create(:email_account)
        email_account2 = create(:email_account)

        account1 = create(:sync_session_account, sync_session: sync_session, email_account: email_account1)
        account1.update!(job_id: 'account_job_123')

        account2 = create(:sync_session_account, sync_session: sync_session, email_account: email_account2)
        account2.update!(job_id: 'another_job_456')

        expect(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'dummy_job').and_return(nil)
        expect(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'account_job_123').and_return(mock_account_job)
        expect(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'another_job_456').and_return(nil)
        expect(mock_account_job).to receive(:destroy)

        sync_session.cancel_all_jobs
      end

      it 'skips accounts without job_ids' do
        email_account1 = create(:email_account)
        email_account2 = create(:email_account)
        email_account3 = create(:email_account)

        account_with_job = create(:sync_session_account, sync_session: sync_session, email_account: email_account1)
        account_with_job.update!(job_id: 'account_job_123')

        create(:sync_session_account, sync_session: sync_session, email_account: email_account2, job_id: nil)

        another_with_job = create(:sync_session_account, sync_session: sync_session, email_account: email_account3)
        another_with_job.update!(job_id: 'another_job_456')

        expect(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'dummy_job').and_return(nil)
        expect(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'account_job_123').and_return(nil)
        expect(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'another_job_456').and_return(nil)

        sync_session.cancel_all_jobs
      end
    end

    context 'error handling' do
      before do
        sync_session.update!(job_ids: [ 'failing_job' ])
        allow(Rails.logger).to receive(:error)
      end

      it 'logs errors when job cancellation fails for main jobs' do
        allow(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'failing_job').and_raise(StandardError.new('Job cancellation failed'))

        sync_session.cancel_all_jobs

        expect(Rails.logger).to have_received(:error).with('Failed to cancel job failing_job: Job cancellation failed')
      end

      it 'logs errors when account job cancellation fails' do
        email_account = create(:email_account)
        account = create(:sync_session_account, sync_session: sync_session, email_account: email_account)
        account.update!(job_id: 'account_job_123')

        allow(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'failing_job').and_return(nil)
        allow(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'account_job_123').and_raise(StandardError.new('Account job failed'))

        sync_session.cancel_all_jobs

        expect(Rails.logger).to have_received(:error).with('Failed to cancel job account_job_123: Account job failed')
      end

      it 'continues processing other jobs when one fails' do
        working_job = double('SolidQueue::Job', scheduled?: true, ready?: false, destroy: true)

        email_account = create(:email_account)
        account = create(:sync_session_account, sync_session: sync_session, email_account: email_account)
        account.update!(job_id: 'account_job_123')

        sync_session.update!(job_ids: [ 'failing_job', 'working_job' ])

        allow(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'failing_job').and_raise(StandardError.new('Job failed'))
        allow(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'working_job').and_return(working_job)
        allow(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'account_job_123').and_return(nil)

        expect(working_job).to receive(:destroy)

        sync_session.cancel_all_jobs

        expect(Rails.logger).to have_received(:error).with('Failed to cancel job failing_job: Job failed')
      end
    end

    context 'with empty job arrays' do
      it 'handles empty job_ids array' do
        sync_session.update!(job_ids: [])
        expect { sync_session.cancel_all_jobs }.not_to raise_error
      end

      it 'handles sync_session with no accounts' do
        sync_session.sync_session_accounts.destroy_all
        sync_session.update!(job_ids: [ 'job_1' ])

        expect(SolidQueue::Job).to receive(:find_by).with(active_job_id: 'job_1').and_return(nil)
        expect { sync_session.cancel_all_jobs }.not_to raise_error
      end
    end
  end

  describe '#active_accounts_with_latest_expense', :unit do
    let(:sync_session) { build(:sync_session, status: 'running') }

    it 'returns active email accounts ordered by bank_name and email' do
      account1 = create(:email_account, active: true, bank_name: 'Zbank', email: 'z@example.com')
      account2 = create(:email_account, active: true, bank_name: 'Abank', email: 'a@example.com')
      create(:email_account, active: false, bank_name: 'Mbank', email: 'm@example.com')

      results = sync_session.send(:active_accounts_with_latest_expense)
      expect(results.map(&:id)).to eq([ account2.id, account1.id ])
    end

    it 'excludes inactive accounts' do
      create(:email_account, active: false)
      results = sync_session.send(:active_accounts_with_latest_expense)
      expect(results).to be_empty
    end

    it 'exposes latest_expense_created_at attribute from joined subquery' do
      account = create(:email_account, active: true)
      old_expense = create(:expense, email_account: account, created_at: 2.days.ago)
      new_expense = create(:expense, email_account: account, created_at: 1.hour.ago)

      results = sync_session.send(:active_accounts_with_latest_expense)
      expect(results.first.latest_expense_created_at.to_i).to eq(new_expense.created_at.to_i)
    end

    it 'excludes soft-deleted expenses from latest_expense_created_at' do
      account = create(:email_account, active: true)
      create(:expense, email_account: account, created_at: 1.hour.ago, deleted_at: Time.current)

      results = sync_session.send(:active_accounts_with_latest_expense)
      expect(results.first.latest_expense_created_at).to be_nil
    end

    it 'returns nil latest_expense_created_at for accounts with no expenses' do
      create(:email_account, active: true)

      results = sync_session.send(:active_accounts_with_latest_expense)
      expect(results.first.latest_expense_created_at).to be_nil
    end

    it 'issues only a single database query regardless of account count', :unit do
      create_list(:email_account, 5, active: true).each do |account|
        create(:expense, email_account: account)
      end

      expect {
        sync_session.send(:active_accounts_with_latest_expense).load
      }.to make_database_queries(count: 1)
    end
  end

  describe '#build_sync_info_for_dashboard', :unit do
    let(:sync_session) { build(:sync_session, status: 'running') }

    it 'builds a hash keyed by account id with last_sync and account entries' do
      account = create(:email_account, active: true)
      expense = create(:expense, email_account: account, created_at: 30.minutes.ago)

      allow(sync_session).to receive(:active_accounts_with_latest_expense).and_call_original

      result = sync_session.send(:build_sync_info_for_dashboard)

      expect(result[account.id]).to include(:last_sync, :account)
      expect(result[account.id][:account]).to eq(account)
    end

    it 'sets has_running_jobs based on active? status' do
      running_session = build(:sync_session, status: 'running')
      allow(running_session).to receive(:active_accounts_with_latest_expense).and_return([])

      result = running_session.send(:build_sync_info_for_dashboard)

      expect(result[:has_running_jobs]).to be true
      expect(result[:running_job_count]).to eq(1)
    end

    it 'sets has_running_jobs to false when not active' do
      completed_session = build(:sync_session, status: 'completed')
      allow(completed_session).to receive(:active_accounts_with_latest_expense).and_return([])

      result = completed_session.send(:build_sync_info_for_dashboard)

      expect(result[:has_running_jobs]).to be false
      expect(result[:running_job_count]).to eq(0)
    end

    it 'does not issue N+1 queries when building sync info for multiple accounts', :unit do
      accounts = create_list(:email_account, 5, active: true)
      accounts.each { |a| create(:expense, email_account: a) }

      preloaded = sync_session.send(:active_accounts_with_latest_expense).to_a

      expect {
        sync_session.send(:build_sync_info_for_dashboard, preloaded)
      }.to make_database_queries(count: 0)
    end
  end
end
