require 'rails_helper'
require 'support/email_processing_processor_test_helper'

RSpec.describe 'EmailProcessing::Processor - Conflict Detection', type: :service, unit: true do
  include EmailProcessingProcessorTestHelper
  let(:email_account) { create(:email_account, :bac) }
  let(:metrics_collector) { instance_double(SyncMetricsCollector) }
  let(:processor) { EmailProcessing::Processor.new(email_account, metrics_collector: metrics_collector) }
  let(:mock_imap_service) { instance_double(ImapConnectionService) }

  describe '#detect_and_handle_conflict' do
    let(:sync_session) { instance_double(SyncSession, id: 1) }
    let(:conflict_detector) { instance_double(ConflictDetectionService) }
    let(:parsing_rule) { instance_double(ParsingRule) }
    let(:parsing_strategy) { instance_double(EmailProcessing::Strategies::Regex) }

    before do
      allow(ParsingRule).to receive_message_chain(:active, :for_bank, :first).and_return(parsing_rule)
      allow(EmailProcessing::StrategyFactory).to receive(:create_strategy).and_return(parsing_strategy)
      allow(metrics_collector).to receive(:track_operation).and_yield
    end

    describe 'edge cases and complex scenarios' do
      context 'with multiple concurrent sync sessions' do
        let(:sync_session1) { instance_double(SyncSession, id: 1) }
        let(:sync_session2) { instance_double(SyncSession, id: 2) }
        let(:active_sessions) { double('active_sessions') }

        before do
          allow(SyncSession).to receive(:active).and_return(active_sessions)
        end

        it 'uses the most recent active sync session' do
          allow(active_sessions).to receive(:last).and_return(sync_session2)
          
          expect(ConflictDetectionService).to receive(:new).with(
            sync_session2,
            metrics_collector: metrics_collector
          ).and_return(conflict_detector)

          allow(parsing_strategy).to receive(:parse_email).and_return({ amount: 100 })
          allow(conflict_detector).to receive(:detect_conflict_for_expense).and_return(false)

          email_data = { body: 'Transaction $100', date: Time.current }
          processor.send(:detect_and_handle_conflict, email_data)
        end

        it 'handles sync session switching during processing' do
          # Simulate session change between calls
          call_count = 0
          allow(active_sessions).to receive(:last) do
            call_count += 1
            call_count == 1 ? sync_session1 : sync_session2
          end

          allow(ConflictDetectionService).to receive(:new).and_return(conflict_detector)
          allow(parsing_strategy).to receive(:parse_email).and_return({ amount: 100 })
          allow(conflict_detector).to receive(:detect_conflict_for_expense).and_return(false)

          email_data = { body: 'Transaction $100', date: Time.current }
          
          # Process twice to simulate session change
          processor.send(:detect_and_handle_conflict, email_data)
          processor.send(:detect_and_handle_conflict, email_data)
        end
      end

      context 'with malformed expense data' do
        let(:email_data) { { body: 'Corrupted transaction data', date: nil } }

        before do
          allow(SyncSession).to receive_message_chain(:active, :last).and_return(sync_session)
        end

        it 'handles nil transaction date gracefully' do
          expense_data = { amount: 100, description: 'Purchase' }
          allow(parsing_strategy).to receive(:parse_email).and_return(expense_data)
          allow(ConflictDetectionService).to receive(:new).and_return(conflict_detector)
          allow(conflict_detector).to receive(:detect_conflict_for_expense)

          result = processor.send(:detect_and_handle_conflict, email_data)
          
          expect(conflict_detector).to have_received(:detect_conflict_for_expense).with(
            hash_including(
              amount: 100,
              description: 'Purchase',
              transaction_date: nil
            )
          )
        end

        it 'handles partial expense data from parser' do
          partial_data = { amount: nil, description: 'Unknown' }
          allow(parsing_strategy).to receive(:parse_email).and_return(partial_data)
          allow(ConflictDetectionService).to receive(:new).and_return(conflict_detector)
          allow(conflict_detector).to receive(:detect_conflict_for_expense).and_return(false)

          result = processor.send(:detect_and_handle_conflict, email_data)
          
          expect(result).to be false
        end

        it 'handles empty expense data hash' do
          allow(parsing_strategy).to receive(:parse_email).and_return({})
          # ConflictDetectionService should NOT be instantiated when there's no amount
          expect(ConflictDetectionService).not_to receive(:new)

          result = processor.send(:detect_and_handle_conflict, email_data)
          
          # Should return false when no amount present
          expect(result).to be false
        end
      end

      context 'with race conditions' do
        before do
          allow(SyncSession).to receive_message_chain(:active, :last).and_return(sync_session)
          allow(parsing_strategy).to receive(:parse_email).and_return({ amount: 100 })
        end

        it 'handles conflict detector initialization failure' do
          allow(ConflictDetectionService).to receive(:new)
            .and_raise(ActiveRecord::RecordNotFound, 'Session expired')
          allow(Rails.logger).to receive(:error)

          email_data = { body: 'Transaction', date: Time.current }
          
          expect(Rails.logger).to receive(:error).with(
            '[EmailProcessing::Processor] Error detecting conflict: Session expired'
          )

          result = processor.send(:detect_and_handle_conflict, email_data)
          expect(result).to be false
        end

        it 'handles conflict detection timeout' do
          allow(ConflictDetectionService).to receive(:new).and_return(conflict_detector)
          allow(conflict_detector).to receive(:detect_conflict_for_expense)
            .and_raise(Timeout::Error, 'Detection timeout')
          allow(Rails.logger).to receive(:error)

          email_data = { body: 'Transaction', date: Time.current }

          expect(Rails.logger).to receive(:error).with(
            '[EmailProcessing::Processor] Error detecting conflict: Detection timeout'
          )

          result = processor.send(:detect_and_handle_conflict, email_data)
          expect(result).to be false
        end
      end

      context 'with complex conflict scenarios' do
        let(:email_data) { 
          { 
            body: 'Transaction: $50.00 at Store XYZ on 2024-01-15',
            date: Time.parse('2024-01-15 10:00:00')
          }
        }
        let(:expense_data) {
          {
            amount: 50.00,
            description: 'Store XYZ',
            transaction_date: Time.parse('2024-01-15 10:00:00')
          }
        }

        before do
          allow(SyncSession).to receive_message_chain(:active, :last).and_return(sync_session)
          allow(parsing_strategy).to receive(:parse_email).and_return(expense_data)
          allow(ConflictDetectionService).to receive(:new).and_return(conflict_detector)
        end

        it 'detects exact duplicate transactions' do
          allow(conflict_detector).to receive(:detect_conflict_for_expense).and_return(true)

          result = processor.send(:detect_and_handle_conflict, email_data)
          
          expect(result).to be true
          expect(conflict_detector).to have_received(:detect_conflict_for_expense).with(
            hash_including(
              amount: 50.00,
              description: 'Store XYZ',
              email_account_id: email_account.id,
              raw_email_content: email_data[:body],
              transaction_date: email_data[:date]
            )
          )
        end

        it 'handles near-duplicate transactions' do
          # Simulate a near-duplicate (same amount, similar time)
          similar_expense_data = expense_data.merge(
            transaction_date: Time.parse('2024-01-15 10:01:00')
          )
          
          allow(parsing_strategy).to receive(:parse_email).and_return(similar_expense_data)
          allow(conflict_detector).to receive(:detect_conflict_for_expense).and_return(true)

          result = processor.send(:detect_and_handle_conflict, email_data)
          
          expect(result).to be true
        end

        it 'distinguishes between similar but distinct transactions' do
          allow(conflict_detector).to receive(:detect_conflict_for_expense).and_return(false)

          result = processor.send(:detect_and_handle_conflict, email_data)
          
          expect(result).to be false
        end
      end

      context 'with database connection issues' do
        let(:email_data) { { body: 'Transaction', date: Time.current } }

        before do
          allow(parsing_strategy).to receive(:parse_email).and_return({ amount: 100 })
        end

        it 'handles database connection errors during session lookup' do
          allow(SyncSession).to receive(:active)
            .and_raise(ActiveRecord::ConnectionNotEstablished, 'Database connection lost')
          allow(Rails.logger).to receive(:error)

          expect(Rails.logger).to receive(:error).with(
            '[EmailProcessing::Processor] Error detecting conflict: Database connection lost'
          )

          result = processor.send(:detect_and_handle_conflict, email_data)
          expect(result).to be false
        end

        it 'handles stale database connections' do
          stale_session = instance_double(SyncSession, id: 999)
          allow(SyncSession).to receive_message_chain(:active, :last).and_return(stale_session)
          
          allow(ConflictDetectionService).to receive(:new)
            .and_raise(ActiveRecord::StaleObjectError, 'Stale session')
          allow(Rails.logger).to receive(:error)

          result = processor.send(:detect_and_handle_conflict, email_data)
          
          expect(Rails.logger).to have_received(:error).with(
            a_string_including('[EmailProcessing::Processor] Error detecting conflict:')
          )
          expect(result).to be false
        end
      end

      context 'with parser edge cases' do
        let(:email_data) { { body: 'Transaction details', date: Time.current } }

        before do
          allow(SyncSession).to receive_message_chain(:active, :last).and_return(sync_session)
        end

        it 'handles parser returning nil gracefully' do
          allow(parsing_strategy).to receive(:parse_email).and_return(nil)

          result = processor.send(:detect_and_handle_conflict, email_data)
          
          expect(result).to be false
        end

        it 'handles parser raising encoding errors' do
          allow(parsing_strategy).to receive(:parse_email)
            .and_raise(Encoding::UndefinedConversionError, 'Invalid encoding')
          allow(Rails.logger).to receive(:error)

          expect(Rails.logger).to receive(:error).with(
            '[EmailProcessing::Processor] Error parsing email: Invalid encoding'
          )

          result = processor.send(:detect_and_handle_conflict, email_data)
          expect(result).to be false
        end

        it 'handles parser returning invalid data types' do
          allow(parsing_strategy).to receive(:parse_email).and_return('invalid_string')

          result = processor.send(:detect_and_handle_conflict, email_data)
          expect(result).to be false
        end
      end

      context 'with metrics collector integration' do
        let(:email_data) { { body: 'Transaction', date: Time.current } }

        before do
          allow(SyncSession).to receive_message_chain(:active, :last).and_return(sync_session)
          allow(parsing_strategy).to receive(:parse_email).and_return({ amount: 100 })
        end

        it 'passes metrics collector through to conflict detection service' do
          expect(ConflictDetectionService).to receive(:new).with(
            sync_session,
            metrics_collector: metrics_collector
          ).and_return(conflict_detector)

          allow(conflict_detector).to receive(:detect_conflict_for_expense).and_return(false)

          processor.send(:detect_and_handle_conflict, email_data)
        end

        it 'works without metrics collector' do
          processor_no_metrics = EmailProcessing::Processor.new(email_account)
          
          allow(ConflictDetectionService).to receive(:new).with(
            sync_session,
            metrics_collector: nil
          ).and_return(conflict_detector)

          allow(conflict_detector).to receive(:detect_conflict_for_expense).and_return(false)

          result = processor_no_metrics.send(:detect_and_handle_conflict, email_data)
          expect(result).to be false
        end
      end

      context 'with boundary conditions' do
        before do
          allow(parsing_strategy).to receive(:parse_email).and_return({ amount: 100 })
        end

        it 'handles extremely long email body content' do
          long_body = 'Transaction: ' + ('X' * 10_000)
          email_data = { body: long_body, date: Time.current }

          allow(SyncSession).to receive_message_chain(:active, :last).and_return(sync_session)
          allow(ConflictDetectionService).to receive(:new).and_return(conflict_detector)
          allow(conflict_detector).to receive(:detect_conflict_for_expense).and_return(false)

          result = processor.send(:detect_and_handle_conflict, email_data)
          
          expect(conflict_detector).to have_received(:detect_conflict_for_expense).with(
            hash_including(raw_email_content: long_body)
          )
        end

        it 'handles nil email body' do
          email_data = { body: nil, date: Time.current }

          allow(SyncSession).to receive_message_chain(:active, :last).and_return(sync_session)
          allow(ConflictDetectionService).to receive(:new).and_return(conflict_detector)
          allow(conflict_detector).to receive(:detect_conflict_for_expense).and_return(false)

          result = processor.send(:detect_and_handle_conflict, email_data)
          
          expect(conflict_detector).to have_received(:detect_conflict_for_expense).with(
            hash_including(raw_email_content: nil)
          )
        end

        it 'handles future-dated transactions' do
          future_date = Time.current + 1.year
          email_data = { body: 'Future transaction', date: future_date }

          allow(SyncSession).to receive_message_chain(:active, :last).and_return(sync_session)
          allow(ConflictDetectionService).to receive(:new).and_return(conflict_detector)
          allow(conflict_detector).to receive(:detect_conflict_for_expense).and_return(false)

          result = processor.send(:detect_and_handle_conflict, email_data)
          
          expect(conflict_detector).to have_received(:detect_conflict_for_expense).with(
            hash_including(transaction_date: future_date)
          )
        end
      end
    end
  end
end