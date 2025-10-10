require 'rails_helper'
require 'support/email_processing_processor_test_helper'

RSpec.describe 'Services::EmailProcessing::Processor - Metrics Tracking', type: :service, unit: true do
  include EmailProcessingProcessorTestHelper
  let(:email_account) { create(:email_account, :bac) }
  let(:sync_session) { create(:sync_session) }
  let(:metrics_collector) { instance_double(Services::SyncMetricsCollector) }
  let(:processor) { Services::EmailProcessing::Processor.new(email_account, metrics_collector: metrics_collector) }
  let(:mock_imap_service) { create_mock_imap_service }

  describe 'comprehensive metrics integration' do
    let(:message_ids) { [ 1, 2, 3, 4, 5 ] }
    let(:envelopes) do
      {
        1 => create_envelope('BAC - Notificación de transacción', 'bank@bac.co.cr'),
        2 => create_envelope('Promotional Email', 'promo@store.com'),
        3 => create_envelope('BAC - Notificación de compra', 'bank@bac.co.cr'),
        4 => create_envelope('Cargo a su cuenta', 'alerts@bank.cr'),
        5 => nil # Missing envelope case
      }
    end

    def create_envelope(subject, from_email)
      if subject.downcase.include?('transacción') || subject.downcase.include?('cargo') || subject.downcase.include?('compra')
        create_transaction_envelope(subject)
      else
        create_non_transaction_envelope
      end
    end

    before do
      # Setup IMAP service responses
      envelopes.each do |id, envelope|
        allow(mock_imap_service).to receive(:fetch_envelope).with(id).and_return(envelope)
      end

      # Setup metrics collector expectations
      allow(metrics_collector).to receive(:track_operation).and_yield
    end

    describe 'operation tracking' do
      context 'when processing multiple emails' do
        before do
          allow(processor).to receive(:extract_email_data) do |message_id, envelope, _|
            if envelope && envelope.subject.downcase.include?('transacción')
              {
                message_id: message_id,
                from: 'bank@bac.co.cr',
                subject: envelope.subject,
                date: envelope.date,
                body: 'Transaction details'
              }
            else
              nil
            end
          end

          allow(ProcessEmailJob).to receive(:perform_later)
        end

        it 'tracks each email processing operation with correct parameters' do
          expected_tracked_ids = [ 1, 3, 4 ] # Only transaction emails

          expected_tracked_ids.each do |message_id|
            expect(metrics_collector).to receive(:track_operation).with(
              :parse_email,
              email_account,
              { message_id: message_id }
            ).once.and_yield
          end

          processor.process_emails(message_ids, mock_imap_service)
        end

        it 'includes metadata in tracking calls' do
          allow(metrics_collector).to receive(:track_operation) do |operation, account, metadata, &block|
            expect(operation).to eq(:parse_email)
            expect(account).to eq(email_account)
            expect(metadata).to have_key(:message_id)
            expect(metadata[:message_id]).to be_in([ 1, 2, 3, 4, 5 ])
            block.call if block
          end

          processor.process_emails(message_ids, mock_imap_service)
        end
      end

      context 'when metrics collector raises an error' do
        before do
          allow(metrics_collector).to receive(:track_operation)
            .and_raise(StandardError, 'Metrics error')
        end

        it 'continues processing despite metrics errors' do
          allow(Rails.logger).to receive(:error)

          expect {
            processor.process_emails([ 1 ], mock_imap_service)
          }.not_to raise_error
        end
      end
    end

    describe 'conflict detection with metrics' do
      let(:sync_session) { instance_double(SyncSession) }
      let(:conflict_detector) { instance_double(Services::ConflictDetectionService) }
      let(:parsing_rule) { instance_double(ParsingRule) }
      let(:parsing_strategy) { instance_double(Services::EmailProcessing::Strategies::Regex) }
      let(:email_data) {
        {
          body: 'Transaction: $50.00 at Store ABC',
          date: Time.current,
          from: 'bank@bac.co.cr',
          subject: 'Transaction notification'
        }
      }

      before do
        allow(SyncSession).to receive_message_chain(:active, :last).and_return(sync_session)
        allow(ParsingRule).to receive_message_chain(:active, :for_bank, :first).and_return(parsing_rule)
        allow(Services::EmailProcessing::StrategyFactory).to receive(:create_strategy).and_return(parsing_strategy)
        allow(parsing_strategy).to receive(:parse_email).and_return({
          amount: 50.00,
          description: 'Store ABC',
          transaction_date: Time.current
        })
      end

      it 'passes metrics collector to Services::ConflictDetectionService' do
        expect(Services::ConflictDetectionService).to receive(:new).with(
          sync_session,
          metrics_collector: metrics_collector
        ).and_return(conflict_detector)

        allow(conflict_detector).to receive(:detect_conflict_for_expense).and_return(false)

        processor.send(:detect_and_handle_conflict, email_data)
      end

      it 'tracks conflict detection operations through the service' do
        allow(Services::ConflictDetectionService).to receive(:new).and_return(conflict_detector)

        expect(conflict_detector).to receive(:detect_conflict_for_expense).with(
          hash_including(
            amount: 50.00,
            description: 'Store ABC',
            email_account_id: email_account.id,
            raw_email_content: email_data[:body]
          )
        )

        processor.send(:detect_and_handle_conflict, email_data)
      end
    end

    describe 'performance metrics' do
      let(:large_message_set) { (1..100).to_a }

      before do
        large_message_set.each do |id|
          envelope = id.even? ?
            create_envelope('BAC - Notificación de transacción', 'bank@bac.co.cr') :
            create_envelope('Regular email', 'info@example.com')

          allow(mock_imap_service).to receive(:fetch_envelope).with(id).and_return(envelope)
        end

        allow(processor).to receive(:extract_email_data).and_return({ body: 'test' })
        allow(ProcessEmailJob).to receive(:perform_later)
      end

      it 'handles large batches with metrics tracking' do
        # Should track all emails (100), not just transaction emails
        # The metrics collector tracks the operation regardless of email type
        expect(metrics_collector).to receive(:track_operation).exactly(100).times.and_yield

        result = processor.process_emails(large_message_set, mock_imap_service)

        expect(result[:processed_count]).to eq(50)
        expect(result[:total_count]).to eq(100)
      end

      it 'includes timing information in metrics (simulated)' do
        start_time = Time.current

        allow(metrics_collector).to receive(:track_operation) do |op, account, metadata, &block|
          # Simulate timing measurement
          operation_start = Time.current
          result = block.call
          operation_duration = Time.current - operation_start

          expect(operation_duration).to be < 1.0 # Each operation should be fast
          result
        end

        processor.process_emails([ 1, 2, 3 ], mock_imap_service)

        total_duration = Time.current - start_time
        expect(total_duration).to be < 3.0 # Total should be reasonable
      end
    end

    describe 'error tracking with metrics' do
      context 'when IMAP operations fail' do
        before do
          error = create_imap_no_response_error('IMAP server error')
          allow(mock_imap_service).to receive(:fetch_envelope)
            .and_raise(error)
        end

        it 'tracks failed operations in metrics' do
          # Metrics collector should be called and yield to its block
          expect(metrics_collector).to receive(:track_operation).with(
            :parse_email,
            email_account,
            { message_id: 1 }
          ).and_yield

          allow(Rails.logger).to receive(:error)

          result = processor.process_emails([ 1 ], mock_imap_service)

          expect(result[:processed_count]).to eq(0)
          expect(processor.errors).not_to be_empty
        end
      end

      context 'when parsing fails' do
        before do
          allow(mock_imap_service).to receive(:fetch_envelope).and_return(
            create_envelope('BAC - Notificación de transacción', 'bank@bac.co.cr')
          )
          allow(processor).to receive(:extract_email_data).and_raise(
            Encoding::InvalidByteSequenceError, 'Invalid UTF-8'
          )
        end

        it 'captures parsing errors in metrics context' do
          # Metrics collector should yield and let the error be handled inside
          expect(metrics_collector).to receive(:track_operation).and_yield

          allow(Rails.logger).to receive(:error)

          processor.process_emails([ 1 ], mock_imap_service)
          expect(processor.errors.first).to include('Invalid UTF-8')
        end
      end
    end

    describe 'batch processing metrics' do
      it 'tracks batch-level metrics for entire process_emails call' do
        batch_metadata = {
          total_messages: 5,
          start_time: Time.current,
          email_account_id: email_account.id
        }

        # Simulate batch-level tracking
        processed_count = 0
        allow(metrics_collector).to receive(:track_operation) do |op, account, metadata, &block|
          result = block.call
          processed_count += 1 if op == :parse_email
          result
        end

        allow(processor).to receive(:extract_email_data).and_return({ body: 'test' })
        allow(ProcessEmailJob).to receive(:perform_later)

        result = processor.process_emails(message_ids, mock_imap_service)

        # Verify batch results align with metrics
        expect(processed_count).to be > 0
        expect(result[:total_count]).to eq(message_ids.length)
      end
    end
  end

  describe 'metrics collector absence handling' do
    let(:processor_no_metrics) { Services::EmailProcessing::Processor.new(email_account) }

    it 'gracefully handles nil metrics collector' do
      envelope = double('envelope',
        subject: 'BAC - Notificación de transacción',
        date: Time.current,
        from: [ double('from', mailbox: 'bank', host: 'bac.co.cr') ]
      )

      allow(mock_imap_service).to receive(:fetch_envelope).and_return(envelope)
      allow(processor_no_metrics).to receive(:extract_email_data).and_return({ body: 'test' })
      allow(ProcessEmailJob).to receive(:perform_later)

      expect {
        processor_no_metrics.process_emails([ 1 ], mock_imap_service)
      }.not_to raise_error
    end

    it 'processes emails normally without metrics' do
      envelope = double('envelope',
        subject: 'BAC - Notificación de transacción',
        date: Time.current,
        from: [ double('from', mailbox: 'bank', host: 'bac.co.cr') ]
      )

      allow(mock_imap_service).to receive(:fetch_envelope).and_return(envelope)
      allow(processor_no_metrics).to receive(:extract_email_data).and_return({ body: 'test' })
      allow(ProcessEmailJob).to receive(:perform_later)

      result = processor_no_metrics.process_emails([ 1 ], mock_imap_service)

      expect(result[:processed_count]).to eq(1)
      expect(result[:total_count]).to eq(1)
    end
  end
end
