require 'rails_helper'

RSpec.describe SyncSessionMonitorJob, type: :job, unit: true do
  subject(:job) { described_class.new }

  let(:sync_session_id) { 123 }
  let(:sync_session) do
    instance_double(SyncSession,
      id: sync_session_id,
      running?: true,
      reload: nil,
      complete!: true,
      fail!: true
    )
  end

  let(:accounts) { [] }
  let(:accounts_relation) do
    double('accounts_relation').tap do |relation|
      allow(relation).to receive(:all?) do |&block|
        accounts.all?(&block) if block
      end
      allow(relation).to receive(:empty?).and_return(accounts.empty?)
      allow(relation).to receive(:where) do
        double('where_relation', not: double('not_relation', pluck: error_messages))
      end
    end
  end

  let(:error_messages) { [] }

  before do
    allow(SyncSession).to receive(:find_by).with(id: sync_session_id).and_return(sync_session)
    allow(sync_session).to receive(:sync_session_accounts).and_return(accounts_relation)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe '#perform' do
    context 'when sync session is not found' do
      before do
        allow(SyncSession).to receive(:find_by).with(id: sync_session_id).and_return(nil)
      end

      it 'returns early without error' do
        expect { job.perform(sync_session_id) }.not_to raise_error
      end

      it 'does not attempt to process' do
        expect(sync_session).not_to receive(:reload)
        job.perform(sync_session_id)
      end

      it 'does not log any messages' do
        expect(Rails.logger).not_to receive(:info)
        expect(Rails.logger).not_to receive(:error)
        job.perform(sync_session_id)
      end
    end

    context 'when sync session is not running' do
      before do
        allow(sync_session).to receive(:running?).and_return(false)
      end

      context 'when status is completed' do
        before do
          allow(sync_session).to receive(:running?).and_return(false)
        end

        it 'returns early without processing' do
          expect(sync_session).not_to receive(:complete!)
          expect(sync_session).not_to receive(:fail!)
          job.perform(sync_session_id)
        end

        it 'reloads the session to get latest status' do
          expect(sync_session).to receive(:reload)
          job.perform(sync_session_id)
        end

        it 'does not reschedule the job' do
          expect(described_class).not_to receive(:set)
          job.perform(sync_session_id)
        end
      end

      context 'when status is failed' do
        before do
          allow(sync_session).to receive(:running?).and_return(false)
        end

        it 'returns early without processing' do
          expect(sync_session).not_to receive(:sync_session_accounts)
          job.perform(sync_session_id)
        end
      end
    end

    context 'when sync session is running' do
      context 'with no accounts' do
        let(:accounts) { [] }

        it 'marks sync session as completed' do
          expect(sync_session).to receive(:complete!)
          job.perform(sync_session_id)
        end

        it 'logs completion with no accounts message' do
          expect(Rails.logger).to receive(:info)
            .with("Sync session #{sync_session_id} completed - no accounts to process")
          job.perform(sync_session_id)
        end

        it 'does not reschedule the job' do
          expect(described_class).not_to receive(:set)
          job.perform(sync_session_id)
        end
      end

      context 'with all accounts completed' do
        let(:account1) { instance_double('SyncSessionAccount', completed?: true, failed?: false) }
        let(:account2) { instance_double('SyncSessionAccount', completed?: true, failed?: false) }
        let(:accounts) { [ account1, account2 ] }

        it 'marks sync session as completed' do
          expect(sync_session).to receive(:complete!)
          job.perform(sync_session_id)
        end

        it 'logs completion message' do
          expect(Rails.logger).to receive(:info)
            .with("Sync session #{sync_session_id} completed")
          job.perform(sync_session_id)
        end

        it 'does not reschedule the job' do
          expect(described_class).not_to receive(:set)
          job.perform(sync_session_id)
        end
      end

      context 'with all accounts failed' do
        let(:account1) { instance_double('SyncSessionAccount', completed?: false, failed?: true) }
        let(:account2) { instance_double('SyncSessionAccount', completed?: false, failed?: true) }
        let(:accounts) { [ account1, account2 ] }
        let(:error_messages) { [ 'Error 1', 'Error 2' ] }

        it 'marks sync session as failed' do
          expect(sync_session).to receive(:fail!).with('Error 1; Error 2')
          job.perform(sync_session_id)
        end

        it 'logs failure message' do
          expect(Rails.logger).to receive(:info)
            .with("Sync session #{sync_session_id} failed - all accounts failed")
          job.perform(sync_session_id)
        end

        it 'does not reschedule the job' do
          expect(described_class).not_to receive(:set)
          job.perform(sync_session_id)
        end

        context 'when no error messages are present' do
          let(:error_messages) { [] }

          it 'uses default error message' do
            expect(sync_session).to receive(:fail!).with('All accounts failed')
            job.perform(sync_session_id)
          end
        end
      end

      context 'with partial success (some failed, some completed)' do
        let(:account1) { instance_double('SyncSessionAccount', completed?: false, failed?: true) }
        let(:account2) { instance_double('SyncSessionAccount', completed?: true, failed?: false) }
        let(:accounts) { [ account1, account2 ] }

        it 'marks sync session as completed' do
          expect(sync_session).to receive(:complete!)
          job.perform(sync_session_id)
        end

        it 'logs completion message' do
          expect(Rails.logger).to receive(:info)
            .with("Sync session #{sync_session_id} completed")
          job.perform(sync_session_id)
        end

        it 'does not reschedule the job' do
          expect(described_class).not_to receive(:set)
          job.perform(sync_session_id)
        end
      end

      context 'with accounts still processing' do
        let(:account1) { instance_double('SyncSessionAccount', completed?: false, failed?: false) }
        let(:account2) { instance_double('SyncSessionAccount', completed?: true, failed?: false) }
        let(:accounts) { [ account1, account2 ] }

        it 'does not change sync session status' do
          expect(sync_session).not_to receive(:complete!)
          expect(sync_session).not_to receive(:fail!)
          job.perform(sync_session_id)
        end

        it 'reschedules itself for 5 seconds later' do
          job_double = double('job')
          expect(described_class).to receive(:set)
            .with(wait: 5.seconds)
            .and_return(job_double)
          expect(job_double).to receive(:perform_later)
            .with(sync_session_id)

          job.perform(sync_session_id)
        end

        it 'does not log any completion messages' do
          allow(described_class).to receive(:set).and_return(double(perform_later: true))
          expect(Rails.logger).not_to receive(:info)
          job.perform(sync_session_id)
        end
      end

      context 'with all accounts still processing' do
        let(:account1) { instance_double('SyncSessionAccount', completed?: false, failed?: false) }
        let(:account2) { instance_double('SyncSessionAccount', completed?: false, failed?: false) }
        let(:accounts) { [ account1, account2 ] }

        it 'reschedules itself' do
          job_double = double('job')
          expect(described_class).to receive(:set)
            .with(wait: 5.seconds)
            .and_return(job_double)
          expect(job_double).to receive(:perform_later)
            .with(sync_session_id)

          job.perform(sync_session_id)
        end
      end
    end

    context 'error handling' do
      context 'when reload raises an error' do
        let(:error) { StandardError.new('Database connection lost') }

        before do
          allow(sync_session).to receive(:reload).and_raise(error)
        end

        it 'logs the error with context' do
          expect(Rails.logger).to receive(:error)
            .with("Error monitoring sync session #{sync_session_id}: Database connection lost")

          job.perform(sync_session_id)
        end

        it 'attempts to fail the sync session' do
          expect(sync_session).to receive(:fail!).with('Database connection lost')
          job.perform(sync_session_id)
        end

        it 'does not raise the error' do
          expect { job.perform(sync_session_id) }.not_to raise_error
        end
      end

      context 'when checking accounts raises an error' do
        let(:error) { ActiveRecord::StatementTimeout.new('Query timeout') }

        before do
          allow(sync_session).to receive(:sync_session_accounts).and_raise(error)
        end

        it 'logs the error' do
          expect(Rails.logger).to receive(:error)
            .with("Error monitoring sync session #{sync_session_id}: Query timeout")

          job.perform(sync_session_id)
        end

        it 'marks sync session as failed' do
          expect(sync_session).to receive(:fail!).with('Query timeout')
          job.perform(sync_session_id)
        end
      end

      context 'when sync session is nil in rescue block' do
        let(:error) { StandardError.new('Unknown error') }

        before do
          allow(SyncSession).to receive(:find_by).and_raise(error)
        end

        it 'logs the error without failing' do
          expect(Rails.logger).to receive(:error)
            .with("Error monitoring sync session #{sync_session_id}: Unknown error")

          job.perform(sync_session_id)
        end

        it 'does not attempt to fail nil sync session' do
          # The &. operator prevents calling fail! on nil
          expect { job.perform(sync_session_id) }.not_to raise_error
        end
      end

      context 'when complete! raises an error' do
        let(:error) { StandardError.new('Validation failed') }

        before do
          allow(sync_session).to receive(:complete!).and_raise(error)
        end

        it 'logs the error and fails the session' do
          expect(Rails.logger).to receive(:error)
            .with("Error monitoring sync session #{sync_session_id}: Validation failed")
          expect(sync_session).to receive(:fail!).with('Validation failed')

          job.perform(sync_session_id)
        end
      end
    end

    context 'edge cases' do
      context 'when status changes during execution' do
        before do
          # First call returns true (passes the check), second returns false
          allow(sync_session).to receive(:running?).and_return(true, false)
        end

        it 'checks status after reload' do
          # It will call sync_session_accounts because first running? check passes
          # But since all accounts are done (empty), it will complete
          expect(sync_session).to receive(:complete!)
          job.perform(sync_session_id)
        end
      end

      context 'with large number of failed accounts' do
        let(:accounts) do
          100.times.map do
            instance_double('SyncSessionAccount', completed?: false, failed?: true)
          end
        end
        let(:error_messages) { 100.times.map { |i| "Error #{i}" } }

        it 'aggregates all error messages' do
          expected_message = error_messages.join('; ')
          expect(sync_session).to receive(:fail!).with(expected_message)
          job.perform(sync_session_id)
        end
      end

      context 'with mixed nil and present error messages' do
        let(:account1) { instance_double('SyncSessionAccount', completed?: false, failed?: true) }
        let(:account2) { instance_double('SyncSessionAccount', completed?: false, failed?: true) }
        let(:accounts) { [ account1, account2 ] }
        let(:error_messages) { [ 'Error 1' ] }  # Only one has error message

        it 'only includes non-nil error messages' do
          expect(sync_session).to receive(:fail!).with('Error 1')
          job.perform(sync_session_id)
        end
      end
    end
  end

  describe 'job configuration' do
    it 'uses the default queue' do
      expect(job.queue_name).to eq('default')
    end

    it 'inherits from ApplicationJob' do
      expect(described_class).to be < ApplicationJob
    end
  end

  describe 'ActiveJob interface' do
    it 'responds to perform_later' do
      expect(described_class).to respond_to(:perform_later)
    end

    it 'responds to perform_now' do
      expect(described_class).to respond_to(:perform_now)
    end

    it 'responds to set' do
      expect(described_class).to respond_to(:set)
    end
  end
end
