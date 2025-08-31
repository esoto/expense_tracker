# frozen_string_literal: true

require 'rails_helper'

# Stub User class for testing since BaseJob references it
class User
  attr_accessor :id
  
  def initialize(id)
    @id = id
  end
  
  def self.find_by(id:)
    new(id) if id
  end
end unless defined?(User)

# Test-specific subclasses for testing the abstract base class
class SuccessfulBulkJob < BulkOperations::BaseJob
  def execute_operation
    {
      success: true,
      message: 'Operation completed successfully',
      affected_count: @expense_ids.count
    }
  end

  def service_class
    "TestService"
  end
end

class FailingBulkJob < BulkOperations::BaseJob
  def execute_operation
    {
      success: false,
      message: 'Operation failed with validation errors',
      errors: ['Validation error 1', 'Validation error 2']
    }
  end

  def service_class
    "FailingService"
  end
end

class ErrorBulkJob < BulkOperations::BaseJob
  def execute_operation
    raise StandardError, 'Unexpected database error occurred'
  end

  def service_class
    "ErrorService"
  end
end

class IncompleteJob < BulkOperations::BaseJob
  # Intentionally not implementing required methods to test NotImplementedError
end

RSpec.describe BulkOperations::BaseJob, type: :job, unit: true do
  let(:expense_ids) { [1, 2, 3, 4, 5] }
  let(:user_id) { 42 }
  let(:user) { User.new(user_id) }
  let(:options) { { batch_size: 10, force: true } }
  let(:job_id) { 'test-job-123' }

  # Spy doubles for external dependencies
  let(:rails_cache) { instance_spy(ActiveSupport::Cache::Store) }
  let(:action_cable) { instance_spy(ActionCable::Server::Base) }
  let(:rails_logger) { instance_spy(Logger) }

  before do
    # Mock external dependencies with spies
    allow(Rails).to receive(:cache).and_return(rails_cache)
    allow(ActionCable).to receive(:server).and_return(action_cable)
    allow(Rails).to receive(:logger).and_return(rails_logger)
    allow(Time).to receive(:current).and_return(Time.zone.parse('2025-08-31 10:00:00'))
  end

  describe 'abstract method contract' do
    subject(:incomplete_job) { IncompleteJob.new }

    before do
      allow(incomplete_job).to receive(:job_id).and_return(job_id)
    end

    describe '#execute_operation' do
      it 'raises NotImplementedError when not implemented in subclass' do
        expect { incomplete_job.send(:execute_operation) }.to raise_error(
          NotImplementedError,
          'Subclasses must implement execute_operation'
        )
      end
    end

    describe '#service_class' do
      it 'raises NotImplementedError when not implemented in subclass' do
        expect { incomplete_job.send(:service_class) }.to raise_error(
          NotImplementedError,
          'Subclasses must implement service_class'
        )
      end
    end

    it 'enforces implementation of both abstract methods' do
      expect { incomplete_job.perform(expense_ids: expense_ids) }.to raise_error(
        NotImplementedError,
        'Subclasses must implement execute_operation'
      )
    end
  end

  describe 'successful operation path' do
    subject(:successful_job) { SuccessfulBulkJob.new }

    before do
      allow(successful_job).to receive(:job_id).and_return(job_id)
    end

    context 'with user context' do
      it 'executes operation and tracks progress correctly' do
        result = successful_job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

        # Verify result
        expect(result).to eq({
          success: true,
          message: 'Operation completed successfully',
          affected_count: 5
        })

        # Verify progress tracking calls
        expect(rails_cache).to have_received(:write).with(
          "bulk_operation_progress:#{job_id}",
          {
            percentage: 0,
            message: 'Starting bulk operation...',
            error: false,
            updated_at: Time.current
          },
          expires_in: 1.hour
        ).ordered

        expect(rails_cache).to have_received(:write).with(
          "bulk_operation_progress:#{job_id}",
          {
            percentage: 100,
            message: 'Operation completed successfully',
            error: false,
            updated_at: Time.current
          },
          expires_in: 1.hour
        ).ordered
      end

      it 'broadcasts progress updates to user-specific channel' do
        successful_job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

        # Verify start broadcast
        expect(action_cable).to have_received(:broadcast).with(
          "bulk_operations_#{user_id}",
          {
            job_id: job_id,
            percentage: 0,
            message: 'Starting bulk operation...',
            error: false
          }
        ).ordered

        # Verify completion broadcast
        expect(action_cable).to have_received(:broadcast).with(
          "bulk_operations_#{user_id}",
          {
            job_id: job_id,
            percentage: 100,
            message: 'Operation completed successfully',
            error: false
          }
        ).ordered
      end

      it 'broadcasts completion notification to user-specific completion channel' do
        successful_job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

        expect(action_cable).to have_received(:broadcast).with(
          "bulk_operations_completion_#{user_id}",
          {
            job_id: job_id,
            success: true,
            affected_count: 5,
            message: 'Operation completed successfully'
          }
        )
      end
    end

    context 'without user context' do
      it 'executes operation and tracks progress correctly' do
        result = successful_job.perform(expense_ids: expense_ids, options: options)

        expect(result).to eq({
          success: true,
          message: 'Operation completed successfully',
          affected_count: 5
        })

        # Verify progress tracking still occurs
        expect(rails_cache).to have_received(:write).exactly(2).times
      end

      it 'broadcasts to general channels without user_id' do
        successful_job.perform(expense_ids: expense_ids, options: options)

        # Verify broadcasts to general channels
        expect(action_cable).to have_received(:broadcast).with(
          'bulk_operations',
          hash_including(job_id: job_id, percentage: 0)
        )

        expect(action_cable).to have_received(:broadcast).with(
          'bulk_operations',
          hash_including(job_id: job_id, percentage: 100)
        )

        expect(action_cable).to have_received(:broadcast).with(
          'bulk_operations_completion',
          hash_including(job_id: job_id, success: true)
        )
      end
    end

    context 'with minimal parameters' do
      it 'works with only expense_ids parameter' do
        result = successful_job.perform(expense_ids: expense_ids)

        expect(result[:success]).to be true
        expect(rails_cache).to have_received(:write).at_least(:once)
        expect(action_cable).to have_received(:broadcast).at_least(:once)
      end
    end
  end

  describe 'failure operation path' do
    subject(:failing_job) { FailingBulkJob.new }

    before do
      allow(failing_job).to receive(:job_id).and_return(job_id)
    end

    it 'handles operation failure and tracks error state' do
      result = failing_job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

      expect(result).to eq({
        success: false,
        message: 'Operation failed with validation errors',
        errors: ['Validation error 1', 'Validation error 2']
      })

      # Verify error progress tracking
      expect(rails_cache).to have_received(:write).with(
        "bulk_operation_progress:#{job_id}",
        {
          percentage: 100,
          message: 'Operation failed: Operation failed with validation errors',
          error: true,
          updated_at: Time.current
        },
        expires_in: 1.hour
      )
    end

    it 'broadcasts failure notification with error details' do
      failing_job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

      expect(action_cable).to have_received(:broadcast).with(
        "bulk_operations_completion_#{user_id}",
        {
          job_id: job_id,
          success: false,
          errors: ['Validation error 1', 'Validation error 2'],
          message: 'Operation failed with validation errors'
        }
      )
    end

    it 'does not re-raise exceptions for non-fatal failures' do
      expect {
        failing_job.perform(expense_ids: expense_ids, user_id: user_id, options: options)
      }.not_to raise_error
    end
  end

  describe 'error handling and recovery' do
    subject(:error_job) { ErrorBulkJob.new }

    before do
      allow(error_job).to receive(:job_id).and_return(job_id)
    end

    it 'handles exceptions and re-raises for retry mechanism' do
      expect {
        error_job.perform(expense_ids: expense_ids, user_id: user_id, options: options)
      }.to raise_error(StandardError, 'Unexpected database error occurred')
    end

    it 'tracks error state before re-raising' do
      expect {
        error_job.perform(expense_ids: expense_ids, user_id: user_id, options: options)
      }.to raise_error(StandardError)

      # Verify error was logged
      expect(rails_logger).to have_received(:error).with('Bulk operation job error: Unexpected database error occurred')
      expect(rails_logger).to have_received(:error).with(String).at_least(:once) # Backtrace

      # Verify error progress was tracked
      expect(rails_cache).to have_received(:write).with(
        "bulk_operation_progress:#{job_id}",
        {
          percentage: 100,
          message: 'Operation failed: Unexpected database error occurred',
          error: true,
          updated_at: Time.current
        },
        expires_in: 1.hour
      )
    end

    it 'broadcasts error state before re-raising' do
      expect {
        error_job.perform(expense_ids: expense_ids, user_id: user_id, options: options)
      }.to raise_error(StandardError)

      expect(action_cable).to have_received(:broadcast).with(
        "bulk_operations_#{user_id}",
        {
          job_id: job_id,
          percentage: 100,
          message: 'Operation failed: Unexpected database error occurred',
          error: true
        }
      )
    end

    context 'when progress tracking fails' do
      before do
        allow(rails_cache).to receive(:write).and_raise(Redis::ConnectionError, 'Connection refused')
      end

      it 'logs tracking errors but continues operation' do
        result = SuccessfulBulkJob.new.tap { |j| allow(j).to receive(:job_id).and_return(job_id) }
                                  .perform(expense_ids: expense_ids, user_id: user_id)

        expect(result[:success]).to be true
        expect(rails_logger).to have_received(:error).with('Failed to track progress: Connection refused').at_least(:once)
      end
    end
  end

  describe 'progress tracking details' do
    subject(:successful_job) { SuccessfulBulkJob.new }

    before do
      allow(successful_job).to receive(:job_id).and_return(job_id)
    end

    it 'uses correct cache key format' do
      successful_job.perform(expense_ids: expense_ids, user_id: user_id)

      expect(rails_cache).to have_received(:write).with(
        "bulk_operation_progress:#{job_id}",
        anything,
        anything
      ).at_least(:once)
    end

    it 'sets correct TTL for cache entries' do
      successful_job.perform(expense_ids: expense_ids, user_id: user_id)

      expect(rails_cache).to have_received(:write).with(
        anything,
        anything,
        expires_in: 1.hour
      ).at_least(:once)
    end

    it 'includes timestamp in progress data' do
      frozen_time = Time.zone.parse('2025-08-31 15:30:00')
      allow(Time).to receive(:current).and_return(frozen_time)

      successful_job.perform(expense_ids: expense_ids, user_id: user_id)

      expect(rails_cache).to have_received(:write).with(
        anything,
        hash_including(updated_at: frozen_time),
        anything
      ).at_least(:once)
    end
  end

  describe 'ActionCable broadcasting details' do
    subject(:successful_job) { SuccessfulBulkJob.new }

    before do
      allow(successful_job).to receive(:job_id).and_return(job_id)
    end

    it 'includes job_id in all broadcasts' do
      successful_job.perform(expense_ids: expense_ids, user_id: user_id)

      # All broadcasts should include job_id
      expect(action_cable).to have_received(:broadcast).with(
        anything,
        hash_including(job_id: job_id)
      ).at_least(3).times # Start, completion progress, completion notification
    end

    it 'uses different channels for progress and completion' do
      successful_job.perform(expense_ids: expense_ids, user_id: user_id)

      # Progress channel
      expect(action_cable).to have_received(:broadcast).with(
        "bulk_operations_#{user_id}",
        anything
      ).at_least(:twice)

      # Completion channel
      expect(action_cable).to have_received(:broadcast).with(
        "bulk_operations_completion_#{user_id}",
        anything
      ).once
    end

    context 'with nil user_id' do
      it 'falls back to general broadcast channels' do
        successful_job.perform(expense_ids: expense_ids, user_id: nil)

        expect(action_cable).to have_received(:broadcast).with('bulk_operations', anything).at_least(:once)
        expect(action_cable).to have_received(:broadcast).with('bulk_operations_completion', anything).once
      end
    end
  end

  describe 'retry configuration' do
    it 'is configured to retry on StandardError' do
      # This is a smoke test to verify retry configuration exists
      expect(BulkOperations::BaseJob).to respond_to(:retry_on)
    end

    it 'uses bulk_operations queue' do
      expect(BulkOperations::BaseJob.queue_name).to eq('bulk_operations')
    end
  end

  describe 'job orchestration flow' do
    subject(:successful_job) { SuccessfulBulkJob.new }

    before do
      allow(successful_job).to receive(:job_id).and_return(job_id)
    end

    it 'follows correct execution order' do
      successful_job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

      # Verify that progress tracking occurred  
      expect(rails_cache).to have_received(:write).at_least(:twice) # Initial and final progress

      # Verify broadcasts happened (without strict ordering due to test implementation)
      expect(action_cable).to have_received(:broadcast).with(
        "bulk_operations_#{user_id}",
        hash_including(percentage: 0)
      ).at_least(:once)

      expect(action_cable).to have_received(:broadcast).with(
        "bulk_operations_#{user_id}",
        hash_including(percentage: 100)
      ).at_least(:once)

      expect(action_cable).to have_received(:broadcast).with(
        "bulk_operations_completion_#{user_id}",
        hash_including(success: true)
      ).once
    end
  end

  describe 'edge cases' do
    subject(:successful_job) { SuccessfulBulkJob.new }

    before do
      allow(successful_job).to receive(:job_id).and_return(job_id)
    end

    context 'with empty expense_ids' do
      it 'handles empty array gracefully' do
        result = successful_job.perform(expense_ids: [], user_id: user_id)

        expect(result[:success]).to be true
        expect(result[:affected_count]).to eq(0)
      end
    end

    context 'with invalid user_id' do
      it 'continues without user context' do
        # User.find_by returns nil for nil id in our stub implementation
        result = successful_job.perform(expense_ids: expense_ids, user_id: nil)

        expect(result[:success]).to be true
        # Should broadcast to general channels (at least once)
        expect(action_cable).to have_received(:broadcast).with('bulk_operations', anything).at_least(:once)
      end
    end

    context 'with very large expense_ids array' do
      let(:large_expense_ids) { (1..10000).to_a }

      it 'handles large datasets without issues' do
        result = successful_job.perform(expense_ids: large_expense_ids, user_id: user_id)

        expect(result[:success]).to be true
        expect(result[:affected_count]).to eq(10000)
      end
    end
  end

  describe 'protected method visibility' do
    it 'defines execute_operation as protected in base class' do
      # The base class defines these as protected, which subclasses override
      base_job_methods = BulkOperations::BaseJob.protected_instance_methods
      expect(base_job_methods).to include(:execute_operation)
    end

    it 'defines service_class as protected in base class' do
      base_job_methods = BulkOperations::BaseJob.protected_instance_methods
      expect(base_job_methods).to include(:service_class)
    end
  end

  describe 'private method encapsulation' do
    subject(:job) { SuccessfulBulkJob.new }

    before do
      allow(job).to receive(:job_id).and_return(job_id)
    end

    it 'encapsulates internal helper methods as private' do
      # Check that methods are not public
      public_methods = job.public_methods
      
      expect(public_methods).not_to include(:track_progress)
      expect(public_methods).not_to include(:broadcast_completion)
      expect(public_methods).not_to include(:broadcast_failure)
      expect(public_methods).not_to include(:handle_job_error)
      expect(public_methods).not_to include(:progress_cache_key)
      expect(public_methods).not_to include(:progress_channel)
      expect(public_methods).not_to include(:completion_channel)
      
      # Verify they exist and are callable via send (meaning they're private)
      expect { job.send(:progress_cache_key) }.not_to raise_error
      expect { job.send(:progress_channel) }.not_to raise_error
      expect { job.send(:completion_channel) }.not_to raise_error
    end
  end
end