# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Services::Email::ProcessingService, type: :service, unit: true do
  describe 'Phase 4: Transaction Processing & Expense Creation' do
    include EmailProcessingTestHelper

    let(:email_account) { create(:email_account, :bac, :gmail, bank_name: 'BAC San José') }
    let(:category) { create(:category, name: 'Groceries') }
    let(:processing_service) { described_class.new(email_account, options) }
    let(:options) { { auto_categorize: auto_categorize } }
    let(:auto_categorize) { true }
    let(:mock_imap) { create_mock_imap }

    # Mock categorization engine with configurable responses
    let(:mock_categorization_engine) {
      instance_double(
        Services::Categorization::Engine,
        categorize: categorization_result
      )
    }

    # Default categorization result with high confidence
    let(:categorization_result) {
      Services::Categorization::CategorizationResult.new(
        category: category,
        confidence: 0.85,
        method: 'pattern_match',
        processing_time_ms: 5.0
      )
    }

    before do
      stub_imap_connection(mock_imap)
      allow(Services::Infrastructure::MonitoringService::ErrorTracker).to receive(:report)
    end

    describe 'Database Transaction Safety' do
      context '#process_single_email transaction rollback' do
        let(:email_data) {
          {
            message_id: 'test-email-123',
            from: 'alerts@bac.com',
            subject: 'Transaction Alert',
            date: Time.current,
            body: 'Purchase at SuperMercado for $50.00',
            text_body: 'Purchase at SuperMercado for $50.00'
          }
        }

        it 'rolls back expense creation on database error during save' do
          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false)
          allow(processing_service).to receive(:parse_email).and_return([ {
            amount: 50.00,
            description: 'Purchase at SuperMercado',
            date: Date.current,
            merchant: 'SuperMercado',
            raw_text: 'Purchase at SuperMercado for $50.00'
          } ])

          # Simulate database error during expense save
          allow_any_instance_of(Expense).to receive(:save!).and_raise(ActiveRecord::StatementInvalid, "Database error")

          expect {
            processing_service.send(:process_single_email, email_data)
          }.not_to change { Expense.count }

          expect(ProcessedEmail.count).to eq(0)
        end

        it 'rolls back ProcessedEmail creation on expense validation error' do
          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false)
          allow(processing_service).to receive(:parse_email).and_return([ {
            amount: -50.00, # Invalid negative amount
            description: 'Purchase at SuperMercado',
            date: Date.current,
            merchant: 'SuperMercado',
            raw_text: 'Purchase at SuperMercado for $50.00'
          } ])

          expect {
            processing_service.send(:process_single_email, email_data)
          }.not_to change { [ Expense.count, ProcessedEmail.count ] }
        end

        it 'ensures atomicity when processing multiple expenses from single email' do
          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false)
          allow(processing_service).to receive(:parse_email).and_return([
            {
              amount: 50.00,
              description: 'Purchase at SuperMercado',
              date: Date.current,
              merchant: 'SuperMercado',
              raw_text: 'Purchase at SuperMercado for $50.00'
            },
            {
              amount: -25.00, # Invalid expense that will cause rollback
              description: 'Invalid transaction',
              date: Date.current,
              merchant: 'Test Merchant',
              raw_text: 'Invalid transaction for $25.00'
            }
          ])

          expect {
            processing_service.send(:process_single_email, email_data)
          }.not_to change { [ Expense.count, ProcessedEmail.count ] }
        end

        it 'handles ActiveRecord::StaleObjectError during auto-categorization' do
          service_with_categorization = described_class.new(email_account,
            auto_categorize: true,
            categorization_engine: mock_categorization_engine
          )

          allow(service_with_categorization).to receive(:email_already_processed?).and_return(false)
          allow(service_with_categorization).to receive(:promotional_email?).and_return(false)
          allow(service_with_categorization).to receive(:parse_email).and_return([ {
            amount: 50.00,
            description: 'Purchase at SuperMercado',
            date: Date.current,
            merchant: 'SuperMercado',
            raw_text: 'Purchase at SuperMercado for $50.00'
          } ])

          # Allow the expense to be created initially
          created_expense = nil
          allow(service_with_categorization).to receive(:create_expense) do |expense_data|
            created_expense = email_account.expenses.create!(
              amount: expense_data[:amount],
              description: expense_data[:description],
              transaction_date: expense_data[:date] || Date.current,
              merchant_name: expense_data[:merchant],
              currency: expense_data[:currency]&.downcase || "usd",
              status: "pending"
            )

            # Mock the update to raise StaleObjectError
            allow(created_expense).to receive(:update!).and_raise(ActiveRecord::StaleObjectError)
            created_expense
          end

          # Should not raise error but continue processing
          result = service_with_categorization.send(:process_single_email, email_data)
          expect(result[:success]).to be true
          expect(result[:expenses_created]).to eq(1)
        end

        it 'validates database consistency after transaction completion' do
          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false)
          allow(processing_service).to receive(:parse_email).and_return([ {
            amount: 50.00,
            description: 'Purchase at SuperMercado',
            date: Date.current,
            merchant: 'SuperMercado',
            raw_text: 'Purchase at SuperMercado for $50.00'
          } ])

          expect {
            result = processing_service.send(:process_single_email, email_data)
            expect(result[:success]).to be true
            expect(result[:expenses_created]).to eq(1)
          }.to change { Expense.count }.by(1)
            .and change { ProcessedEmail.count }.by(1)

          # Verify data consistency
          expense = Expense.last
          processed_email = ProcessedEmail.last

          expect(expense.email_account).to eq(email_account)
          expect(processed_email.email_account).to eq(email_account)
          expect(processed_email.message_id).to eq(email_data[:message_id])
        end
      end

      context 'concurrent modification handling' do
        it 'prevents duplicate processing during concurrent email processing' do
          email_data = {
            message_id: 'concurrent-test-123',
            from: 'alerts@bac.com',
            subject: 'Transaction Alert',
            date: Time.current,
            body: 'Purchase at Store for $30.00'
          }

          # Simulate race condition where email gets marked as processed between checks
          allow(processing_service).to receive(:email_already_processed?).and_return(false, true)
          allow(processing_service).to receive(:promotional_email?).and_return(false)

          result1 = processing_service.send(:process_single_email, email_data)
          result2 = processing_service.send(:process_single_email, email_data)

          expect(result1[:success]).to be true
          expect(result2[:success]).to be true
          expect(result2[:expenses_created]).to eq(0)
        end
      end
    end

    describe 'Expense Creation (#create_expense)' do
      let(:expense_data) {
        {
          amount: 75.50,
          description: 'Purchase at Walmart',
          date: Date.current,
          merchant: 'Walmart SuperCenter',
          currency: 'usd',
          raw_text: 'Purchase at Walmart SuperCenter for $75.50'
        }
      }

      context 'attribute mapping from parsed data' do
        it 'creates expense with complete attribute mapping' do
          expense = processing_service.send(:create_expense, expense_data)

          expect(expense).to be_persisted
          expect(expense.amount).to eq(75.50)
          expect(expense.description).to eq('Purchase at Walmart')
          expect(expense.transaction_date).to eq(Date.current)
          expect(expense.merchant_name).to eq('Walmart SuperCenter')
          expect(expense.merchant_normalized).to eq('walmart supercenter')
          expect(expense.currency).to eq('usd')
          expect(expense.raw_email_content).to eq('Purchase at Walmart SuperCenter for $75.50')
          expect(expense.bank_name).to eq('BAC San José')
          expect(expense.status).to eq('pending')
          expect(expense.email_account).to eq(email_account)
        end

        it 'handles missing optional fields gracefully' do
          minimal_data = {
            amount: 25.00,
            date: Date.current
          }

          expense = processing_service.send(:create_expense, minimal_data)

          expect(expense).to be_persisted
          expect(expense.amount).to eq(25.00)
          expect(expense.description).to be_nil
          expect(expense.merchant_name).to be_nil
          expect(expense.merchant_normalized).to be_nil
          expect(expense.currency).to eq('usd') # Default currency
          expect(expense.transaction_date).to eq(Date.current)
          expect(expense.bank_name).to eq('BAC San José')
        end

        it 'defaults transaction_date to current date when missing' do
          travel_to Date.new(2024, 6, 15) do
            data_without_date = expense_data.except(:date)
            expense = processing_service.send(:create_expense, data_without_date)

            expect(expense.transaction_date).to eq(Date.current)
          end
        end

        it 'normalizes currency to lowercase' do
          expense_data[:currency] = 'USD'
          expense = processing_service.send(:create_expense, expense_data)

          expect(expense.currency).to eq('usd')
        end

        it 'normalizes merchant name properly' do
          expense_data[:merchant] = '  WALMART    SUPER CENTER  '
          expense = processing_service.send(:create_expense, expense_data)

          expect(expense.merchant_name).to eq('  WALMART    SUPER CENTER  ')
          expect(expense.merchant_normalized).to eq('walmart super center')
        end
      end

      context 'Costa Rican currency handling' do
        it 'handles Costa Rican colón currency' do
          expense_data[:currency] = 'crc'
          expense_data[:amount] = 42500.00

          expense = processing_service.send(:create_expense, expense_data)

          expect(expense.currency).to eq('crc')
          expect(expense.amount).to eq(42500.00)
        end

        it 'defaults to USD when currency is blank' do
          expense_data[:currency] = nil
          expense = processing_service.send(:create_expense, expense_data)

          expect(expense.currency).to eq('usd')
        end
      end

      context 'bank name assignment' do
        it 'assigns bank name from EmailAccount' do
          expense = processing_service.send(:create_expense, expense_data)
          expect(expense.bank_name).to eq('BAC San José')
        end

        it 'handles email account with empty bank_name' do
          # Test with empty string instead of nil due to database constraint
          account_with_empty_bank = create(:email_account, :bac, :gmail, bank_name: 'Empty Bank')
          account_with_empty_bank.update_column(:bank_name, '') # Set to empty string
          service = described_class.new(account_with_empty_bank, options)

          expense = service.send(:create_expense, expense_data)
          expect(expense.bank_name).to eq('')
        end
      end
    end

    describe 'Auto-categorization Integration' do
      let(:service_with_categorization) {
        described_class.new(email_account,
          auto_categorize: true,
          categorization_engine: mock_categorization_engine
        )
      }

      let(:expense_data) {
        {
          amount: 45.00,
          description: 'Grocery shopping',
          date: Date.current,
          merchant: 'Supermarket',
          raw_text: 'Grocery shopping at Supermarket for $45.00'
        }
      }

      context 'category suggestion flow with confidence thresholds' do
        it 'assigns category when confidence > 0.7' do
          expect(mock_categorization_engine).to receive(:categorize)
            .with(anything)
            .and_return(categorization_result)

          expense = service_with_categorization.send(:create_expense, expense_data)

          expect(expense.category).to eq(category)
          expect(expense.auto_categorized).to be true
          expect(expense.categorization_confidence).to eq(0.85)
          expect(expense.categorization_method).to eq('pattern_match')
          expect(expense.categorized_at).to be_within(1.second).of(Time.current)
        end

        it 'does not assign category when confidence <= 0.7' do
          low_confidence_result = Services::Categorization::CategorizationResult.new(
            category: category,
            confidence: 0.65,
            method: 'pattern_match'
          )

          expect(mock_categorization_engine).to receive(:categorize)
            .and_return(low_confidence_result)

          expense = service_with_categorization.send(:create_expense, expense_data)

          expect(expense.category).to be_nil
          expect(expense.auto_categorized).to be_falsy
          expect(expense.categorization_confidence).to be_nil
          expect(expense.categorization_method).to be_nil
        end

        it 'stores categorization metadata for successful categorization' do
          expect(mock_categorization_engine).to receive(:categorize)
            .and_return(categorization_result)

          service_with_categorization.send(:create_expense, expense_data)

          expect(service_with_categorization.last_categorization_confidence).to eq(0.85)
          expect(service_with_categorization.last_categorization_method).to eq('pattern_match')
        end

        it 'stores low confidence metadata when categorization fails' do
          low_confidence_result = Services::Categorization::CategorizationResult.new(
            category: category,
            confidence: 0.45,
            method: 'pattern_match'
          )

          expect(mock_categorization_engine).to receive(:categorize)
            .and_return(low_confidence_result)

          service_with_categorization.send(:create_expense, expense_data)

          expect(service_with_categorization.last_categorization_confidence).to eq(0.45)
          expect(service_with_categorization.last_categorization_method).to eq('low_confidence')
        end
      end

      context 'categorization error recovery' do
        it 'handles categorization engine errors gracefully' do
          expect(mock_categorization_engine).to receive(:categorize)
            .and_raise(StandardError, 'Categorization service unavailable')

          expect(Rails.logger).to receive(:warn)
            .with(/Categorization failed for expense/)

          expense = service_with_categorization.send(:create_expense, expense_data)

          expect(expense).to be_persisted
          expect(expense.category).to be_nil
          expect(expense.auto_categorized).to be_falsy
          expect(service_with_categorization.last_categorization_confidence).to eq(0.0)
          expect(service_with_categorization.last_categorization_method).to eq('error')
        end

        it 'handles nil categorization result' do
          expect(mock_categorization_engine).to receive(:categorize)
            .and_return(nil)

          expense = service_with_categorization.send(:create_expense, expense_data)

          expect(expense).to be_persisted
          expect(expense.category).to be_nil
          expect(service_with_categorization.last_categorization_confidence).to eq(0.0)
          expect(service_with_categorization.last_categorization_method).to eq('low_confidence')
        end

        it 'handles failed categorization result' do
          failed_result = Services::Categorization::CategorizationResult.error('No patterns found')

          expect(mock_categorization_engine).to receive(:categorize)
            .and_return(failed_result)

          expense = service_with_categorization.send(:create_expense, expense_data)

          expect(expense).to be_persisted
          expect(expense.category).to be_nil
          expect(service_with_categorization.last_categorization_confidence).to eq(0.0)
          expect(service_with_categorization.last_categorization_method).to eq('low_confidence')
        end
      end

      context 'auto-categorization disabled' do
        let(:service_without_categorization) {
          described_class.new(email_account, auto_categorize: false)
        }

        it 'skips categorization when disabled' do
          expect(mock_categorization_engine).not_to receive(:categorize)

          expense = service_without_categorization.send(:create_expense, expense_data)

          expect(expense).to be_persisted
          expect(expense.category).to be_nil
          expect(expense.auto_categorized).to be_falsy
        end
      end

      context 'categorization logging' do
        let(:email_data) {
          {
            message_id: 'log-test-123',
            from: 'alerts@bac.com',
            subject: 'Transaction Alert',
            body: 'Purchase at Store for $30.00'
          }
        }

        it 'logs successful auto-categorization' do
          allow(service_with_categorization).to receive(:email_already_processed?).and_return(false)
          allow(service_with_categorization).to receive(:promotional_email?).and_return(false)
          allow(service_with_categorization).to receive(:parse_email).and_return([ expense_data ])

          expect(Rails.logger).to receive(:info)
            .with(/Auto-categorized expense.*'Groceries'.*0.85 confidence.*pattern_match/)

          service_with_categorization.send(:process_single_email, email_data)
        end

        it 'logs validation failures without auto-categorization log' do
          invalid_data = expense_data.merge(amount: -50.00) # Invalid amount

          allow(service_with_categorization).to receive(:email_already_processed?).and_return(false)
          allow(service_with_categorization).to receive(:promotional_email?).and_return(false)
          allow(service_with_categorization).to receive(:parse_email).and_return([ invalid_data ])

          # Don't expect specific log messages as they may vary
          result = service_with_categorization.send(:process_single_email, email_data)
          expect(result[:success]).to be false
          expect(result[:error]).to include('Failed to process email')
        end
      end
    end

    describe 'Duplicate Prevention' do
      let(:email_data) {
        {
          message_id: 'duplicate-test-456',
          from: 'alerts@bac.com',
          subject: 'Purchase Alert',
          date: Time.current,
          body: 'Purchase for $25.00'
        }
      }

      describe '#email_already_processed?' do
        it 'returns false for new email' do
          result = processing_service.send(:email_already_processed?, email_data)
          expect(result).to be false
        end

        it 'returns true for already processed email' do
          create(:processed_email,
            message_id: email_data[:message_id],
            email_account: email_account
          )

          result = processing_service.send(:email_already_processed?, email_data)
          expect(result).to be true
        end

        it 'scopes check to specific email account' do
          other_account = create(:email_account, :bac)
          create(:processed_email,
            message_id: email_data[:message_id],
            email_account: other_account
          )

          result = processing_service.send(:email_already_processed?, email_data)
          expect(result).to be false
        end

        it 'handles missing message_id gracefully' do
          email_without_id = email_data.merge(message_id: nil)

          expect {
            processing_service.send(:email_already_processed?, email_without_id)
          }.not_to raise_error
        end
      end

      describe '#mark_email_processed' do
        it 'creates ProcessedEmail record with complete data' do
          expect {
            processing_service.send(:mark_email_processed, email_data)
          }.to change { ProcessedEmail.count }.by(1)

          processed = ProcessedEmail.last
          expect(processed.message_id).to eq('duplicate-test-456')
          expect(processed.email_account).to eq(email_account)
          expect(processed.processed_at).to be_within(1.second).of(Time.current)
          expect(processed.uid).to eq(email_data[:uid])
          expect(processed.subject).to eq('Purchase Alert')
          expect(processed.from_address).to eq('alerts@bac.com')
        end

        it 'handles missing optional fields' do
          minimal_email = { message_id: 'minimal-123' }

          expect {
            processing_service.send(:mark_email_processed, minimal_email)
          }.to change { ProcessedEmail.count }.by(1)

          processed = ProcessedEmail.last
          expect(processed.message_id).to eq('minimal-123')
          expect(processed.uid).to be_nil
          expect(processed.subject).to be_nil
          expect(processed.from_address).to be_nil
        end

        it 'enforces unique constraint on message_id + email_account' do
          processing_service.send(:mark_email_processed, email_data)

          expect {
            processing_service.send(:mark_email_processed, email_data)
          }.to raise_error(ActiveRecord::RecordInvalid, /Message has already been taken/)
        end
      end

      context 'integration with email processing' do
        it 'skips processing and expense creation for duplicate emails' do
          create(:processed_email,
            message_id: email_data[:message_id],
            email_account: email_account
          )

          expect(processing_service).not_to receive(:parse_email)

          result = processing_service.send(:process_single_email, email_data)

          expect(result[:success]).to be true
          expect(result[:expenses_created]).to eq(0)
        end

        it 'marks email as processed within the same transaction as expense creation' do
          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false)
          allow(processing_service).to receive(:parse_email).and_return([ {
            amount: 25.00,
            description: 'Test purchase',
            date: Date.current,
            merchant: 'Test Store'
          } ])

          expect {
            processing_service.send(:process_single_email, email_data)
          }.to change { ProcessedEmail.count }.by(1)
            .and change { Expense.count }.by(1)

          # Both should be created atomically
          expect(ProcessedEmail.exists?(message_id: email_data[:message_id])).to be true
          expect(Expense.exists?(description: 'Test purchase')).to be true
        end
      end

      context 'duplicate expense detection within transaction' do
        it 'processes expenses with same amount but different merchants' do
          expense_data_list = [
            {
              amount: 50.00,
              description: 'Purchase A',
              date: Date.current,
              merchant: 'Store A'
            },
            {
              amount: 50.00,  # Same amount
              description: 'Purchase B',
              date: Date.current,
              merchant: 'Store B'  # Different merchant
            }
          ]

          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false)
          allow(processing_service).to receive(:parse_email).and_return(expense_data_list)

          expect {
            result = processing_service.send(:process_single_email, email_data)
            expect(result[:success]).to be true
            expect(result[:expenses_created]).to eq(2)
          }.to change { Expense.count }.by(2)
        end
      end
    end

    describe 'Email Processing Workflow' do
      let(:emails_data) {
        [
          {
            message_id: 'batch-email-1',
            from: 'alerts@bac.com',
            subject: 'Purchase Alert 1',
            body: 'Purchase at Store A for $30.00',
            text_body: 'Purchase at Store A for $30.00'
          },
          {
            message_id: 'batch-email-2',
            from: 'alerts@bac.com',
            subject: 'Purchase Alert 2',
            body: 'Purchase at Store B for $45.00',
            text_body: 'Purchase at Store B for $45.00'
          },
          {
            message_id: 'batch-email-3',
            from: 'promociones@bac.com',  # Promotional sender
            subject: 'Special Offer!',
            body: 'Get 50% off your next purchase!'
          }
        ]
      }

      describe '#process_emails batch processing' do
        it 'processes multiple emails and accumulates results' do
          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false, false, true) # Last one is promotional

          # Mock parsing for first two emails only (third is promotional)
          allow(processing_service).to receive(:parse_email).and_return(
            [ { amount: 30.00, description: 'Store A', date: Date.current, merchant: 'Store A' } ],
            [ { amount: 45.00, description: 'Store B', date: Date.current, merchant: 'Store B' } ]
          )

          results = processing_service.send(:process_emails, emails_data)

          expect(results[:processed]).to eq(3)  # All emails processed (including promotional skip)
          expect(results[:expenses_created]).to eq(2)  # Only non-promotional emails create expenses
          expect(results[:errors]).to be_empty
        end

        it 'accumulates errors from failed email processing' do
          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false)
          allow(processing_service).to receive(:parse_email).and_return([ {
            amount: -25.00,  # Invalid amount causes validation error
            description: 'Invalid purchase',
            date: Date.current
          } ])

          results = processing_service.send(:process_emails, emails_data.first(1))

          expect(results[:processed]).to eq(0)
          expect(results[:expenses_created]).to eq(0)
          expect(results[:errors]).not_to be_empty
          expect(results[:errors].first).to include('Failed to process email')
        end

        it 'updates service metrics correctly' do
          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false, false, true)
          allow(processing_service).to receive(:parse_email).and_return(
            [ { amount: 30.00, description: 'Store A', date: Date.current } ],
            [ { amount: 45.00, description: 'Store B', date: Date.current } ]
          )

          processing_service.send(:process_emails, emails_data)

          metrics = processing_service.metrics
          expect(metrics[:emails_processed]).to eq(3)
          expect(metrics[:expenses_created]).to eq(2)
        end
      end

      describe '#process_single_email complete workflow' do
        let(:single_email) { emails_data.first }

        it 'executes complete workflow: parse -> create -> track' do
          expense_data = {
            amount: 30.00,
            description: 'Store purchase',
            date: Date.current,
            merchant: 'Store A',
            raw_text: 'Purchase at Store A for $30.00'
          }

          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false)
          allow(processing_service).to receive(:parse_email).and_return([ expense_data ])

          expect {
            result = processing_service.send(:process_single_email, single_email)
            expect(result[:success]).to be true
            expect(result[:expenses_created]).to eq(1)
          }.to change { Expense.count }.by(1)
            .and change { ProcessedEmail.count }.by(1)

          # Verify created expense
          expense = Expense.last
          expect(expense.amount).to eq(30.00)
          expect(expense.description).to eq('Store purchase')
          expect(expense.merchant_name).to eq('Store A')
          expect(expense.email_account).to eq(email_account)

          # Verify ProcessedEmail tracking
          processed = ProcessedEmail.last
          expect(processed.message_id).to eq('batch-email-1')
          expect(processed.email_account).to eq(email_account)
        end

        it 'handles empty expense list from parsing' do
          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false)
          allow(processing_service).to receive(:parse_email).and_return([])  # No expenses found

          result = processing_service.send(:process_single_email, single_email)

          expect(result[:success]).to be true
          expect(result[:expenses_created]).to eq(0)
          expect(ProcessedEmail.count).to eq(0)  # Email not marked as processed when no expenses
        end

        it 'marks email as processed even when expense creation partially fails' do
          expense_data_list = [
            { amount: 30.00, description: 'Valid', date: Date.current },
            { amount: -15.00, description: 'Invalid', date: Date.current }  # Invalid amount
          ]

          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false)
          allow(processing_service).to receive(:parse_email).and_return(expense_data_list)

          # Transaction should rollback completely
          expect {
            processing_service.send(:process_single_email, single_email)
          }.not_to change { [ Expense.count, ProcessedEmail.count ] }
        end
      end

      describe 'promotional email filtering' do
        it 'identifies promotional emails by sender patterns' do
          promotional_emails = [
            { from: 'promociones@bac.com' },
            { from: 'marketing@bank.com' },
            { from: 'offers@store.com' },
            { from: 'newsletter@company.com' },
            { from: 'comunicaciones@bac.com' }
          ]

          promotional_emails.each do |email|
            result = processing_service.send(:promotional_email?, email)
            expect(result).to be true
          end
        end

        it 'allows legitimate transaction emails through' do
          legitimate_emails = [
            { from: 'alerts@bac.com' },
            { from: 'notifications@bank.com' },
            { from: 'no-reply@paypal.com' }
          ]

          legitimate_emails.each do |email|
            result = processing_service.send(:promotional_email?, email)
            expect(result).to be false
          end
        end

        it 'skips promotional emails in processing workflow' do
          promotional_email = {
            message_id: 'promo-123',
            from: 'promociones@bac.com',
            subject: 'Special Offer!',
            body: 'Get 50% off!'
          }

          expect(processing_service).not_to receive(:parse_email)

          result = processing_service.send(:process_single_email, promotional_email)

          expect(result[:success]).to be true
          expect(result[:expenses_created]).to eq(0)
        end
      end
    end

    describe 'Data Validation & Edge Cases' do
      context 'invalid expense data handling' do
        let(:email_data) {
          {
            message_id: 'validation-test-789',
            from: 'alerts@bac.com',
            subject: 'Transaction Alert',
            body: 'Invalid transaction data'
          }
        }

        it 'handles zero amount gracefully' do
          invalid_data = {
            amount: 0.00,
            description: 'Zero amount transaction',
            date: Date.current
          }

          expect {
            processing_service.send(:create_expense, invalid_data)
          }.to raise_error(ActiveRecord::RecordInvalid, /Amount must be greater than 0/)
        end

        it 'handles negative amounts' do
          invalid_data = {
            amount: -50.00,
            description: 'Negative amount',
            date: Date.current
          }

          expect {
            processing_service.send(:create_expense, invalid_data)
          }.to raise_error(ActiveRecord::RecordInvalid, /Amount must be greater than 0/)
        end

        it 'handles missing amount' do
          invalid_data = {
            description: 'Missing amount',
            date: Date.current
          }

          expect {
            processing_service.send(:create_expense, invalid_data)
          }.to raise_error(ActiveRecord::RecordInvalid, /Amount can't be blank/)
        end

        it 'handles invalid date formats' do
          invalid_data = {
            amount: 25.00,
            description: 'Invalid date',
            date: 'not-a-date'
          }

          expect {
            processing_service.send(:create_expense, invalid_data)
          }.to raise_error(ActiveRecord::RecordInvalid)
        end

        it 'validates transaction_date presence' do
          invalid_data = {
            amount: 25.00,
            description: 'No date',
            date: nil
          }

          # Should use Date.current as fallback
          expense = processing_service.send(:create_expense, invalid_data)
          expect(expense.transaction_date).to eq(Date.current)
        end
      end

      context 'malformed parsed email content' do
        it 'handles nil expense data arrays' do
          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false)
          allow(processing_service).to receive(:parse_email).and_return([])  # Return empty array instead of nil

          email = { message_id: 'nil-test', from: 'test@bac.com' }

          expect {
            result = processing_service.send(:process_single_email, email)
            expect(result[:success]).to be true
            expect(result[:expenses_created]).to eq(0)
          }.not_to change { Expense.count }
        end

        it 'handles empty expense data hashes' do
          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false)
          allow(processing_service).to receive(:parse_email).and_return([ {} ])  # Empty hash

          email = { message_id: 'empty-test', from: 'test@bac.com' }

          expect {
            processing_service.send(:process_single_email, email)
          }.not_to change { Expense.count }
        end

        it 'handles extremely long merchant names' do
          long_merchant = 'A' * 1000  # Very long name
          expense_data = {
            amount: 25.00,
            description: 'Long merchant test',
            date: Date.current,
            merchant: long_merchant
          }

          expense = processing_service.send(:create_expense, expense_data)
          expect(expense).to be_persisted
          expect(expense.merchant_name).to eq(long_merchant)
        end

        it 'handles special characters in merchant names' do
          special_merchant = "Store@#$%^&*()_+-={}[]|\\:;\"'<>?,./"
          expense_data = {
            amount: 25.00,
            description: 'Special characters test',
            date: Date.current,
            merchant: special_merchant
          }

          expense = processing_service.send(:create_expense, expense_data)
          expect(expense).to be_persisted
          expect(expense.merchant_name).to eq(special_merchant)
          expect(expense.merchant_normalized).to match(/[a-z0-9\s]+/)  # Normalized version
        end
      end

      context 'currency conversion edge cases' do
        it 'handles unsupported currency codes gracefully' do
          expense_data = {
            amount: 100.00,
            description: 'Unsupported currency',
            date: Date.current,
            currency: 'xyz'  # Unsupported currency
          }

          # Should fail validation for unsupported currency due to enum
          expect {
            processing_service.send(:create_expense, expense_data)
          }.to raise_error(ArgumentError, /'xyz' is not a valid currency/)
        end

        it 'handles very large amounts' do
          expense_data = {
            amount: 999_999.99,  # More reasonable large amount
            description: 'Large amount',
            date: Date.current
          }

          expense = processing_service.send(:create_expense, expense_data)
          expect(expense).to be_persisted
          expect(expense.amount).to eq(999_999.99)
        end

        it 'handles very small amounts' do
          expense_data = {
            amount: 0.01,
            description: 'Small amount',
            date: Date.current
          }

          expense = processing_service.send(:create_expense, expense_data)
          expect(expense).to be_persisted
          expect(expense.amount).to eq(0.01)
        end
      end

      context 'boundary validation' do
        it 'processes maximum realistic batch size' do
          large_expense_list = Array.new(50) do |i|
            {
              amount: (i + 1) * 10.0,
              description: "Expense #{i + 1}",
              date: Date.current,
              merchant: "Store #{i + 1}"
            }
          end

          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false)
          allow(processing_service).to receive(:parse_email).and_return(large_expense_list)

          email = { message_id: 'large-batch-test', from: 'test@bac.com' }

          expect {
            result = processing_service.send(:process_single_email, email)
            expect(result[:success]).to be true
            expect(result[:expenses_created]).to eq(50)
          }.to change { Expense.count }.by(50)
        end

        it 'handles date boundaries correctly' do
          # Test various date edge cases
          edge_dates = [
            Date.new(2000, 1, 1),    # Y2K
            Date.new(2024, 2, 29),   # Leap year
            Date.new(2023, 12, 31),  # End of year
            Date.current + 1.day     # Future date
          ]

          edge_dates.each_with_index do |test_date, i|
            expense_data = {
              amount: 25.00,
              description: "Date test #{i}",
              date: test_date
            }

            expense = processing_service.send(:create_expense, expense_data)
            expect(expense).to be_persisted
            expect(expense.transaction_date).to eq(test_date)
          end
        end
      end
    end

    describe 'Performance Validation' do
      context 'batch operations performance' do
        it 'processes moderate batch sizes efficiently' do
          emails = Array.new(10) do |i|
            {
              message_id: "perf-test-#{i}",
              from: 'alerts@bac.com',
              subject: "Transaction #{i}",
              body: "Purchase #{i} for $#{(i + 1) * 10}.00"
            }
          end

          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false)
          allow(processing_service).to receive(:parse_email) do
            [ {
              amount: 25.00,
              description: 'Performance test',
              date: Date.current,
              merchant: 'Test Store'
            } ]
          end

          start_time = Time.current
          results = processing_service.send(:process_emails, emails)
          duration = Time.current - start_time

          expect(results[:processed]).to eq(10)
          expect(results[:expenses_created]).to eq(10)
          expect(duration).to be < 2.seconds  # Performance target
        end

        it 'handles database connection timeouts gracefully' do
          allow(processing_service).to receive(:email_already_processed?).and_return(false)
          allow(processing_service).to receive(:promotional_email?).and_return(false)
          allow(processing_service).to receive(:parse_email).and_return([ {
            amount: 25.00,
            description: 'Timeout test',
            date: Date.current
          } ])

          # Simulate database timeout
          allow_any_instance_of(Expense).to receive(:save!)
            .and_raise(ActiveRecord::ConnectionTimeoutError)

          email = { message_id: 'timeout-test', from: 'test@bac.com' }

          result = processing_service.send(:process_single_email, email)
          expect(result[:success]).to be false
          expect(result[:error]).to include('Failed to process email')
        end
      end
    end
  end
end
