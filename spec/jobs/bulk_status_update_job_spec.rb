# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkStatusUpdateJob, type: :job, unit: true do
  subject(:job) { described_class.new }

  let(:user) { double('User', id: 1) }
  let(:expense_ids) { (1..120).to_a } # 3 batches: 50, 50, 20
  let(:status) { 'processed' }
  let(:options) { { broadcast_updates: true } }
  let(:merged_options) { options.merge(force_synchronous: true) }

  # Mock services for different calls
  let(:main_service) { double('MainService', call: { success: true, message: 'Status update completed', affected_count: 120 }) }
  let(:batch_service) { double('BatchService', call: { success: true }) }

  before do
    # Stub constants for unit test environment
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
    allow(job).to receive(:sleep) # Stub sleep to keep tests fast

    # Default service mocking - allow any parameters
    allow(Services::BulkOperations::StatusUpdateService).to receive(:new).and_return(batch_service)
  end

  describe '#perform' do
    context 'with valid status and multiple batches' do
      it 'sets the status and calls parent perform' do
        # This test verifies the basic flow
        # Mock the redundant service at the end
        allow(Services::BulkOperations::StatusUpdateService).to receive(:new)
          .with(expense_ids: expense_ids, status: status, user: user, options: merged_options)
          .and_return(main_service)

        expect(job).to receive(:track_progress).with(0, "Starting bulk operation...")
        expect(main_service).to receive(:call).and_return({ success: true, message: 'Completed', affected_count: 120 })

        result = job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)

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

        # Mock the main service call at the end (the BUG!)
        allow(Services::BulkOperations::StatusUpdateService).to receive(:new)
          .with(expense_ids: expense_ids, status: status, user: user, options: merged_options)
          .and_return(main_service)

        expect(batch1_service).to receive(:call).once
        expect(batch2_service).to receive(:call).once
        expect(batch3_service).to receive(:call).once
        expect(main_service).to receive(:call).once # This is the redundant call!

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

      it 'calls sleep to throttle large jobs' do
        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)

        # Should sleep after each batch since total > 100
        expect(job).to have_received(:sleep).with(0.1).exactly(3).times
      end
    end

    context 'BUG: redundant service call on line 43' do
      it 'makes an unnecessary duplicate call to StatusUpdateService after batch processing' do
        # This test specifically highlights the BUG where the service is called
        # TWICE for all expenses - once in batches and once for the full set

        batch1_service = double('Batch1Service', call: { success: true })
        batch2_service = double('Batch2Service', call: { success: true })
        batch3_service = double('Batch3Service', call: { success: true })
        initial_service = double('InitialService (line 13)', call: { success: true, message: 'Redundant call', affected_count: 120 })

        # Track which services are created
        service_creation_order = []
        creation_count = 0

        allow(Services::BulkOperations::StatusUpdateService).to receive(:new) do |args|
          creation_count += 1
          service_creation_order << args[:expense_ids].size

          # First call is on line 13 (creates service with ALL expense_ids)
          if creation_count == 1
            initial_service  # This service is created but not used in batches!
          else
            # Subsequent calls are for batches (lines 26-31)
            case args[:expense_ids].size
            when 50
              if service_creation_order.count(50) == 1
                batch1_service
              else
                batch2_service
              end
            when 20
              batch3_service
            end
          end
        end

        # All batches are called
        expect(batch1_service).to receive(:call).once
        expect(batch2_service).to receive(:call).once
        expect(batch3_service).to receive(:call).once

        # BUG: The initial service (line 13) is finally called on line 43!
        expect(initial_service).to receive(:call).once

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)

        # Verify the service was instantiated 4 times (1 initial + 3 batches)
        expect(service_creation_order).to eq([ 120, 50, 50, 20 ])
        #                                      ^^^ Initial service with ALL expenses (line 13)
        #                                           ^^^^^^^^^^^ Batch processing
        # The BUG: Initial service (120) is called AGAIN on line 43!
      end

      it 'demonstrates performance impact of the redundant call' do
        # This test shows that expenses are processed TWICE
        processed_expense_ids = []

        allow(Services::BulkOperations::StatusUpdateService).to receive(:new) do |args|
          # Track which expense IDs are being processed
          processed_expense_ids.concat(args[:expense_ids])
          batch_service
        end

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)

        # BUG: Each expense ID appears TWICE in the processed list
        expense_id_frequency = processed_expense_ids.group_by(&:itself).transform_values(&:count)

        # Every expense is processed exactly twice (once in batch, once in redundant call)
        expect(expense_id_frequency.values.uniq).to eq([ 2 ])
        expect(expense_id_frequency.size).to eq(120)
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

      it 'processes all expenses in a single batch without sleep' do
        single_batch_service = double('SingleBatchService', call: { success: true })

        allow(Services::BulkOperations::StatusUpdateService).to receive(:new)
          .with(expense_ids: expense_ids, status: status, user: user, options: merged_options)
          .and_return(single_batch_service)

        # BUG: Even with a single batch, the service is called twice!
        expect(single_batch_service).to receive(:call).twice # Batch call + redundant final call
        expect(job).not_to receive(:sleep) # No sleep for jobs with <= 100 items

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)
      end
    end

    context 'with exactly 50 expenses (single batch boundary)' do
      let(:expense_ids) { (1..50).to_a }

      it 'processes in one batch but still makes redundant call' do
        boundary_service = double('BoundaryService', call: { success: true })

        allow(Services::BulkOperations::StatusUpdateService).to receive(:new)
          .with(expense_ids: expense_ids, status: status, user: user, options: merged_options)
          .and_return(boundary_service)

        # BUG: Service called twice even for perfect batch size
        expect(boundary_service).to receive(:call).twice
        expect(job).not_to receive(:sleep)

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)
      end
    end

    context 'with exactly 100 expenses (double batch boundary)' do
      let(:expense_ids) { (1..100).to_a }

      it 'processes in exactly 2 batches plus redundant call' do
        batch_services = []

        allow(Services::BulkOperations::StatusUpdateService).to receive(:new) do |args|
          service = double("Service#{args[:expense_ids].size}", call: { success: true })
          batch_services << { size: args[:expense_ids].size, service: service }
          service
        end

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)

        # Should create services for: initial (100), batch1 (50), batch2 (50)
        # The initial service (line 13) is called on line 43
        sizes = batch_services.map { |b| b[:size] }
        expect(sizes).to eq([ 100, 50, 50 ]) # Initial service + 2 batches

        # No sleep since total == 100 (not > 100)
        expect(job).not_to have_received(:sleep)
      end
    end

    context 'with exactly 101 expenses (triggers sleep)' do
      let(:expense_ids) { (1..101).to_a }

      it 'triggers sleep behavior at > 100 threshold' do
        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)

        # Should sleep after each batch since total > 100
        expect(job).to have_received(:sleep).with(0.1).exactly(3).times # 2 full batches + 1 partial
      end
    end

    context 'with no expenses' do
      let(:expense_ids) { [] }

      it 'completes successfully without processing batches' do
        empty_service = double('EmptyService', call: { success: true, message: 'No expenses to update', affected_count: 0 })

        allow(Services::BulkOperations::StatusUpdateService).to receive(:new)
          .with(expense_ids: [], status: status, user: user, options: merged_options)
          .and_return(empty_service)

        # Only the redundant final call happens (no batches to process)
        expect(empty_service).to receive(:call).once
        expect(job).not_to receive(:sleep)

        job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options)
      end
    end

    context 'with single expense' do
      let(:expense_ids) { [ 42 ] }

      it 'processes single expense but still makes redundant call' do
        single_service = double('SingleService', call: { success: true })

        allow(Services::BulkOperations::StatusUpdateService).to receive(:new)
          .with(expense_ids: [ 42 ], status: status, user: user, options: merged_options)
          .and_return(single_service)

        # BUG: Even a single expense is processed twice
        expect(single_service).to receive(:call).twice
        expect(job).not_to receive(:sleep)

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
          .with(expense_ids: expense_ids, status: status, user: nil, options: merged_options)
          .and_return(main_service)

        expect { job.perform(expense_ids: expense_ids, status: status, user_id: user.id, options: options) }
          .not_to raise_error
      end
    end

    context 'when status is not provided' do
      it 'allows nil status but may cause issues in service' do
        # The job itself doesn't validate status, but the service might
        allow(Services::BulkOperations::StatusUpdateService).to receive(:new)
          .with(expense_ids: expense_ids, status: nil, user: user, options: merged_options)
          .and_return(main_service)

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

    it 'creates main service and batch services with correct parameters' do
      expect(Services::BulkOperations::StatusUpdateService).to receive(:new)
        .with(expense_ids: expense_ids, status: status, user: user, options: merged_options)
        .and_return(main_service).twice # Once for initial, once for redundant call

      expect(main_service).to receive(:call).twice # BUG: Called twice!

      job.send(:execute_operation)
    end

    it 'demonstrates the redundant final call bug' do
      # This test explicitly shows the BUG on line 43
      # The service is instantiated at line 13 but never used until line 43

      initial_service = double('InitialService')
      batch_service = double('BatchService', call: { success: true })

      # Track service instantiation
      instantiation_count = 0

      allow(Services::BulkOperations::StatusUpdateService).to receive(:new) do |args|
        instantiation_count += 1
        if instantiation_count == 1
          # Line 13: Service created but NEVER USED in batch processing
          initial_service
        else
          # Lines 26-31: New services created for each batch
          batch_service
        end
      end

      # The initial service is created but its reference is lost!
      expect(initial_service).to receive(:call).once # Line 43: Finally used!
      expect(batch_service).to receive(:call).once   # Batch processing

      job.send(:execute_operation)
    end

    context 'with large batch requiring throttling' do
      let(:expense_ids) { (1..150).to_a }

      it 'calls sleep after each batch for large jobs' do
        allow(Services::BulkOperations::StatusUpdateService).to receive(:new).and_return(batch_service, main_service)

        job.send(:execute_operation)

        # 3 batches: 50, 50, 50
        expect(job).to have_received(:sleep).with(0.1).exactly(3).times
      end
    end

    context 'progress tracking accuracy' do
      let(:expense_ids) { (1..75).to_a } # Will create 2 batches: 50, 25

      it 'calculates correct progress percentages' do
        allow(Services::BulkOperations::StatusUpdateService).to receive(:new).and_return(batch_service, main_service)

        job.send(:execute_operation)

        expect(job).to have_received(:track_progress).with(67, "Updated status for 50 of 75 expenses...").once
        expect(job).to have_received(:track_progress).with(100, "Updated status for 75 of 75 expenses...").once
      end
    end
  end

  describe '#service_class' do
    it 'returns BulkOperations::StatusUpdateService' do
      expect(job.send(:service_class)).to eq(BulkOperations::StatusUpdateService)
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
      allow(Services::BulkOperations::StatusUpdateService).to receive(:new).and_return(batch_service, main_service)
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

        # Should create: 1 initial + 200 batches = 201 service instances
        # The initial service (line 13) is used on line 43 (redundant call)
        expect(call_count).to eq(201) # BUG: The initial service processes ALL 10000 items again!
      end
    end
  end
end
