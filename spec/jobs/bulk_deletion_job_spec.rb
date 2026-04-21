# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkDeletionJob, type: :job, unit: true do
  subject(:job) { described_class.new }

  let(:user) { double('User', id: 1) }
  let(:expense_ids) { (1..120).to_a } # 3 batches: 50, 50, 20
  let(:options) { { reason: 'test_deletion' } }
  let(:merged_options) { options.merge(force_synchronous: true) }

  # Mock services
  let(:batch_service) { double('BatchService', call: { success: true }) }

  before do
    # Stub constants for unit test environment
    user_class = double('UserClass')
    stub_const('User', user_class)

    deletion_service_class = double('DeletionServiceClass')
    stub_const('Services::BulkOperations::DeletionService', deletion_service_class)

    # Mock inherited behavior from BaseJob
    allow(User).to receive(:find_by).with(id: user.id).and_return(user)
    allow(job).to receive(:track_progress)
    allow(job).to receive(:broadcast_completion)
    allow(job).to receive(:broadcast_failure)
    allow(job).to receive(:handle_job_error)
    allow(job).to receive(:job_id).and_return('test-job-id')

    # Default service mocking - allow any parameters
    allow(Services::BulkOperations::DeletionService).to receive(:new).and_return(batch_service)
  end

  describe '#perform' do
    context 'with multiple batches' do
      it 'processes expenses in batches of 50' do
        # Mock services for specific batches
        batch1_service = double('Batch1Service', call: { success: true })
        batch2_service = double('Batch2Service', call: { success: true })
        batch3_service = double('Batch3Service', call: { success: true })

        # Set up expectations for batch service creation
        allow(Services::BulkOperations::DeletionService).to receive(:new)
          .with(expense_ids: expense_ids[0...50], user: user, options: merged_options)
          .and_return(batch1_service)
        allow(Services::BulkOperations::DeletionService).to receive(:new)
          .with(expense_ids: expense_ids[50...100], user: user, options: merged_options)
          .and_return(batch2_service)
        allow(Services::BulkOperations::DeletionService).to receive(:new)
          .with(expense_ids: expense_ids[100...120], user: user, options: merged_options)
          .and_return(batch3_service)

        expect(batch1_service).to receive(:call).once
        expect(batch2_service).to receive(:call).once
        expect(batch3_service).to receive(:call).once

        job.perform(expense_ids: expense_ids, user_id: user.id, options: options)
      end

      it 'tracks progress after each batch' do
        job.perform(expense_ids: expense_ids, user_id: user.id, options: options)

        # Verify progress tracking calls from BaseJob and execute_operation
        expect(job).to have_received(:track_progress).with(0, "Starting bulk operation...").once
        expect(job).to have_received(:track_progress).with(42, "Deleted 50 of 120 expenses...").once
        expect(job).to have_received(:track_progress).with(83, "Deleted 100 of 120 expenses...").once
        expect(job).to have_received(:track_progress).with(100, "Deleted 120 of 120 expenses...").once
      end
    end

    context 'with fewer expenses than batch size' do
      let(:expense_ids) { (1..30).to_a }

      it 'processes all expenses in a single batch' do
        single_batch_service = double('SingleBatchService', call: { success: true })

        allow(Services::BulkOperations::DeletionService).to receive(:new)
          .with(expense_ids: expense_ids, user: user, options: merged_options)
          .and_return(single_batch_service)

        expect(single_batch_service).to receive(:call).once

        job.perform(expense_ids: expense_ids, user_id: user.id, options: options)
      end
    end

    context 'with no expenses' do
      let(:expense_ids) { [] }

      it 'completes successfully without processing batches' do
        expect(Services::BulkOperations::DeletionService).not_to receive(:new)

        job.perform(expense_ids: expense_ids, user_id: user.id, options: options)
      end
    end

    context 'when service fails during batch processing' do
      let(:test_error) { StandardError.new('Batch deletion failed') }

      before do
        allow(Services::BulkOperations::DeletionService).to receive(:new).and_return(batch_service)
        allow(batch_service).to receive(:call).and_raise(test_error)
      end

      it 'handles the error and re-raises for retry mechanism' do
        expect { job.perform(expense_ids: expense_ids, user_id: user.id, options: options) }
          .to raise_error(StandardError, 'Batch deletion failed')

        expect(job).to have_received(:handle_job_error).with(test_error)
      end
    end

    context 'when user is not found' do
      before do
        allow(User).to receive(:find_by).with(id: user.id).and_return(nil)
      end

      it 'proceeds with nil user' do
        allow(Services::BulkOperations::DeletionService).to receive(:new)
          .with(expense_ids: anything, user: nil, options: merged_options)
          .and_return(batch_service)

        expect { job.perform(expense_ids: expense_ids, user_id: user.id, options: options) }
          .not_to raise_error
      end
    end
  end

  describe '#execute_operation' do
    let(:expense_ids) { [ 1, 2, 3 ] }

    before do
      job.instance_variable_set(:@expense_ids, expense_ids)
      job.instance_variable_set(:@user, user)
      job.instance_variable_set(:@options, options)
    end

    it 'creates service only for each batch, not for full set' do
      expect(Services::BulkOperations::DeletionService).to receive(:new)
        .with(expense_ids: expense_ids, user: user, options: merged_options)
        .once
        .and_return(batch_service)

      expect(batch_service).to receive(:call).once

      job.send(:execute_operation)
    end

    it 'processes each expense exactly once' do
      processed_expense_ids = []

      allow(Services::BulkOperations::DeletionService).to receive(:new) do |args|
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
        allow(Services::BulkOperations::DeletionService).to receive(:new).and_return(batch_service)

        job.send(:execute_operation)

        expect(Services::BulkOperations::DeletionService).to have_received(:new).exactly(3).times
      end
    end
  end

  describe '#service_class' do
    it 'returns Services::BulkOperations::DeletionService' do
      expect(job.send(:service_class)).to eq(Services::BulkOperations::DeletionService)
    end
  end

  describe 'job configuration' do
    it 'inherits queue configuration from BaseJob' do
      expect(described_class.queue_name).to eq('bulk_operations')
    end

    it 'inherits from BulkOperations::BaseJob' do
      expect(described_class.superclass).to eq(BulkOperations::BaseJob)
    end
  end

  describe 'progress calculation' do
    let(:expense_ids) { (1..100).to_a } # 2 batches: 50, 50

    before do
      job.instance_variable_set(:@expense_ids, expense_ids)
      job.instance_variable_set(:@user, user)
      job.instance_variable_set(:@options, options)
      allow(Services::BulkOperations::DeletionService).to receive(:new).and_return(batch_service)
    end

    it 'calculates correct progress percentages' do
      job.send(:execute_operation)

      expect(job).to have_received(:track_progress).with(50, "Deleted 50 of 100 expenses...").once
      expect(job).to have_received(:track_progress).with(100, "Deleted 100 of 100 expenses...").once
    end
  end
end
