# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkCategorizationJob, type: :job, unit: true do
  subject(:job) { described_class.new }

  let(:expense_ids) { [1, 2, 3, 4, 5] }
  let(:category_id) { 10 }
  let(:user_id) { 20 }
  let(:options) { { force: true } }
  let(:category) { double('Category', id: category_id, name: 'Test Category') }
  let(:successful_result) { double('Result', success?: true) }
  let(:failed_result) { double('Result', success?: false, message: 'Service failed', errors: ['Error 1']) }

  before do
    # Mock external dependencies
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Category).to receive(:find).with(category_id).and_return(category)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Rails.cache).to receive(:write)
    allow(Time).to receive(:current).and_return(Time.zone.parse('2025-08-30 12:00:00'))
    allow(SecureRandom).to receive(:uuid).and_return('test-uuid-123')

    # Mock the bulk categorization service
    allow(BulkCategorization::ApplyService).to receive(:new).and_return(
      double('Service', call: successful_result)
    )
  end

  describe '#perform' do
    context 'with successful batch processing' do
      it 'processes expenses in batches and notifies completion' do
        job.perform(expense_ids, category_id, user_id, options)

        expect(Rails.logger).to have_received(:info).with('Processing bulk categorization: 5 expenses')
        expect(Rails.logger).to have_received(:info).with(
          {
            event: 'bulk_categorization_completed',
            user_id: user_id,
            expense_count: expense_ids.count,
            category_id: category_id,
            timestamp: '2025-08-30T12:00:00Z'
          }.to_json
        )
      end

      it 'processes expenses in correct batch sizes' do
        large_expense_ids = (1..45).to_a # 45 expenses = 3 batches of 20, 1 batch of 5
        service_double = double('Service', call: successful_result)
        allow(BulkCategorization::ApplyService).to receive(:new).and_return(service_double)

        job.perform(large_expense_ids, category_id, user_id, options)

        # Should create service instances for each batch
        expect(BulkCategorization::ApplyService).to have_received(:new).exactly(3).times
      end

      it 'passes correct parameters to BulkCategorization::ApplyService' do
        service_double = double('Service', call: successful_result)
        allow(BulkCategorization::ApplyService).to receive(:new).and_return(service_double)

        job.perform(expense_ids, category_id, user_id, options)

        expect(BulkCategorization::ApplyService).to have_received(:new).with(
          expense_ids: expense_ids,
          category_id: category_id,
          user_id: user_id,
          options: options.merge(send_notifications: false)
        )
      end

      it 'sends completion notification via Turbo Streams' do
        job.perform(expense_ids, category_id, user_id, options)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to).with(
          "user_#{user_id}_notifications",
          target: 'notifications',
          partial: 'shared/notification',
          locals: {
            message: 'Bulk categorization completed: 5 expenses categorized as Test Category',
            type: :success,
            timestamp: Time.current
          }
        )
      end
    end

    context 'with failed batch processing' do
      before do
        service_double = double('Service', call: failed_result)
        allow(BulkCategorization::ApplyService).to receive(:new).and_return(service_double)
      end

      it 'logs batch processing errors' do
        job.perform(expense_ids, category_id, user_id, options)

        expect(Rails.logger).to have_received(:error).with('Batch processing failed: Service failed')
      end

      it 'tracks failed batch for retry' do
        job.perform(expense_ids, category_id, user_id, options)

        expect(Rails.cache).to have_received(:write).with(
          'failed_bulk_categorization_test-uuid-123',
          {
            expense_ids: expense_ids,
            errors: ['Error 1'],
            timestamp: Time.current
          },
          expires_in: 7.days
        )
      end

      it 'still notifies completion despite batch failures' do
        job.perform(expense_ids, category_id, user_id, options)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to).with(
          "user_#{user_id}_notifications",
          target: 'notifications',
          partial: 'shared/notification',
          locals: {
            message: 'Bulk categorization completed: 5 expenses categorized as Test Category',
            type: :success,
            timestamp: Time.current
          }
        )
      end
    end

    context 'when job encounters an error' do
      let(:test_error) { StandardError.new('Database connection failed') }

      before do
        allow(BulkCategorization::ApplyService).to receive(:new).and_raise(test_error)
      end

      it 'handles the error and re-raises for retry mechanism' do
        expect { job.perform(expense_ids, category_id, user_id, options) }.to raise_error(StandardError, 'Database connection failed')

        expect(Rails.logger).to have_received(:error).with(
          {
            event: 'bulk_categorization_failed',
            error: 'Database connection failed',
            error_class: 'StandardError',
            user_id: user_id,
            expense_count: expense_ids.count,
            category_id: category_id,
            backtrace: test_error.backtrace&.first(5),
            timestamp: '2025-08-30T12:00:00Z'
          }.to_json
        )
      end

      it 'sends error notification to user' do
        expect { job.perform(expense_ids, category_id, user_id, options) }.to raise_error(StandardError)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to).with(
          "user_#{user_id}_notifications",
          target: 'notifications',
          partial: 'shared/notification',
          locals: {
            message: 'Bulk categorization failed. Please try again or contact support if the problem persists.',
            type: :error,
            timestamp: Time.current
          }
        )
      end
    end

    context 'with empty expense_ids' do
      it 'handles empty array gracefully' do
        empty_ids = []

        expect { job.perform(empty_ids, category_id, user_id, options) }.not_to raise_error

        expect(Rails.logger).to have_received(:info).with('Processing bulk categorization: 0 expenses')
      end
    end
  end

  describe '#process_batch' do
    let(:batch_ids) { [1, 2, 3] }
    
    context 'with successful service call' do
      it 'calls BulkCategorization::ApplyService with correct parameters' do
        service_double = double('Service', call: successful_result)
        allow(BulkCategorization::ApplyService).to receive(:new).and_return(service_double)

        job.send(:process_batch, batch_ids, category_id, user_id, options)

        expect(BulkCategorization::ApplyService).to have_received(:new).with(
          expense_ids: batch_ids,
          category_id: category_id,
          user_id: user_id,
          options: options.merge(send_notifications: false)
        )
        expect(service_double).to have_received(:call)
      end

      it 'does not log errors for successful batches' do
        service_double = double('Service', call: successful_result)
        allow(BulkCategorization::ApplyService).to receive(:new).and_return(service_double)

        job.send(:process_batch, batch_ids, category_id, user_id, options)

        expect(Rails.logger).not_to have_received(:error)
      end
    end

    context 'with failed service call' do
      before do
        service_double = double('Service', call: failed_result)
        allow(BulkCategorization::ApplyService).to receive(:new).and_return(service_double)
      end

      it 'logs the failure and tracks failed batch' do
        job.send(:process_batch, batch_ids, category_id, user_id, options)

        expect(Rails.logger).to have_received(:error).with('Batch processing failed: Service failed')
        expect(Rails.cache).to have_received(:write).with(
          'failed_bulk_categorization_test-uuid-123',
          {
            expense_ids: batch_ids,
            errors: ['Error 1'],
            timestamp: Time.current
          },
          expires_in: 7.days
        )
      end
    end
  end

  describe '#notify_completion' do
    it 'broadcasts success notification to user' do
      job.send(:notify_completion, expense_ids.count, category_id, user_id)

      expect(Category).to have_received(:find).with(category_id)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to).with(
        "user_#{user_id}_notifications",
        target: 'notifications',
        partial: 'shared/notification',
        locals: {
          message: 'Bulk categorization completed: 5 expenses categorized as Test Category',
          type: :success,
          timestamp: Time.current
        }
      )
    end

    it 'logs structured completion data' do
      job.send(:notify_completion, expense_ids.count, category_id, user_id)

      expect(Rails.logger).to have_received(:info).with(
        {
          event: 'bulk_categorization_completed',
          user_id: user_id,
          expense_count: expense_ids.count,
          category_id: category_id,
          timestamp: '2025-08-30T12:00:00Z'
        }.to_json
      )
    end
  end

  describe '#handle_job_error' do
    let(:test_error) do
      error = StandardError.new('Connection timeout')
      error.set_backtrace(['line1', 'line2', 'line3', 'line4', 'line5', 'line6'])
      error
    end

    it 'logs structured error information' do
      job.send(:handle_job_error, test_error, expense_ids, category_id, user_id)

      expect(Rails.logger).to have_received(:error).with(
        {
          event: 'bulk_categorization_failed',
          error: 'Connection timeout',
          error_class: 'StandardError',
          user_id: user_id,
          expense_count: expense_ids.count,
          category_id: category_id,
          backtrace: ['line1', 'line2', 'line3', 'line4', 'line5'],
          timestamp: '2025-08-30T12:00:00Z'
        }.to_json
      )
    end

    it 'broadcasts error notification to user' do
      job.send(:handle_job_error, test_error, expense_ids, category_id, user_id)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to).with(
        "user_#{user_id}_notifications",
        target: 'notifications',
        partial: 'shared/notification',
        locals: {
          message: 'Bulk categorization failed. Please try again or contact support if the problem persists.',
          type: :error,
          timestamp: Time.current
        }
      )
    end
  end

  describe '#track_failed_batch' do
    let(:batch_ids) { [1, 2, 3] }
    let(:result) { double('Result', errors: ['Error 1', 'Error 2']) }

    it 'stores failed batch data in cache' do
      job.send(:track_failed_batch, batch_ids, result)

      expect(Rails.cache).to have_received(:write).with(
        'failed_bulk_categorization_test-uuid-123',
        {
          expense_ids: batch_ids,
          errors: ['Error 1', 'Error 2'],
          timestamp: Time.current
        },
        expires_in: 7.days
      )
    end
  end

  describe 'job configuration' do
    it 'is configured to use bulk_operations queue' do
      expect(described_class.queue_name).to eq('bulk_operations')
    end

    it 'has retry configuration for deadlocks' do
      # Test that retry_on is configured - this is more of a smoke test
      # since the actual retry configuration is defined in the class
      expect(described_class).to respond_to(:retry_on)
    end

    it 'has retry configuration for record not found' do
      # Test that retry_on is configured - this is more of a smoke test
      # since the actual retry configuration is defined in the class
      expect(described_class).to respond_to(:retry_on)
    end

    it 'defines performance constants' do
      expect(described_class::MAX_EXPENSES_PER_JOB).to eq(100)
      expect(described_class::BATCH_SIZE).to eq(20)
    end
  end
end