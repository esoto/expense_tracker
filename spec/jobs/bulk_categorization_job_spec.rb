# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkCategorizationJob, type: :job, unit: true do
  subject(:job) { described_class.new }

  let(:expense_ids) { [ 1, 2, 3, 4, 5 ] }
  let(:category_id) { 10 }
  let(:user_id) { 20 }
  let(:options) { { category_id: category_id, force: true } }
  let(:category) { double('Category', id: category_id, name: 'Test Category') }
  let(:successful_result) do
    OpenStruct.new(
      success?: true,
      message: "Successfully categorized 5 expenses",
      errors: []
    )
  end
  let(:failed_result) do
    OpenStruct.new(
      success?: false,
      message: 'Service failed',
      errors: [ 'Error 1' ]
    )
  end

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Category).to receive(:find_by).with(id: category_id).and_return(category)
    allow(AdminUser).to receive(:find_by).with(id: user_id).and_return(double('AdminUser', id: user_id))
    allow(AdminUser).to receive(:find_by).with(id: nil).and_return(nil)
    allow(Rails.cache).to receive(:write)
    allow(ActionCable.server).to receive(:broadcast)
    allow(Time).to receive(:current).and_return(Time.zone.parse('2025-08-30 12:00:00'))
    allow(SecureRandom).to receive(:uuid).and_return('test-uuid-123')

    allow(Services::BulkCategorization::ApplyService).to receive(:new).and_return(
      double('Service', call: successful_result)
    )
  end

  describe '#perform' do
    context 'with successful batch processing' do
      it 'processes expenses and returns success result' do
        result = job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

        expect(result[:success]).to be true
        expect(result[:affected_count]).to eq(5)
        expect(result[:message]).to include('5 expenses categorized as Test Category')
      end

      it 'logs processing info' do
        job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

        expect(Rails.logger).to have_received(:info).with('Processing bulk categorization: 5 expenses')
      end

      it 'processes expenses in correct batch sizes' do
        large_expense_ids = (1..45).to_a
        service_double = double('Service', call: successful_result)
        allow(Services::BulkCategorization::ApplyService).to receive(:new).and_return(service_double)

        job.perform(expense_ids: large_expense_ids, user_id: user_id, options: options)

        # 45 expenses / 20 batch size = 3 batches (20, 20, 5)
        expect(Services::BulkCategorization::ApplyService).to have_received(:new).exactly(3).times
      end

      it 'passes correct parameters to ApplyService' do
        service_double = double('Service', call: successful_result)
        allow(Services::BulkCategorization::ApplyService).to receive(:new).and_return(service_double)

        job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

        expect(Services::BulkCategorization::ApplyService).to have_received(:new).with(
          expense_ids: expense_ids,
          category_id: category_id,
          user_id: user_id,
          options: { force: true, send_notifications: false }
        )
      end

      it 'tracks progress via BaseJob' do
        job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

        expect(Rails.cache).to have_received(:write).with(
          /bulk_operation_progress/,
          hash_including(percentage: 0, message: "Starting bulk operation..."),
          expires_in: 1.hour
        )
      end

      it 'broadcasts completion via BaseJob' do
        job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

        expect(ActionCable.server).to have_received(:broadcast).with(
          "bulk_operations_completion_#{user_id}",
          hash_including(success: true, affected_count: 5)
        )
      end
    end

    context 'with failed batch processing' do
      before do
        service_double = double('Service', call: failed_result)
        allow(Services::BulkCategorization::ApplyService).to receive(:new).and_return(service_double)
      end

      it 'logs batch processing errors' do
        job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

        expect(Rails.logger).to have_received(:error).with('Batch processing failed: Service failed')
      end

      it 'tracks failed batch in cache' do
        job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

        expect(Rails.cache).to have_received(:write).with(
          'failed_bulk_categorization_test-uuid-123',
          {
            expense_ids: expense_ids,
            errors: [ 'Error 1' ],
            timestamp: Time.current
          },
          expires_in: 7.days
        )
      end

      it 'returns failure result with failures array' do
        result = job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

        expect(result[:success]).to be false
        expect(result[:affected_count]).to eq(0)
        expect(result[:failures]).not_to be_empty
      end

      it 'broadcasts failure via BaseJob' do
        job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

        expect(ActionCable.server).to have_received(:broadcast).with(
          "bulk_operations_completion_#{user_id}",
          hash_including(success: false)
        )
      end
    end

    context 'when job encounters an unhandled error' do
      let(:test_error) { StandardError.new('Database connection failed') }

      before do
        allow(Services::BulkCategorization::ApplyService).to receive(:new).and_raise(test_error)
      end

      it 'lets BaseJob handle the error and re-raises for retry' do
        expect {
          job.perform(expense_ids: expense_ids, user_id: user_id, options: options)
        }.to raise_error(StandardError, 'Database connection failed')
      end

      it 'tracks error progress via BaseJob' do
        begin
          job.perform(expense_ids: expense_ids, user_id: user_id, options: options)
        rescue StandardError
          # Expected
        end

        expect(Rails.cache).to have_received(:write).with(
          /bulk_operation_progress/,
          hash_including(error: true),
          expires_in: 1.hour
        )
      end
    end

    context 'with empty expense_ids' do
      it 'handles empty array gracefully' do
        result = job.perform(expense_ids: [], user_id: user_id, options: options)

        expect(result[:success]).to be true
        expect(result[:affected_count]).to eq(0)
      end
    end

    context 'without user_id' do
      it 'passes nil user_id to ApplyService' do
        service_double = double('Service', call: successful_result)
        allow(Services::BulkCategorization::ApplyService).to receive(:new).and_return(service_double)

        job.perform(expense_ids: expense_ids, options: options)

        expect(Services::BulkCategorization::ApplyService).to have_received(:new).with(
          hash_including(user_id: nil)
        )
      end
    end
  end

  describe '#execute_operation (via perform)' do
    it 'extracts category_id from options' do
      other_category = double('Category', id: 99, name: 'Other Category')
      allow(Category).to receive(:find_by).with(id: 99).and_return(other_category)
      service_double = double('Service', call: successful_result)
      allow(Services::BulkCategorization::ApplyService).to receive(:new).and_return(service_double)

      job.perform(expense_ids: expense_ids, user_id: user_id, options: { category_id: 99 })

      expect(Services::BulkCategorization::ApplyService).to have_received(:new).with(
        hash_including(category_id: 99)
      )
    end

    it 'reports incremental progress during batch processing' do
      large_ids = (1..40).to_a
      service_double = double('Service', call: successful_result)
      allow(Services::BulkCategorization::ApplyService).to receive(:new).and_return(service_double)

      job.perform(expense_ids: large_ids, user_id: user_id, options: options)

      # Should broadcast progress at 50% (20/40) and 100% (40/40)
      expect(ActionCable.server).to have_received(:broadcast).with(
        "bulk_operations_#{user_id}",
        hash_including(percentage: 50, message: "Processed 20/40 expenses")
      )
      expect(ActionCable.server).to have_received(:broadcast).with(
        "bulk_operations_#{user_id}",
        hash_including(percentage: 100, message: "Processed 40/40 expenses")
      )
    end

    it 'handles missing category gracefully' do
      allow(Category).to receive(:find_by).with(id: category_id).and_return(nil)

      result = job.perform(expense_ids: expense_ids, user_id: user_id, options: options)

      expect(result[:message]).to include('categorized as category')
    end
  end

  describe 'job configuration' do
    it 'inherits bulk_operations queue from BaseJob' do
      expect(described_class.queue_name).to eq('bulk_operations')
    end

    it 'defines performance constants' do
      expect(described_class::MAX_EXPENSES_PER_JOB).to eq(100)
      expect(described_class::BATCH_SIZE).to eq(20)
    end

    it 'extends BulkOperations::BaseJob' do
      expect(described_class.superclass).to eq(BulkOperations::BaseJob)
    end
  end
end
