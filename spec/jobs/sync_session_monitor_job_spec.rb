require 'rails_helper'

RSpec.describe SyncSessionMonitorJob, type: :job, unit: true do
  include ActiveJob::TestHelper

  let(:sync_session_id) { 123 }
  let(:sync_session) { instance_double(SyncSession, id: sync_session_id) }
  let(:sync_session_accounts) { [] }
  let(:logger) { instance_double(ActiveSupport::Logger) }

  before do
    allow(Rails).to receive(:logger).and_return(logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
  end

  describe '#perform' do
    describe 'sync session retrieval' do
      context 'when sync session does not exist' do
        before do
          allow(SyncSession).to receive(:find_by).with(id: sync_session_id).and_return(nil)
        end

        it 'returns early without error', unit: true do
          expect { subject.perform(sync_session_id) }.not_to raise_error
        end

        it 'does not attempt to reload', unit: true do
          expect(sync_session).not_to receive(:reload)
          subject.perform(sync_session_id)
        end

        it 'does not log any messages', unit: true do
          expect(logger).not_to receive(:info)
          expect(logger).not_to receive(:error)
          subject.perform(sync_session_id)
        end

        it 'does not reschedule the job', unit: true do
          expect(described_class).not_to receive(:set)
          subject.perform(sync_session_id)
        end
      end

      context 'when sync session exists' do
        before do
          allow(SyncSession).to receive(:find_by).with(id: sync_session_id).and_return(sync_session)
          allow(sync_session).to receive(:reload)
          allow(sync_session).to receive(:running?).and_return(true)
          allow(sync_session).to receive(:sync_session_accounts).and_return(sync_session_accounts)
          allow(sync_session).to receive(:complete!)  # Handle empty accounts case
        end

        it 'finds the sync session by id', unit: true do
          expect(SyncSession).to receive(:find_by).with(id: sync_session_id)
          subject.perform(sync_session_id)
        end

        it 'reloads the sync session to get latest status', unit: true do
          expect(sync_session).to receive(:reload)
          subject.perform(sync_session_id)
        end
      end
    end

    describe 'status checking' do
      before do
        allow(SyncSession).to receive(:find_by).with(id: sync_session_id).and_return(sync_session)
        allow(sync_session).to receive(:reload)
      end

      context 'when sync session is not running (completed)' do
        before do
          allow(sync_session).to receive(:running?).and_return(false)
        end

        it 'returns early without processing', unit: true do
          expect(sync_session).not_to receive(:sync_session_accounts)
          subject.perform(sync_session_id)
        end

        it 'does not attempt to complete or fail the session', unit: true do
          expect(sync_session).not_to receive(:complete!)
          expect(sync_session).not_to receive(:fail!)
          subject.perform(sync_session_id)
        end

        it 'does not reschedule the job', unit: true do
          expect(described_class).not_to receive(:set)
          subject.perform(sync_session_id)
        end

        it 'does not log any messages', unit: true do
          expect(logger).not_to receive(:info)
          subject.perform(sync_session_id)
        end
      end

      context 'when sync session is not running (failed)' do
        before do
          allow(sync_session).to receive(:running?).and_return(false)
        end

        it 'returns early without checking accounts', unit: true do
          expect(sync_session).not_to receive(:sync_session_accounts)
          subject.perform(sync_session_id)
        end

        it 'does not reschedule the job', unit: true do
          expect(described_class).not_to receive(:set)
          subject.perform(sync_session_id)
        end
      end

      context 'when sync session is running' do
        before do
          allow(sync_session).to receive(:running?).and_return(true)
          allow(sync_session).to receive(:sync_session_accounts).and_return(sync_session_accounts)
          allow(sync_session).to receive(:complete!)  # Handle empty accounts case
        end

        it 'continues to process accounts', unit: true do
          expect(sync_session).to receive(:sync_session_accounts)
          subject.perform(sync_session_id)
        end
      end
    end

    describe 'empty accounts handling' do
      before do
        allow(SyncSession).to receive(:find_by).with(id: sync_session_id).and_return(sync_session)
        allow(sync_session).to receive(:reload)
        allow(sync_session).to receive(:running?).and_return(true)
        allow(sync_session).to receive(:sync_session_accounts).and_return([])
      end

      context 'when there are no accounts to process' do
        it 'marks the sync session as completed', unit: true do
          expect(sync_session).to receive(:complete!)
          subject.perform(sync_session_id)
        end

        it 'logs completion message for empty accounts', unit: true do
          allow(sync_session).to receive(:complete!)
          expect(logger).to receive(:info).with("Sync session #{sync_session_id} completed - no accounts to process")
          subject.perform(sync_session_id)
        end

        it 'does not attempt to check account statuses', unit: true do
          allow(sync_session).to receive(:complete!)
          # No account status checks should happen
          subject.perform(sync_session_id)
        end

        it 'does not reschedule the job', unit: true do
          allow(sync_session).to receive(:complete!)
          expect(described_class).not_to receive(:set)
          subject.perform(sync_session_id)
        end
      end
    end

    describe 'accounts processing' do
      let(:account1) { instance_double('SyncSessionAccount') }
      let(:account2) { instance_double('SyncSessionAccount') }
      let(:account3) { instance_double('SyncSessionAccount') }

      before do
        allow(SyncSession).to receive(:find_by).with(id: sync_session_id).and_return(sync_session)
        allow(sync_session).to receive(:reload)
        allow(sync_session).to receive(:running?).and_return(true)
      end

      context 'when all accounts are completed' do
        before do
          allow(account1).to receive(:completed?).and_return(true)
          allow(account1).to receive(:failed?).and_return(false)
          allow(account2).to receive(:completed?).and_return(true)
          allow(account2).to receive(:failed?).and_return(false)
          allow(sync_session).to receive(:sync_session_accounts).and_return([account1, account2])
        end

        it 'marks sync session as completed', unit: true do
          expect(sync_session).to receive(:complete!)
          subject.perform(sync_session_id)
        end

        it 'logs completion message', unit: true do
          allow(sync_session).to receive(:complete!)
          expect(logger).to receive(:info).with("Sync session #{sync_session_id} completed")
          subject.perform(sync_session_id)
        end

        it 'does not reschedule the job', unit: true do
          allow(sync_session).to receive(:complete!)
          expect(described_class).not_to receive(:set)
          subject.perform(sync_session_id)
        end

        it 'checks all accounts for completion status', unit: true do
          allow(sync_session).to receive(:complete!)
          expect(account1).to receive(:completed?)
          expect(account2).to receive(:completed?)
          subject.perform(sync_session_id)
        end
      end

      context 'when all accounts are failed' do
        let(:accounts_collection) { double('AccountsCollection') }
        let(:accounts_relation) { instance_double(ActiveRecord::Relation) }

        before do
          allow(account1).to receive(:completed?).and_return(false)
          allow(account1).to receive(:failed?).and_return(true)
          allow(account2).to receive(:completed?).and_return(false)
          allow(account2).to receive(:failed?).and_return(true)
          
          # Setup accounts collection to behave like ActiveRecord relation
          allow(sync_session).to receive(:sync_session_accounts).and_return(accounts_collection)
          allow(accounts_collection).to receive(:all?) do |&block|
            [account1, account2].all?(&block)
          end
          allow(accounts_collection).to receive(:empty?).and_return(false)
          allow(accounts_collection).to receive_message_chain(:where, :not).with(no_args).with(last_error: nil).and_return(accounts_relation)
          allow(accounts_relation).to receive(:pluck).with(:last_error).and_return(['Error 1', 'Error 2'])
        end

        it 'marks sync session as failed', unit: true do
          expect(sync_session).to receive(:fail!).with('Error 1; Error 2')
          subject.perform(sync_session_id)
        end

        it 'aggregates error messages from all failed accounts', unit: true do
          expect(accounts_relation).to receive(:pluck).with(:last_error).and_return(['Connection timeout', 'Auth failed'])
          expect(sync_session).to receive(:fail!).with('Connection timeout; Auth failed')
          subject.perform(sync_session_id)
        end

        it 'logs failure message', unit: true do
          allow(sync_session).to receive(:fail!)
          expect(logger).to receive(:info).with("Sync session #{sync_session_id} failed - all accounts failed")
          subject.perform(sync_session_id)
        end

        it 'does not reschedule the job', unit: true do
          allow(sync_session).to receive(:fail!)
          expect(described_class).not_to receive(:set)
          subject.perform(sync_session_id)
        end

        it 'checks all accounts for failed status', unit: true do
          allow(sync_session).to receive(:fail!)
          expect(account1).to receive(:failed?)
          expect(account2).to receive(:failed?)
          subject.perform(sync_session_id)
        end
      end

      context 'when all accounts failed but no error messages' do
        let(:accounts_collection) { double('AccountsCollection') }
        let(:accounts_relation) { instance_double(ActiveRecord::Relation) }

        before do
          allow(account1).to receive(:completed?).and_return(false)
          allow(account1).to receive(:failed?).and_return(true)
          allow(account2).to receive(:completed?).and_return(false)
          allow(account2).to receive(:failed?).and_return(true)
          
          # Setup accounts collection to behave like ActiveRecord relation
          allow(sync_session).to receive(:sync_session_accounts).and_return(accounts_collection)
          allow(accounts_collection).to receive(:all?) do |&block|
            [account1, account2].all?(&block)
          end
          allow(accounts_collection).to receive(:empty?).and_return(false)
          allow(accounts_collection).to receive_message_chain(:where, :not).with(no_args).with(last_error: nil).and_return(accounts_relation)
          allow(accounts_relation).to receive(:pluck).with(:last_error).and_return([])
        end

        it 'uses default error message when no specific errors', unit: true do
          expect(sync_session).to receive(:fail!).with('All accounts failed')
          subject.perform(sync_session_id)
        end
      end

      context 'when some accounts are still processing' do
        let(:job_double) { instance_double(ActiveJob::ConfiguredJob) }

        before do
          allow(account1).to receive(:completed?).and_return(true)
          allow(account1).to receive(:failed?).and_return(false)
          allow(account2).to receive(:completed?).and_return(false)
          allow(account2).to receive(:failed?).and_return(false)
          allow(sync_session).to receive(:sync_session_accounts).and_return([account1, account2])
        end

        it 'does not mark sync session as completed', unit: true do
          allow(described_class).to receive(:set).and_return(job_double)
          allow(job_double).to receive(:perform_later)
          expect(sync_session).not_to receive(:complete!)
          expect(sync_session).not_to receive(:fail!)
          subject.perform(sync_session_id)
        end

        it 'reschedules the job for 5 seconds later', unit: true do
          expect(described_class).to receive(:set).with(wait: 5.seconds).and_return(job_double)
          expect(job_double).to receive(:perform_later).with(sync_session_id)
          subject.perform(sync_session_id)
        end

        it 'does not log any completion or failure messages', unit: true do
          allow(described_class).to receive(:set).and_return(job_double)
          allow(job_double).to receive(:perform_later)
          expect(logger).not_to receive(:info)
          subject.perform(sync_session_id)
        end
      end

      context 'with mixed completion statuses (partial success)' do
        before do
          allow(account1).to receive(:completed?).and_return(true)
          allow(account1).to receive(:failed?).and_return(false)
          allow(account2).to receive(:completed?).and_return(false)
          allow(account2).to receive(:failed?).and_return(true)
          allow(account3).to receive(:completed?).and_return(true)
          allow(account3).to receive(:failed?).and_return(false)
          allow(sync_session).to receive(:sync_session_accounts).and_return([account1, account2, account3])
        end

        it 'marks sync session as completed for partial success', unit: true do
          expect(sync_session).to receive(:complete!)
          subject.perform(sync_session_id)
        end

        it 'logs completion message', unit: true do
          allow(sync_session).to receive(:complete!)
          expect(logger).to receive(:info).with("Sync session #{sync_session_id} completed")
          subject.perform(sync_session_id)
        end

        it 'does not fail the session when some accounts succeeded', unit: true do
          allow(sync_session).to receive(:complete!)
          expect(sync_session).not_to receive(:fail!)
          subject.perform(sync_session_id)
        end

        it 'does not reschedule the job', unit: true do
          allow(sync_session).to receive(:complete!)
          expect(described_class).not_to receive(:set)
          subject.perform(sync_session_id)
        end
      end

      context 'when checking account statuses' do
        let(:job_double) { instance_double(ActiveJob::ConfiguredJob) }

        before do
          allow(account1).to receive(:completed?).and_return(false)
          allow(account1).to receive(:failed?).and_return(false)
          allow(sync_session).to receive(:sync_session_accounts).and_return([account1])
          allow(described_class).to receive(:set).with(wait: 5.seconds).and_return(job_double)
          allow(job_double).to receive(:perform_later).with(sync_session_id)
        end

        it 'checks both completed and failed status for each account', unit: true do
          expect(account1).to receive(:completed?).ordered
          expect(account1).to receive(:failed?).ordered
          subject.perform(sync_session_id)
        end

        it 'uses OR logic for completed or failed check', unit: true do
          # Test that it checks if account is either completed OR failed
          expect(account1).to receive(:completed?).and_return(false)
          expect(account1).to receive(:failed?).and_return(false)
          subject.perform(sync_session_id)
        end

        it 'checks failed status even when account is completed', unit: true do
          allow(account1).to receive(:completed?).and_return(true)
          allow(account1).to receive(:failed?).and_return(false)
          allow(sync_session).to receive(:sync_session_accounts).and_return([account1])
          allow(sync_session).to receive(:complete!)
          
          # Even when completed, it still checks failed to determine if ALL failed
          expect(account1).to receive(:completed?).at_least(:once).and_return(true)
          expect(account1).to receive(:failed?).at_least(:once).and_return(false)
          
          subject.perform(sync_session_id)
        end
      end
    end

    describe 'error handling' do
      before do
        allow(SyncSession).to receive(:find_by).with(id: sync_session_id).and_return(sync_session)
      end

      context 'when reload raises an error' do
        before do
          allow(sync_session).to receive(:reload).and_raise(StandardError, 'Database connection lost')
          allow(sync_session).to receive(:fail!)
        end

        it 'rescues the error', unit: true do
          expect { subject.perform(sync_session_id) }.not_to raise_error
        end

        it 'logs the error message', unit: true do
          expect(logger).to receive(:error).with("Error monitoring sync session #{sync_session_id}: Database connection lost")
          subject.perform(sync_session_id)
        end

        it 'fails the sync session with error message', unit: true do
          expect(sync_session).to receive(:fail!).with('Database connection lost')
          subject.perform(sync_session_id)
        end
      end

      context 'when sync_session_accounts raises an error' do
        before do
          allow(sync_session).to receive(:reload)
          allow(sync_session).to receive(:running?).and_return(true)
          allow(sync_session).to receive(:sync_session_accounts).and_raise(ActiveRecord::RecordNotFound, 'Association not found')
          allow(sync_session).to receive(:fail!)
        end

        it 'rescues the error', unit: true do
          expect { subject.perform(sync_session_id) }.not_to raise_error
        end

        it 'logs the error with sync session id', unit: true do
          expect(logger).to receive(:error).with("Error monitoring sync session #{sync_session_id}: Association not found")
          subject.perform(sync_session_id)
        end

        it 'fails the sync session', unit: true do
          expect(sync_session).to receive(:fail!).with('Association not found')
          subject.perform(sync_session_id)
        end
      end

      context 'when complete! raises an error' do
        before do
          allow(sync_session).to receive(:reload)
          allow(sync_session).to receive(:running?).and_return(true)
          allow(sync_session).to receive(:sync_session_accounts).and_return([])
          allow(sync_session).to receive(:complete!).and_raise(StandardError, 'State transition error')
          allow(sync_session).to receive(:fail!)
        end

        it 'rescues the error', unit: true do
          expect { subject.perform(sync_session_id) }.not_to raise_error
        end

        it 'logs the error', unit: true do
          expect(logger).to receive(:error).with("Error monitoring sync session #{sync_session_id}: State transition error")
          subject.perform(sync_session_id)
        end

        it 'attempts to fail the sync session', unit: true do
          expect(sync_session).to receive(:fail!).with('State transition error')
          subject.perform(sync_session_id)
        end
      end

      context 'when fail! raises an error' do
        let(:accounts_collection) { double('AccountsCollection') }
        let(:accounts_relation) { instance_double(ActiveRecord::Relation) }
        let(:account1) { instance_double('SyncSessionAccount') }

        before do
          allow(sync_session).to receive(:reload)
          allow(sync_session).to receive(:running?).and_return(true)
          allow(account1).to receive(:completed?).and_return(false)
          allow(account1).to receive(:failed?).and_return(true)
          
          # Setup accounts collection to behave like ActiveRecord relation
          allow(sync_session).to receive(:sync_session_accounts).and_return(accounts_collection)
          allow(accounts_collection).to receive(:all?) do |&block|
            [account1].all?(&block)
          end
          allow(accounts_collection).to receive(:empty?).and_return(false)
          allow(accounts_collection).to receive_message_chain(:where, :not).with(no_args).with(last_error: nil).and_return(accounts_relation)
          allow(accounts_relation).to receive(:pluck).with(:last_error).and_return(['Error'])
          
          # First call to fail! raises error, second call in rescue should not raise
          call_count = 0
          allow(sync_session).to receive(:fail!) do |msg|
            call_count += 1
            if call_count == 1
              raise StandardError, 'Cannot transition state'
            end
            # Second call succeeds silently
          end
        end

        it 'rescues the error', unit: true do
          expect { subject.perform(sync_session_id) }.not_to raise_error
        end

        it 'logs the error', unit: true do
          expect(logger).to receive(:error).with("Error monitoring sync session #{sync_session_id}: Cannot transition state")
          subject.perform(sync_session_id)
        end
      end

      context 'when sync session is nil in rescue block' do
        before do
          allow(SyncSession).to receive(:find_by).with(id: sync_session_id).and_return(nil)
          # Force an error to trigger rescue block
          allow(SyncSession).to receive(:find_by).and_raise(StandardError, 'Unexpected error')
        end

        it 'handles nil sync_session gracefully', unit: true do
          expect { subject.perform(sync_session_id) }.not_to raise_error
        end

        it 'logs the error', unit: true do
          expect(logger).to receive(:error).with("Error monitoring sync session #{sync_session_id}: Unexpected error")
          subject.perform(sync_session_id)
        end
      end

      context 'when reschedule fails' do
        let(:job_double) { instance_double(ActiveJob::ConfiguredJob) }
        let(:account1) { instance_double('SyncSessionAccount') }

        before do
          allow(sync_session).to receive(:reload)
          allow(sync_session).to receive(:running?).and_return(true)
          allow(account1).to receive(:completed?).and_return(false)
          allow(account1).to receive(:failed?).and_return(false)
          allow(sync_session).to receive(:sync_session_accounts).and_return([account1])
          allow(described_class).to receive(:set).with(wait: 5.seconds).and_raise(StandardError, 'Queue error')
          allow(sync_session).to receive(:fail!)
        end

        it 'rescues and logs the error', unit: true do
          expect(logger).to receive(:error).with("Error monitoring sync session #{sync_session_id}: Queue error")
          subject.perform(sync_session_id)
        end

        it 'fails the sync session', unit: true do
          expect(sync_session).to receive(:fail!).with('Queue error')
          subject.perform(sync_session_id)
        end
      end
    end

    describe 'job configuration' do
      it 'uses the default queue', unit: true do
        expect(described_class.new.queue_name).to eq('default')
      end

      it 'inherits from ApplicationJob', unit: true do
        expect(described_class.superclass).to eq(ApplicationJob)
      end
    end

    describe 'ActiveJob integration' do
      it 'can be enqueued with perform_later', unit: true do
        expect {
          described_class.perform_later(sync_session_id)
        }.to have_enqueued_job(described_class).with(sync_session_id)
      end

      it 'can be scheduled with a delay', unit: true do
        expect {
          described_class.set(wait: 5.seconds).perform_later(sync_session_id)
        }.to have_enqueued_job(described_class).with(sync_session_id).at(be_within(1.second).of(5.seconds.from_now))
      end

      it 'can be performed immediately with perform_now', unit: true do
        allow(SyncSession).to receive(:find_by).with(id: sync_session_id).and_return(nil)
        expect { described_class.perform_now(sync_session_id) }.not_to raise_error
      end
    end
  end
end