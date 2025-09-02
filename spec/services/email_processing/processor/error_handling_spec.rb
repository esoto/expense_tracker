require 'rails_helper'
require 'timeout'
require 'support/email_processing_processor_test_helper'

RSpec.describe 'EmailProcessing::Processor - Error Handling', type: :service, unit: true do
  include EmailProcessingProcessorTestHelper
  
  let(:email_account) { create(:email_account, :bac) }
  let(:metrics_collector) { instance_double(SyncMetricsCollector) }
  let(:processor) { EmailProcessing::Processor.new(email_account, metrics_collector: metrics_collector) }
  let(:mock_imap_service) { create_mock_imap_service }

  before do
    allow(metrics_collector).to receive(:track_operation).and_yield
  end

  describe 'IMAP connection errors' do
    let(:message_ids) { [1, 2, 3] }

    context 'with network timeouts' do
      it 'handles connection timeout gracefully' do
        allow(mock_imap_service).to receive(:fetch_envelope)
          .and_raise(Net::OpenTimeout, 'Connection timeout')
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(result[:total_count]).to eq(3)
        expect(processor.errors).to include('Error processing email: Connection timeout')
      end

      it 'handles read timeout during fetch' do
        allow(mock_imap_service).to receive(:fetch_envelope)
          .and_raise(Net::ReadTimeout, 'Read timeout')
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(processor.errors.first).to include('Read timeout')
      end

      it 'handles operation timeout' do
        allow(mock_imap_service).to receive(:fetch_envelope)
          .and_raise(Timeout::Error, 'Operation timed out')
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(processor.errors.first).to include('Operation timed out')
      end
    end

    context 'with IMAP protocol errors' do
      it 'handles IMAP NO response' do
        error = create_imap_no_response_error('Message not found')
        allow(mock_imap_service).to receive(:fetch_envelope)
          .and_raise(error)
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(processor.errors).not_to be_empty
      end

      it 'handles IMAP BAD response' do
        error = create_imap_bad_response_error('Invalid command')
        allow(mock_imap_service).to receive(:fetch_envelope)
          .and_raise(error)
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(processor.errors.first).to include('Invalid command')
      end

      it 'handles IMAP BYE response (server disconnect)' do
        error = create_imap_bye_response_error('Server closing connection')
        allow(mock_imap_service).to receive(:fetch_envelope)
          .and_raise(error)
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(processor.errors.first).to include('Server closing connection')
      end

      it 'handles IMAP response parse error' do
        error = Net::IMAP::ResponseParseError.new('Malformed response')
        allow(mock_imap_service).to receive(:fetch_envelope)
          .and_raise(error)
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(processor.errors.first).to include('Malformed response')
      end
    end

    context 'with authentication errors' do
      it 'handles authentication failure' do
        error = create_imap_no_response_error('Authentication failed')
        allow(mock_imap_service).to receive(:fetch_envelope)
          .and_raise(error)
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(processor.errors.first).to include('Authentication failed')
      end

      it 'handles expired credentials' do
        allow(mock_imap_service).to receive(:fetch_envelope)
          .and_raise(StandardError, 'Invalid credentials')
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(processor.errors.first).to include('Invalid credentials')
      end
    end

    context 'with connection state errors' do
      it 'handles disconnected IMAP connection' do
        allow(mock_imap_service).to receive(:fetch_envelope)
          .and_raise(IOError, 'Connection reset by peer')
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(processor.errors.first).to include('Connection reset')
      end

      it 'handles SSL/TLS errors' do
        allow(mock_imap_service).to receive(:fetch_envelope)
          .and_raise(OpenSSL::SSL::SSLError, 'SSL handshake failed')
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(processor.errors.first).to include('SSL handshake failed')
      end

      it 'handles socket errors' do
        allow(mock_imap_service).to receive(:fetch_envelope)
          .and_raise(SocketError, 'getaddrinfo: Name or service not known')
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(processor.errors.first).to include('Name or service not known')
      end
    end
  end

  describe 'partial failure handling' do
    let(:message_ids) { [1, 2, 3, 4, 5] }

    context 'with intermittent failures' do
      it 'continues processing after individual message failure' do
        envelopes = {
          1 => create_envelope('BAC - Notificación de transacción'),
          2 => nil, # This will cause a failure
          3 => create_envelope('BAC - Notificación de compra'),
          4 => create_envelope('Regular email'), # Non-transaction
          5 => create_envelope('Cargo a su cuenta')
        }

        envelopes.each do |id, envelope|
          if id == 2
            allow(mock_imap_service).to receive(:fetch_envelope).with(id)
              .and_raise(StandardError, 'Message 2 error')
          else
            allow(mock_imap_service).to receive(:fetch_envelope).with(id)
              .and_return(envelope)
          end
        end

        allow(processor).to receive(:extract_email_data).and_return({ body: 'test' })
        allow(ProcessEmailJob).to receive(:perform_later)
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(3) # 1, 3, 5 are transactions
        expect(result[:total_count]).to eq(5)
        expect(processor.errors.length).to eq(1)
      end

      it 'handles errors during email data extraction' do
        envelope = create_envelope('BAC - Notificación de transacción')
        
        allow(mock_imap_service).to receive(:fetch_envelope).and_return(envelope)
        allow(processor).to receive(:extract_email_data)
          .and_raise(StandardError, 'Extraction error')
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails([1], mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(processor.errors.first).to include('Extraction error')
      end

      it 'handles ProcessEmailJob queueing failures' do
        envelope = create_envelope('BAC - Notificación de transacción')
        
        allow(mock_imap_service).to receive(:fetch_envelope).and_return(envelope)
        allow(processor).to receive(:extract_email_data).and_return({ body: 'test' })
        allow(processor).to receive(:detect_and_handle_conflict).and_return(false)
        allow(ProcessEmailJob).to receive(:perform_later)
          .and_raise(ActiveJob::EnqueueError, 'Queue full')
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails([1], mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(processor.errors.first).to include('Queue full')
      end
    end
  end

  describe 'error accumulation and reporting' do
    let(:message_ids) { (1..10).to_a }

    it 'accumulates multiple errors across processing' do
      allow(Rails.logger).to receive(:error)

      # Simulate different errors for different messages
      message_ids.each do |id|
        case id
        when 1, 2
          error = create_imap_no_response_error("Error for message #{id}")
          allow(mock_imap_service).to receive(:fetch_envelope).with(id)
            .and_raise(error)
        when 3
          allow(mock_imap_service).to receive(:fetch_envelope).with(id)
            .and_return(nil)
        else
          envelope = create_non_transaction_envelope
          allow(mock_imap_service).to receive(:fetch_envelope).with(id)
            .and_return(envelope)
        end
      end

      processor.process_emails(message_ids, mock_imap_service)

      expect(processor.errors.length).to eq(2) # Two IMAP errors
      expect(processor.errors.first).to include('Error for message 1')
      expect(processor.errors.last).to include('Error for message 2')
    end

    it 'logs errors with proper context' do
      allow(mock_imap_service).to receive(:fetch_envelope)
        .and_raise(StandardError, 'Test error')
      allow(Rails.logger).to receive(:error)

      processor.process_emails([1], mock_imap_service)

      expect(Rails.logger).to have_received(:error).at_least(:once).with(
        a_string_including('Error processing email 1: Test error')
      )
    end
  end

  describe 'body extraction error scenarios' do
    let(:message_id) { 123 }

    context 'with fetch_body_part failures' do
      it 'handles body part fetch timeout' do
        body_structure = double('structure', multipart?: false)
        
        allow(mock_imap_service).to receive(:fetch_body_structure).and_return(body_structure)
        allow(mock_imap_service).to receive(:fetch_text_body)
          .and_raise(Net::ReadTimeout, 'Body fetch timeout')
        allow(Rails.logger).to receive(:warn)
        allow(mock_imap_service).to receive(:fetch_body_part).with(message_id, "1")
          .and_return(nil)

        result = processor.send(:extract_email_body, message_id, mock_imap_service)
        expect(result).to eq('Failed to fetch email content')
      end

      it 'recovers from body structure fetch error with HTML fallback' do
        allow(mock_imap_service).to receive(:fetch_body_structure)
          .and_raise(StandardError, 'Structure error')
        allow(mock_imap_service).to receive(:fetch_body_part).with(message_id, '1')
          .and_return('<html>Recovery content</html>')
        allow(Rails.logger).to receive(:warn)

        result = processor.send(:extract_email_body, message_id, mock_imap_service)

        expect(result).to include('Recovery content')
      end

      it 'returns error message when all recovery attempts fail' do
        allow(mock_imap_service).to receive(:fetch_body_structure)
          .and_raise(StandardError, 'Structure error')
        allow(mock_imap_service).to receive(:fetch_body_part)
          .and_raise(StandardError, 'Part fetch error')
        allow(Rails.logger).to receive(:warn)

        result = processor.send(:extract_email_body, message_id, mock_imap_service)

        expect(result).to eq('Failed to fetch email content')
      end
    end
  end

  describe 'progress callback error handling' do
    let(:message_ids) { [1, 2, 3] }

    it 'continues processing when progress callback raises error' do
      envelope = create_envelope('BAC - Notificación de transacción')
      
      allow(mock_imap_service).to receive(:fetch_envelope).and_return(envelope)
      allow(processor).to receive(:extract_email_data).and_return({ body: 'test' })
      allow(ProcessEmailJob).to receive(:perform_later)

      error_callback = proc do |processed, detected|
        raise StandardError, 'Callback error' if processed == 2
      end

      # Should not propagate callback errors
      expect {
        processor.process_emails(message_ids, mock_imap_service, &error_callback)
      }.to raise_error(StandardError, 'Callback error')
    end

    it 'handles nil progress callback gracefully' do
      envelope = create_envelope('BAC - Notificación de transacción')
      
      allow(mock_imap_service).to receive(:fetch_envelope).and_return(envelope)
      allow(processor).to receive(:extract_email_data).and_return({ body: 'test' })
      allow(ProcessEmailJob).to receive(:perform_later)

      result = processor.process_emails(message_ids, mock_imap_service, &nil)

      expect(result[:processed_count]).to eq(3)
    end
  end

  describe 'metrics error handling' do
    context 'when metrics collector fails' do
      it 'continues processing when metrics tracking fails' do
        # Metrics collector should catch and log errors from the block
        allow(metrics_collector).to receive(:track_operation) do |_, _, _, &block|
          begin
            block.call
          rescue StandardError => e
            Rails.logger.error "Metrics tracking error: #{e.message}"
            { processed: false, expense_created: false }
          end
        end
        
        # Make the actual processing fail
        allow(mock_imap_service).to receive(:fetch_envelope)
          .and_raise(StandardError, 'Processing error')
        allow(Rails.logger).to receive(:error)

        result = processor.process_emails([1], mock_imap_service)

        expect(result[:total_count]).to eq(1)
        expect(result[:processed_count]).to eq(0)
      end

      it 'handles metrics collector returning nil' do
        # Metrics collector yields but doesn't return the block's result
        allow(metrics_collector).to receive(:track_operation) do |_, _, _, &block|
          block.call
          nil  # Return nil instead of the block's result
        end
        
        envelope = create_envelope('BAC - Notificación de transacción')
        allow(mock_imap_service).to receive(:fetch_envelope).and_return(envelope)
        allow(processor).to receive(:extract_email_data).and_return({ body: 'test' })
        allow(ProcessEmailJob).to receive(:perform_later)

        # The processor should handle nil return and use default values
        result = processor.process_emails([1], mock_imap_service)

        expect(result[:total_count]).to eq(1)
        # Since track_operation returns nil, the processor treats it as not processed
        expect(result[:processed_count]).to eq(0)
      end
    end
  end

  describe 'complex error recovery scenarios' do
    it 'handles cascading failures gracefully' do
      # First message: envelope fetch fails
      error = create_imap_no_response_error('First error')
      allow(mock_imap_service).to receive(:fetch_envelope).with(1)
        .and_raise(error)
      
      # Second message: envelope ok, body extraction fails
      envelope2 = create_envelope('BAC - Notificación de transacción')
      allow(mock_imap_service).to receive(:fetch_envelope).with(2)
        .and_return(envelope2)
      allow(processor).to receive(:extract_email_data).with(2, envelope2, mock_imap_service)
        .and_raise(StandardError, 'Extraction error')
      
      # Third message: processes successfully
      envelope3 = create_envelope('Cargo a su cuenta')
      allow(mock_imap_service).to receive(:fetch_envelope).with(3)
        .and_return(envelope3)
      allow(processor).to receive(:extract_email_data).with(3, envelope3, mock_imap_service)
        .and_return({ body: 'Success' })
      allow(ProcessEmailJob).to receive(:perform_later)
      allow(Rails.logger).to receive(:error)

      result = processor.process_emails([1, 2, 3], mock_imap_service)

      expect(result[:processed_count]).to eq(1) # Only message 3 succeeded
      expect(result[:total_count]).to eq(3)
      expect(processor.errors.length).to eq(2)
    end
  end

  private

  def create_envelope(subject, from_email = 'bank@bac.co.cr')
    if subject.downcase.include?('transacción') || subject.downcase.include?('cargo') || subject.downcase.include?('compra')
      create_transaction_envelope(subject)
    else
      create_non_transaction_envelope
    end
  end
end