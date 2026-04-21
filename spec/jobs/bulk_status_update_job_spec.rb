# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkStatusUpdateJob, type: :job, unit: true do
  subject(:job) { described_class.new }

  let(:user) { double('User', id: 1) }
  let(:expense_ids) { (1..120).to_a } # 3 batches: 50, 50, 20
  let(:status) { 'processed' }
  let(:options) { { broadcast_updates: true } }
  let(:merged_options) { options.merge(force_synchronous: true) }

  # Mock services
  let(:batch_service) { double('BatchService', call: { success: true }) }

  before do
    # Stub constants for unit test environment
    # PR 8: BaseJob reloads via User.find_by (was AdminUser).
    user_class = double('UserClass')
    stub_const('User', user_class)

    status_update_service_class = double('StatusUpdateServiceClass')
    stub_const('Services::BulkOperations::StatusUpdateService', status_update_service_class)

    # Mock inherited behavior from BaseJob
    allow(User).to receive(:find_by).with(id: user.id).and_return(user)
    allow(job).to receive(:track_progress)
    allow(job).to receive(:broadcast_completion)
    allow(job).to receive(:broadcast_failure)
    allow(job).to receive(:handle_job_error)
    allow(job).to receive(:job_id).and_return('test-job-id')

    # Default service mocking - allow any parameters
    allow(Services::BulkOperations::StatusUpdateService).to receive(:new).and_return(batch_service)
  end

  describe '#perform' do
    context 'with valid status and multiple batches' do
      it 'sets the status and calls parent perform' do
        expect(job).to receive(:track_progress).with(0, "Starting bulk operation...")

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)

        expect(job.instance_variable_get(:@status)).to eq('processed')
      end

      it 'processes expenses in batches of 50' do
        # Mock services for specific batches
        batch1_service = double('Batch1Service', call: { success: true })
        batch2_service = double('Batch2Service', call: { success: true })
        batch3_service = double('Batch3Service', call: { success: true })

        # Set up expectations for batch service creation
        allow(Services::BulkOperations::StatusUpdateService).to receive(:new)
          .with(expense_ids: expense_ids[0...50], status: status, user: user, options: merged_options)
          .and_return(batch1_service)
        allow(Services::BulkOperations::StatusUpdateService).to receive(:new)
          .with(expense_ids: expense_ids[50...100], status: status, user: user, options: merged_options)
          .and_return(batch2_service)
        allow(Services::BulkOperations::StatusUpdateService).to receive(:new)
          .with(expense_ids: expense_ids[100...120], status: status, user: user, options: merged_options)
          .and_return(batch3_service)

        expect(batch1_service).to receive(:call).once
        expect(batch2_service).to receive(:call).once
        expect(batch3_service).to receive(:call).once

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)
      end

      it 'tracks progress after each batch' do
        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)

        # Verify progress tracking calls from BaseJob and execute_operation
        expect(job).to have_received(:track_progress).with(0, "Starting bulk operation...").once
        expect(job).to have_received(:track_progress).with(42, "Updated status for 50 of 120 expenses...").once
        expect(job).to have_received(:track_progress).with(83, "Updated status for 100 of 120 expenses...").once
        expect(job).to have_received(:track_progress).with(100, "Updated status for 120 of 120 expenses...").once
      end
    end

    context 'processes each expense exactly once' do
      it 'does not double-process expenses' do
        processed_expense_ids = []

        allow(Services::BulkOperations::StatusUpdateService).to receive(:new) do |args|
          processed_expense_ids.concat(args[:expense_ids])
          batch_service
        end

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)

        expense_id_frequency = processed_expense_ids.group_by(&:itself).transform_values(&:count)
        expect(expense_id_frequency.values.uniq).to eq([ 1 ])
        expect(expense_id_frequency.size).to eq(120)
      end

      it 'creates services only for batches, not for the full set' do
        service_creation_sizes = []

        allow(Services::BulkOperations::StatusUpdateService).to receive(:new) do |args|
          service_creation_sizes << args[:expense_ids].size
          batch_service
        end

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)

        expect(service_creation_sizes).to eq([ 50, 50, 20 ])
      end
    end

    context 'with different statuses' do
      %w[pending processed failed duplicate].each do |test_status|
        it "correctly processes status '#{test_status}'" do
          job.perform(expense_ids: [ 1, 2, 3 ], status: test_status, user_id: user.id, options: options)

          expect(job.instance_variable_get(:@status)).to eq(test_status)
        end
      end
    end

    context 'with fewer expenses than batch size' do
      let(:expense_ids) { (1..30).to_a }

      it 'processes all expenses in a single batch' do
        single_batch_service = double('SingleBatchService', call: { success: true })

        allow(Services::BulkOperations::StatusUpdateService).to receive(:new)
          .with(expense_ids: expense_ids, status: status, user: user, options: merged_options)
          .and_return(single_batch_service)

        expect(single_batch_service).to receive(:call).once

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)
      end
    end

    context 'with exactly 50 expenses (single batch boundary)' do
      let(:expense_ids) { (1..50).to_a }

      it 'processes in one batch' do
        boundary_service = double('BoundaryService', call: { success: true })

        allow(Services::BulkOperations::StatusUpdateService).to receive(:new)
          .with(expense_ids: expense_ids, status: status, user: user, options: merged_options)
          .and_return(boundary_service)

        expect(boundary_service).to receive(:call).once

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)
      end
    end

    context 'with exactly 100 expenses (double batch boundary)' do
      let(:expense_ids) { (1..100).to_a }

      it 'processes in exactly 2 batches' do
        batch_services = []

        allow(Services::BulkOperations::StatusUpdateService).to receive(:new) do |args|
          service = double("Service#{args[:expense_ids].size}", call: { success: true })
          batch_services << { size: args[:expense_ids].size, service: service }
          service
        end

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)

        sizes = batch_services.map { |b| b[:size] }
        expect(sizes).to eq([ 50, 50 ])
      end
    end

    context 'with no expenses' do
      let(:expense_ids) { [] }

      it 'completes successfully without processing batches' do
        expect(Services::BulkOperations::StatusUpdateService).not_to receive(:new)

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)
      end
    end

    context 'with single expense' do
      let(:expense_ids) { [ 42 ] }

      it 'processes single expense exactly once' do
        single_service = double('SingleService', call: { success: true })

        allow(Services::BulkOperations::StatusUpdateService).to receive(:new)
          .with(expense_ids: [ 42 ], status: status, user: user, options: merged_options)
          .and_return(single_service)

        expect(single_service).to receive(:call).once

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)
      end
    end

    context 'when service fails during batch processing' do
      let(:test_error) { StandardError.new('Status update failed') }

      before do
        allow(Services::BulkOperations::StatusUpdateService).to receive(:new).and_return(batch_service)
        allow(batch_service).to receive(:call).and_raise(test_error)
      end

      it 'handles the error and re-raises for retry mechanism' do
        expect { job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options) }
          .to raise_error(StandardError, 'Status update failed')

        expect(job).to have_received(:handle_job_error).with(test_error)
      end
    end

    context 'when user is not found' do
      before do
        allow(User).to receive(:find_by).with(id: user.id).and_return(nil)
      end

      it 'proceeds with nil user' do
        allow(Services::BulkOperations::StatusUpdateService).to receive(:new)
          .with(expense_ids: anything, status: status, user: nil, options: merged_options)
          .and_return(batch_service)

        expect { job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options) }
          .not_to raise_error
      end
    end

    context 'when status is not provided' do
      it 'allows nil status but may cause issues in service' do
        allow(Services::BulkOperations::StatusUpdateService).to receive(:new)
          .with(expense_ids: anything, status: nil, user: user, options: merged_options)
          .and_return(batch_service)

        expect { job.perform(expense_ids: expense_ids, status: nil, user_id: user.id, options: options) }
          .not_to raise_error

        expect(job.instance_variable_get(:@status)).to be_nil
      end
    end
  end

  describe '#execute_operation' do
    let(:expense_ids) { [ 1, 2, 3 ] }

    before do
      job.instance_variable_set(:@expense_ids, expense_ids)
      job.instance_variable_set(:@status, status)
      job.instance_variable_set(:@user, user)
      job.instance_variable_set(:@options, options)
    end

    it 'creates service only for each batch, not for full set' do
      expect(Services::BulkOperations::StatusUpdateService).to receive(:new)
        .with(expense_ids: expense_ids, status: status, user: user, options: merged_options)
        .once
        .and_return(batch_service)

      expect(batch_service).to receive(:call).once

      job.send(:execute_operation)
    end

    it 'processes each expense exactly once' do
      processed_expense_ids = []

      allow(Services::BulkOperations::StatusUpdateService).to receive(:new) do |args|
        processed_expense_ids.concat(args[:expense_ids])
        batch_service
      end

      job.send(:execute_operation)

      expense_id_frequency = processed_expense_ids.group_by(&:itself).transform_values(&:count)
      expect(expense_id_frequency.values.uniq).to eq([ 1 ])
    end

    context 'with large batch' do
      let(:expense_ids) { (1..150).to_a }

      it 'processes all batches without throttling' do
        allow(Services::BulkOperations::StatusUpdateService).to receive(:new).and_return(batch_service)

        job.send(:execute_operation)

        # 3 batches: 50, 50, 50
        expect(Services::BulkOperations::StatusUpdateService).to have_received(:new).exactly(3).times
      end
    end

    context 'progress tracking accuracy' do
      let(:expense_ids) { (1..75).to_a } # Will create 2 batches: 50, 25

      it 'calculates correct progress percentages' do
        allow(Services::BulkOperations::StatusUpdateService).to receive(:new).and_return(batch_service)

        job.send(:execute_operation)

        expect(job).to have_received(:track_progress).with(67, "Updated status for 50 of 75 expenses...").once
        expect(job).to have_received(:track_progress).with(100, "Updated status for 75 of 75 expenses...").once
      end
    end
  end

  describe '#service_class' do
    it 'returns Services::BulkOperations::StatusUpdateService' do
      expect(job.send(:service_class)).to eq(Services::BulkOperations::StatusUpdateService)
    end
  end

  describe 'job configuration' do
    it 'inherits queue configuration from BaseJob' do
      expect(described_class.queue_name).to eq('bulk_operations')
    end

    it 'inherits from BulkOperations::BaseJob' do
      expect(described_class.superclass).to eq(BulkOperations::BaseJob)
    end

    it 'inherits retry configuration from BaseJob' do
      # BaseJob configures retry_on with exponential backoff
      # The jitter value depends on the Rails/ActiveJob configuration
      expect(described_class.retry_jitter).to be_a(Float)
    end
  end

  describe 'progress calculation' do
    let(:expense_ids) { (1..100).to_a } # 2 batches: 50, 50

    before do
      job.instance_variable_set(:@expense_ids, expense_ids)
      job.instance_variable_set(:@status, status)
      job.instance_variable_set(:@user, user)
      job.instance_variable_set(:@options, options)
      allow(Services::BulkOperations::StatusUpdateService).to receive(:new).and_return(batch_service)
    end

    it 'calculates correct progress percentages' do
      job.send(:execute_operation)

      expect(job).to have_received(:track_progress).with(50, "Updated status for 50 of 100 expenses...").once
      expect(job).to have_received(:track_progress).with(100, "Updated status for 100 of 100 expenses...").once
    end

    it 'rounds progress percentages correctly' do
      # Test with 33 expenses (should show 33%, 67%, 100% progress)
      job.instance_variable_set(:@expense_ids, (1..33).to_a)

      job.send(:execute_operation)

      # Since batch size is 50, all 33 will be in one batch
      expect(job).to have_received(:track_progress).with(100, "Updated status for 33 of 33 expenses...").once
    end
  end

  describe 'BaseJob integration (20% focus as per architect recommendation)' do
    it 'properly integrates with BaseJob#perform' do
      # Verify the job correctly overrides perform and calls super
      expect(job).to respond_to(:perform)
      expect(job.method(:perform).owner).to eq(described_class)
    end

    it 'uses BaseJob error handling' do
      # BaseJob provides retry_on and error handling
      expect(described_class.ancestors).to include(BulkOperations::BaseJob)
    end

    it 'leverages BaseJob broadcasting methods' do
      # Test that BaseJob's broadcast methods are available (private methods)
      expect(job.private_methods).to include(:broadcast_completion)
      expect(job.private_methods).to include(:broadcast_failure)
    end
  end

  describe 'performance characteristics' do
    context 'with very large dataset' do
      let(:expense_ids) { (1..10000).to_a } # 200 batches

      it 'processes efficiently in batches' do
        call_count = 0

        allow(Services::BulkOperations::StatusUpdateService).to receive(:new) do
          call_count += 1
          batch_service
        end

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)

        # Should create exactly 200 batch services (no redundant initial service)
        expect(call_count).to eq(200)
      end
    end
  end
end
