require 'rails_helper'

RSpec.describe ProcessEmailJob, type: :job, unit: true do
  let(:job) { described_class.new }
  let(:email_account_id) { 123 }
  let(:email_account) { instance_double(EmailAccount, id: email_account_id, email: 'test@example.com', bank_name: 'Test Bank') }
  let(:email_data) do
    {
      body: 'Transaction notification: $100.00 at Store ABC',
      subject: 'Transaction Alert',
      from: 'bank@example.com',
      date: Time.current
    }
  end

  # Mock dependencies
  let(:parser) { instance_double(EmailProcessing::Parser) }
  let(:expense) { instance_double(Expense, id: 1, formatted_amount: '$100.00', amount: 100.0) }
  let(:sync_session) { instance_double(SyncSession) }
  let(:metrics_collector) { instance_double(SyncMetricsCollector) }

  before do
    # Stub Rails.logger to prevent actual logging
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:debug)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe '#perform' do
    context 'when email account exists' do
      before do
        allow(EmailAccount).to receive(:find_by).with(id: email_account_id).and_return(email_account)
      end

      context 'without active sync session' do
        before do
          allow(SyncSession).to receive_message_chain(:active, :last).and_return(nil)
        end

        context 'when parsing succeeds' do
          before do
            allow(EmailProcessing::Parser).to receive(:new).with(email_account, email_data).and_return(parser)
            allow(parser).to receive(:parse_expense).and_return(expense)
          end

          it 'processes the email successfully' do
            result = job.perform(email_account_id, email_data)
            expect(result).to eq(expense)
          end

          it 'creates a parser with correct parameters' do
            expect(EmailProcessing::Parser).to receive(:new).with(email_account, email_data).and_return(parser)
            job.perform(email_account_id, email_data)
          end

          it 'logs the processing start' do
            expect(Rails.logger).to receive(:info).with("Processing individual email for: test@example.com")
            job.perform(email_account_id, email_data)
          end

          it 'logs the email data in debug mode' do
            expect(Rails.logger).to receive(:debug).with("Email data: #{email_data.inspect}")
            job.perform(email_account_id, email_data)
          end

          it 'logs successful expense creation' do
            expect(Rails.logger).to receive(:info).with("Successfully created expense: 1 - $100.00")
            job.perform(email_account_id, email_data)
          end
        end

        context 'when parsing fails' do
          let(:parser_errors) { ['Amount not found', 'Invalid date format'] }

          before do
            allow(EmailProcessing::Parser).to receive(:new).with(email_account, email_data).and_return(parser)
            allow(parser).to receive(:parse_expense).and_return(nil)
            allow(parser).to receive(:errors).and_return(parser_errors)
            allow(job).to receive(:save_failed_parsing)
          end

          it 'returns nil when parsing fails' do
            result = job.perform(email_account_id, email_data)
            expect(result).to be_nil
          end

          it 'logs the parsing failure' do
            expect(Rails.logger).to receive(:warn).with("Failed to create expense from email: Amount not found, Invalid date format")
            job.perform(email_account_id, email_data)
          end

          it 'calls save_failed_parsing with correct parameters' do
            expect(job).to receive(:save_failed_parsing).with(email_account, email_data, parser_errors)
            job.perform(email_account_id, email_data)
          end
        end
      end

      context 'with active sync session' do
        before do
          allow(SyncSession).to receive_message_chain(:active, :last).and_return(sync_session)
          allow(SyncMetricsCollector).to receive(:new).with(sync_session).and_return(metrics_collector)
          allow(metrics_collector).to receive(:track_operation).and_yield
          allow(metrics_collector).to receive(:flush_buffer)
        end

        context 'when parsing succeeds' do
          before do
            allow(EmailProcessing::Parser).to receive(:new).with(email_account, email_data).and_return(parser)
            allow(parser).to receive(:parse_expense).and_return(expense)
          end

          it 'creates a metrics collector with the sync session' do
            expect(SyncMetricsCollector).to receive(:new).with(sync_session).and_return(metrics_collector)
            job.perform(email_account_id, email_data)
          end

          it 'tracks the operation with metrics collector' do
            expect(metrics_collector).to receive(:track_operation).with(
              :detect_expense,
              email_account,
              { email_subject: 'Transaction Alert' }
            ).and_yield
            job.perform(email_account_id, email_data)
          end

          it 'flushes the metrics buffer' do
            expect(metrics_collector).to receive(:flush_buffer)
            job.perform(email_account_id, email_data)
          end

          it 'processes the email within the tracked operation' do
            expect(EmailProcessing::Parser).to receive(:new).ordered
            expect(parser).to receive(:parse_expense).ordered
            job.perform(email_account_id, email_data)
          end
        end

        context 'when parsing fails' do
          let(:parser_errors) { ['Parsing error'] }

          before do
            allow(EmailProcessing::Parser).to receive(:new).with(email_account, email_data).and_return(parser)
            allow(parser).to receive(:parse_expense).and_return(nil)
            allow(parser).to receive(:errors).and_return(parser_errors)
            allow(job).to receive(:save_failed_parsing)
          end

          it 'still tracks the operation even when parsing fails' do
            expect(metrics_collector).to receive(:track_operation).and_yield
            expect(metrics_collector).to receive(:flush_buffer)
            job.perform(email_account_id, email_data)
          end
        end
      end
    end

    context 'when email account does not exist' do
      before do
        allow(EmailAccount).to receive(:find_by).with(id: email_account_id).and_return(nil)
      end

      it 'logs an error' do
        expect(Rails.logger).to receive(:error).with("EmailAccount not found: 123")
        job.perform(email_account_id, email_data)
      end

      it 'returns early without processing' do
        expect(EmailProcessing::Parser).not_to receive(:new)
        job.perform(email_account_id, email_data)
      end

      it 'does not create a metrics collector' do
        expect(SyncMetricsCollector).not_to receive(:new)
        job.perform(email_account_id, email_data)
      end
    end

    context 'with edge cases' do
      before do
        allow(EmailAccount).to receive(:find_by).with(id: email_account_id).and_return(email_account)
        allow(SyncSession).to receive_message_chain(:active, :last).and_return(nil)
      end

      context 'when email_data is nil' do
        it 'handles nil email_data gracefully' do
          allow(EmailProcessing::Parser).to receive(:new).with(email_account, nil).and_return(parser)
          allow(parser).to receive(:parse_expense).and_return(nil)
          allow(parser).to receive(:errors).and_return(['Invalid email data'])
          allow(job).to receive(:save_failed_parsing)

          expect { job.perform(email_account_id, nil) }.not_to raise_error
        end
      end

      context 'when email_data is empty hash' do
        it 'handles empty email_data gracefully' do
          allow(EmailProcessing::Parser).to receive(:new).with(email_account, {}).and_return(parser)
          allow(parser).to receive(:parse_expense).and_return(nil)
          allow(parser).to receive(:errors).and_return(['Empty email data'])
          allow(job).to receive(:save_failed_parsing)

          expect { job.perform(email_account_id, {}) }.not_to raise_error
        end
      end

      context 'when parser raises an exception' do
        it 'allows the exception to bubble up' do
          allow(EmailProcessing::Parser).to receive(:new).and_raise(StandardError, 'Parser initialization failed')

          expect { job.perform(email_account_id, email_data) }.to raise_error(StandardError, 'Parser initialization failed')
        end
      end
    end
  end

  describe '#save_failed_parsing' do
    let(:errors) { ['Amount not found', 'Date format invalid', 'Currency mismatch'] }
    let(:failed_email_data) do
      {
        body: 'Failed email content',
        subject: 'Failed subject',
        from: 'sender@example.com'
      }
    end
    let(:created_expense) { instance_double(Expense) }

    context 'with normal-sized email body' do
      before do
        allow(Expense).to receive(:create!).and_return(created_expense)
      end

      it 'creates a failed expense record' do
        expect(Expense).to receive(:create!).with(
          hash_including(
            email_account: email_account,
            amount: 0.01,
            merchant_name: nil,
            description: 'Failed to parse: Amount not found',
            status: 'failed',
            bank_name: 'Test Bank'
          )
        )

        job.send(:save_failed_parsing, email_account, failed_email_data, errors)
      end

      it 'stores the raw email content' do
        expect(Expense).to receive(:create!).with(
          hash_including(
            raw_email_content: 'Failed email content',
            email_body: 'Failed email content'
          )
        )

        job.send(:save_failed_parsing, email_account, failed_email_data, errors)
      end

      it 'stores parsed data with errors and metadata' do
        expect(Expense).to receive(:create!) do |args|
          parsed_data = JSON.parse(args[:parsed_data])
          expect(parsed_data['errors']).to eq(errors)
          expect(parsed_data['truncated']).to eq(false)
          expect(parsed_data['original_size']).to eq(20) # 'Failed email content'.bytesize
          created_expense
        end

        job.send(:save_failed_parsing, email_account, failed_email_data, errors)
      end

      it 'uses only the first error in the description' do
        expect(Expense).to receive(:create!).with(
          hash_including(description: 'Failed to parse: Amount not found')
        )

        job.send(:save_failed_parsing, email_account, failed_email_data, errors)
      end
    end

    context 'with large email body' do
      let(:large_body) { 'x' * 15_000 } # 15KB, exceeds TRUNCATE_SIZE (10KB)
      let(:large_email_data) { failed_email_data.merge(body: large_body) }

      before do
        allow(Expense).to receive(:create!).and_return(created_expense)
      end

      it 'truncates the email body to TRUNCATE_SIZE' do
        expect(Expense).to receive(:create!) do |args|
          expect(args[:raw_email_content].bytesize).to be <= 10_000 + 20 # TRUNCATE_SIZE + truncation message
          expect(args[:raw_email_content]).to end_with('... [truncated]')
          created_expense
        end

        job.send(:save_failed_parsing, email_account, large_email_data, errors)
      end

      it 'marks as truncated in parsed_data' do
        expect(Expense).to receive(:create!) do |args|
          parsed_data = JSON.parse(args[:parsed_data])
          expect(parsed_data['truncated']).to eq(true)
          expect(parsed_data['original_size']).to eq(15_000)
          created_expense
        end

        job.send(:save_failed_parsing, email_account, large_email_data, errors)
      end

      it 'preserves exactly TRUNCATE_SIZE bytes' do
        expect(Expense).to receive(:create!) do |args|
          truncated_content = args[:raw_email_content]
          # Remove the truncation message to check the actual content size
          actual_content = truncated_content.sub(/\n\.\.\. \[truncated\]$/, '')
          expect(actual_content.bytesize).to eq(10_000)
          created_expense
        end

        job.send(:save_failed_parsing, email_account, large_email_data, errors)
      end
    end

    context 'with edge cases in email body size' do
      context 'when body is exactly TRUNCATE_SIZE' do
        let(:exact_size_body) { 'x' * 10_000 }
        let(:exact_email_data) { failed_email_data.merge(body: exact_size_body) }

        before do
          allow(Expense).to receive(:create!).and_return(created_expense)
        end

        it 'does not truncate the body' do
          expect(Expense).to receive(:create!) do |args|
            expect(args[:raw_email_content]).to eq(exact_size_body)
            parsed_data = JSON.parse(args[:parsed_data])
            expect(parsed_data['truncated']).to eq(false)
            created_expense
          end

          job.send(:save_failed_parsing, email_account, exact_email_data, errors)
        end
      end

      context 'when body is one byte over TRUNCATE_SIZE' do
        let(:over_size_body) { 'x' * 10_001 }
        let(:over_email_data) { failed_email_data.merge(body: over_size_body) }

        before do
          allow(Expense).to receive(:create!).and_return(created_expense)
        end

        it 'truncates the body' do
          expect(Expense).to receive(:create!) do |args|
            expect(args[:raw_email_content]).to end_with('... [truncated]')
            parsed_data = JSON.parse(args[:parsed_data])
            expect(parsed_data['truncated']).to eq(true)
            created_expense
          end

          job.send(:save_failed_parsing, email_account, over_email_data, errors)
        end
      end
    end

    context 'when saving fails' do
      context 'with ActiveRecord::RecordInvalid' do
        before do
          allow(Expense).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
        end

        it 'logs the error' do
          expect(Rails.logger).to receive(:error).with(/Failed to save failed parsing record/)
          job.send(:save_failed_parsing, email_account, failed_email_data, errors)
        end

        it 'does not raise the exception' do
          expect { job.send(:save_failed_parsing, email_account, failed_email_data, errors) }.not_to raise_error
        end
      end

      context 'with StandardError' do
        before do
          allow(Expense).to receive(:create!).and_raise(StandardError, 'Database connection lost')
        end

        it 'logs the specific error message' do
          expect(Rails.logger).to receive(:error).with('Failed to save failed parsing record: Database connection lost')
          job.send(:save_failed_parsing, email_account, failed_email_data, errors)
        end

        it 'does not raise the exception' do
          expect { job.send(:save_failed_parsing, email_account, failed_email_data, errors) }.not_to raise_error
        end
      end
    end

    context 'with nil or missing data' do
      before do
        allow(Expense).to receive(:create!).and_return(created_expense)
      end

      context 'when email_data[:body] is nil' do
        let(:nil_body_data) { { body: nil, subject: 'Test' } }

        it 'handles nil body gracefully' do
          expect(Expense).to receive(:create!).with(
            hash_including(
              raw_email_content: '',
              email_body: ''
            )
          )

          job.send(:save_failed_parsing, email_account, nil_body_data, errors)
        end

        it 'stores correct metadata for nil body' do
          expect(Expense).to receive(:create!) do |args|
            parsed_data = JSON.parse(args[:parsed_data])
            expect(parsed_data['original_size']).to eq(0)
            expect(parsed_data['truncated']).to eq(false)
            created_expense
          end

          job.send(:save_failed_parsing, email_account, nil_body_data, errors)
        end
      end

      context 'when errors array is empty' do
        it 'handles empty errors array' do
          expect(Expense).to receive(:create!).with(
            hash_including(description: 'Failed to parse: ')
          )

          job.send(:save_failed_parsing, email_account, failed_email_data, [])
        end
      end

      context 'when email_account has nil bank_name' do
        let(:account_no_bank) { instance_double(EmailAccount, id: 1, email: 'test@example.com', bank_name: nil) }

        it 'handles nil bank_name' do
          expect(Expense).to receive(:create!).with(
            hash_including(bank_name: nil)
          )

          job.send(:save_failed_parsing, account_no_bank, failed_email_data, errors)
        end
      end
    end

    context 'with UTF-8 encoding issues' do
      let(:invalid_utf8_body) { "Valid text \xC3\x28 invalid UTF-8" }
      let(:utf8_email_data) { failed_email_data.merge(body: invalid_utf8_body) }

      before do
        allow(Expense).to receive(:create!).and_return(created_expense)
      end

      it 'handles invalid UTF-8 gracefully' do
        expect { job.send(:save_failed_parsing, email_account, utf8_email_data, errors) }.not_to raise_error
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

  describe 'constants' do
    it 'defines TRUNCATE_SIZE as 10_000' do
      expect(described_class::TRUNCATE_SIZE).to eq(10_000)
    end
  end
end