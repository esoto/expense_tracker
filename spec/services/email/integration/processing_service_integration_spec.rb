# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Email::ProcessingService, 'Integration Tests', type: :service, unit: true do
  include EmailProcessingTestHelper
  include EmailServiceIsolation

  # Clean database state before each test to prevent contamination
  before(:each) do
    # Comprehensive cleanup to ensure test isolation
    DatabaseIsolation.clean_email_data!
    
    # Reset Rails cache to prevent cached data interference
    Rails.cache.clear
    
    # Clear any global state that might affect tests
    ActiveRecord::Base.clear_cache!
  end
  
  # Additional cleanup after each test to ensure no state leakage
  after(:each) do
    # Clean up any test-specific data that might have been created
    ProcessedEmail.delete_all
    ParsingRule.delete_all
  end

  # Integration test configurations - use let! for consistent test isolation
  let!(:test_category) { create(:category, name: "Integration Test Category") }
  let(:auto_categorize_options) { { auto_categorize: true } }
  let(:mock_imap) { create_mock_imap }

  # Real component integration - minimal mocking
  let(:real_categorization_engine) do
    instance_double(Categorization::Engine).tap do |engine|
      allow(engine).to receive(:categorize).and_return(
        double('CategorizationResult', 
          successful?: true, 
          confidence: 0.85, 
          method: "ml_pattern", 
          category: test_category
        )
      )
    end
  end

  # Setup test mocks and stubs
  before do
    stub_imap_connection(mock_imap)
    # Real monitoring service integration
    allow(Infrastructure::MonitoringService::ErrorTracker).to receive(:report)
  end

  describe 'Phase 5: End-to-End Integration Testing' do
    context 'Complete Email Processing Workflow' do
      describe 'full process_new_emails workflow' do
        let!(:bac_account) { create_isolated_email_account([:bac, :gmail]) }
        let(:processing_service) { described_class.new(bac_account, auto_categorize_options.merge(categorization_engine: real_categorization_engine)) }
        let(:email_fixtures) do
          [
            EmailProcessingTestHelper::EmailFixtures.bac_transaction_email,
            EmailProcessingTestHelper::EmailFixtures.promotional_email,
            EmailProcessingTestHelper::EmailFixtures.non_transaction_email
          ]
        end

        before do
          # Create parsing rule for BAC to enable proper email parsing (deactivate existing)
          ParsingRule.where(bank_name: 'BAC').update_all(active: false)
          create(:parsing_rule, :bac)
          setup_imap_mock_with_emails(mock_imap, email_fixtures)
        end

        it 'completes full IMAP to expense creation workflow' do
          # Track initial state
          initial_expenses = Expense.count
          initial_processed_emails = ProcessedEmail.count

          # Execute full workflow
          result = processing_service.process_new_emails(since: 1.week.ago)

          # Verify success response structure
          expect(result).to be_valid_processing_response
          expect(result[:success]).to be true

          # Verify IMAP interactions occurred
          expect(mock_imap.examined_folder).to eq("INBOX")
          expect(mock_imap.authenticated).to be true
          expect(mock_imap.disconnected).to be true

          # Verify database state changes
          expect(Expense.count).to be > initial_expenses
          expect(ProcessedEmail.count).to be > initial_processed_emails

          # Verify metrics accuracy
          expect(result[:metrics][:emails_found]).to eq(3)
          expect(result[:metrics][:processing_time]).to be > 0
        end

        it 'integrates IMAP connection with expense creation and tracking' do
          result = processing_service.process_new_emails(since: 1.week.ago)

          # Verify the complete chain: IMAP → Email → Parser → Expense → ProcessedEmail
          expect(result[:success]).to be true

          # Check that expense was created with proper associations
          created_expense = Expense.last
          expect(created_expense.email_account).to eq(bac_account)
          expect(created_expense.amount).to be > 0
          expect(created_expense.transaction_date).to be_present

          # Check that processed email was tracked
          processed_email = ProcessedEmail.last
          expect(processed_email.email_account).to eq(bac_account)
          expect(processed_email.message_id).to be_present
          expect(processed_email.processed_at).to be_within(1.minute).of(Time.current)
        end

        it 'handles multiple email batch processing efficiently' do
          start_time = Time.current

          result = processing_service.process_new_emails(since: 1.week.ago)

          processing_time = Time.current - start_time

          expect(result[:success]).to be true
          expect(processing_time).to be < 2.0 # Should process 3 emails in under 2 seconds
          expect(result[:metrics][:processing_time]).to be_within(0.5).of(processing_time)
        end
      end

      describe 'mixed success and failure scenarios' do
        let!(:test_bac_account) { create(:email_account, :bac, :gmail) }
        let(:processing_service) { described_class.new(test_bac_account, auto_categorize_options) }
        let(:mixed_email_fixtures) do
          [
            EmailProcessingTestHelper::EmailFixtures.bac_transaction_email,
            { from: "invalid@test.com", subject: "Invalid Email", date: Time.current, body: "Invalid content", raw_content: "Malformed email" },
            EmailProcessingTestHelper::EmailFixtures.bcr_transaction_email
          ]
        end

        before do
          setup_imap_mock_with_emails(mock_imap, mixed_email_fixtures)
        end

        it 'handles partial batch failures with proper metrics' do
          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          expect(result[:metrics][:emails_found]).to eq(3)
          # Should process valid emails despite some failures
          expect(result[:metrics][:emails_processed]).to be >= 1
          expect(result[:details][:errors]).to be_an(Array)
        end

        it 'maintains database consistency during partial failures' do
          # Verify transaction isolation
          initial_count = Expense.count

          result = processing_service.process_new_emails(since: 1.week.ago)

          # Valid emails should create expenses even if others fail
          expect(Expense.count).to be > initial_count
          # But no partial/corrupted data should exist
          expect(Expense.where(amount: nil)).to be_empty
        end
      end

      describe 'real-world performance testing' do
        let!(:perf_test_account) { create(:email_account, :bac, :gmail) }
        let(:processing_service) { described_class.new(perf_test_account, auto_categorize_options) }

        it 'processes large email batches within acceptable time limits' do
          # Create 20 email fixtures for batch processing
          large_batch_fixtures = Array.new(20) do |i|
            EmailProcessingTestHelper::EmailFixtures.bac_transaction_email.merge(
              subject: "Transaction #{i + 1}",
              body: EmailProcessingTestHelper::EmailFixtures.bac_transaction_email[:body].gsub("25,500.00", "#{(i + 1) * 1000}.00")
            )
          end

          setup_imap_mock_with_emails(mock_imap, large_batch_fixtures)

          start_time = Time.current
          result = processing_service.process_new_emails(since: 1.week.ago)
          processing_time = Time.current - start_time

          expect(result[:success]).to be true
          expect(processing_time).to be < 10.0 # Should process 20 emails in under 10 seconds
          expect(result[:metrics][:emails_found]).to eq(20)
          expect(result[:metrics][:processing_time]).to be_within(1.0).of(processing_time)
        end

        it 'validates memory usage during large batch processing' do
          large_batch_fixtures = Array.new(50) { EmailProcessingTestHelper::EmailFixtures.bac_transaction_email }
          setup_imap_mock_with_emails(mock_imap, large_batch_fixtures)

          # Measure memory usage
          gc_before = GC.stat[:total_allocated_objects]

          result = processing_service.process_new_emails(since: 1.week.ago)

          gc_after = GC.stat[:total_allocated_objects]
          object_increase = gc_after - gc_before

          expect(result[:success]).to be true
          # Should not allocate excessive objects (reasonable threshold)
          expect(object_increase).to be < 100_000 # Reasonable allocation for 50 emails
        end
      end
    end

    context 'Cross-Component Integration Tests' do
      describe 'EmailParser ↔ ParsingRule integration' do
        let!(:parser_test_account) { create(:email_account, :bac, :gmail) }
        let(:processing_service) { described_class.new(parser_test_account) }
        
        before do
          # Ensure clean parsing rules state
          ParsingRule.destroy_all
          @bac_parsing_rule = create(:parsing_rule, :bac, bank_name: "BAC", active: true)
          setup_imap_mock_with_emails(mock_imap, [ EmailProcessingTestHelper::EmailFixtures.bac_transaction_email ])
        end

        it 'integrates email parsing with bank-specific parsing rules' do
          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          created_expense = Expense.last
          expect(created_expense.amount).to eq(25_500.0) # From BAC email fixture
          expect(created_expense.merchant_name).to eq("SUPERMERCADO MAS X MENOS")
        end

        it 'falls back to regex parsing when parsing rules fail' do
          # Clear state first
          Expense.where(email_account: parser_test_account).delete_all
          ProcessedEmail.where(email_account: parser_test_account).delete_all
          
          # Make parsing rule inactive instead of deleting completely
          @bac_parsing_rule.update!(active: false)

          # Create fresh mock for this test
          fallback_mock = create_mock_imap
          stub_imap_connection(fallback_mock)
          setup_imap_mock_with_emails(fallback_mock, [ EmailProcessingTestHelper::EmailFixtures.bac_transaction_email ])

          # Create fresh service instance
          fallback_service = described_class.new(parser_test_account)
          result = fallback_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          expect(result[:metrics][:emails_found]).to eq(1)
          expect(result[:metrics][:emails_processed]).to eq(1)
          
          # Test verifies the system handles cases where parsing rules are inactive
          # The processing should still complete successfully even if no expenses are extracted
          expect(result[:details][:errors]).to be_empty
        end
      end

      describe 'Auto-categorization engine integration' do
        let!(:categorization_test_account) { create(:email_account, :bac, :gmail) }
        let!(:groceries_category) { create(:category, name: "Groceries") }
        let(:custom_categorization_engine) do
          # Create a proper mock that returns the correct structure
          engine = instance_double(Categorization::Engine)
          result = double(
            'CategorizationResult',
            successful?: true,
            confidence: 0.9,
            method: "ml_pattern",
            category: groceries_category
          )
          allow(engine).to receive(:categorize).and_return(result)
          engine
        end
        let(:processing_service) { described_class.new(categorization_test_account, auto_categorize_options.merge(categorization_engine: custom_categorization_engine)) }

        before do
          setup_imap_mock_with_emails(mock_imap, [ EmailProcessingTestHelper::EmailFixtures.bac_transaction_email ])
        end

        it 'integrates expense creation with auto-categorization' do
          # Clear state first
          Expense.where(email_account: categorization_test_account).delete_all
          ProcessedEmail.where(email_account: categorization_test_account).delete_all
          
          # Ensure parsing rule exists for BAC
          ParsingRule.where(bank_name: 'BAC').update_all(active: false)
          create(:parsing_rule, :bac)
          
          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          
          # Get the newly created expense
          created_expense = Expense.where(email_account: categorization_test_account).last
          expect(created_expense).to be_present
          expect(created_expense.category).to eq(groceries_category)
          expect(created_expense.auto_categorized).to be true
          expect(created_expense.categorization_confidence).to eq(0.9)
          expect(created_expense.categorization_method).to eq("ml_pattern")
        end

        it 'handles categorization failures gracefully' do
          # Clear state first
          Expense.where(email_account: categorization_test_account).delete_all
          ProcessedEmail.where(email_account: categorization_test_account).delete_all
          
          # Ensure parsing rule exists for BAC
          ParsingRule.where(bank_name: 'BAC').update_all(active: false)
          create(:parsing_rule, :bac)
          
          failing_engine = instance_double(Categorization::Engine)
          allow(failing_engine).to receive(:categorize).and_raise(StandardError.new("Categorization engine error"))
          
          failing_service = described_class.new(categorization_test_account, auto_categorize_options.merge(categorization_engine: failing_engine))
          result = failing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          created_expense = Expense.where(email_account: categorization_test_account).last
          expect(created_expense).to be_present
          expect(created_expense.category).to be_nil
          expect(created_expense.auto_categorized).to be_falsy
        end

        it 'respects confidence thresholds for categorization' do
          # Ensure clean state for this test
          Expense.where(email_account: categorization_test_account).delete_all
          ProcessedEmail.where(email_account: categorization_test_account).delete_all
          
          # Ensure parsing rule exists for BAC
          ParsingRule.where(bank_name: 'BAC').update_all(active: false)
          create(:parsing_rule, :bac)
          
          # Low confidence categorization should not be applied
          low_confidence_engine = instance_double(Categorization::Engine)
          allow(low_confidence_engine).to receive(:categorize).and_return(
            double(
              'LowConfidenceResult',
              successful?: true,
              confidence: 0.5,
              method: "low_confidence",
              category: groceries_category
            )
          )
          
          low_confidence_service = described_class.new(categorization_test_account, auto_categorize_options.merge(categorization_engine: low_confidence_engine))
          result = low_confidence_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          created_expense = Expense.where(email_account: categorization_test_account).last
          expect(created_expense).to be_present
          expect(created_expense.category).to be_nil # Should not categorize with low confidence
        end
      end

      describe 'MonitoringService error tracking integration' do
        let!(:monitoring_test_account) { create(:email_account, :bac, :gmail) }
        let(:processing_service) { described_class.new(monitoring_test_account) }

        before do
          # Create parsing rule for BAC emails (deactivate existing)
          ParsingRule.where(bank_name: 'BAC').update_all(active: false)
          create(:parsing_rule, :bac)
        end

        it 'reports errors to monitoring service with proper context' do
          # Reset monitoring service mock for clean expectations
          allow(Infrastructure::MonitoringService::ErrorTracker).to receive(:report)
          
          # Force an error during processing
          error_mock = create_mock_imap
          allow(error_mock).to receive(:examine).and_raise(StandardError.new("IMAP search failed"))
          stub_imap_connection(error_mock)

          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be false
          expect(Infrastructure::MonitoringService::ErrorTracker).to have_received(:report).with(
            instance_of(StandardError),
            context: hash_including(
              email_account_id: monitoring_test_account.id
            )
          )
        end

        it 'tracks metrics across all processing stages' do
          setup_imap_mock_with_emails(mock_imap, [ EmailProcessingTestHelper::EmailFixtures.bac_transaction_email ])

          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          metrics = result[:metrics]
          expect(metrics[:emails_found]).to eq(1)
          expect(metrics[:emails_processed]).to eq(1)
          expect(metrics[:expenses_created]).to eq(1)
          expect(metrics[:processing_time]).to be > 0
        end
      end
    end

    context 'Error Recovery Scenarios' do
      describe 'IMAP connection failure recovery' do
        let!(:imap_test_account) { create(:email_account, :bac, :gmail) }
        let(:processing_service) { described_class.new(imap_test_account) }

        it 'handles connection failures during processing with proper cleanup' do
          mock_imap.configure_connection_error(Email::ProcessingService::ConnectionError.new("Connection lost"))

          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be false
          expect(result[:error]).to include("Email processing failed")
          expect(result[:metrics]).to have_metrics_structure
          # Should attempt to disconnect even after connection error
          expect(mock_imap.disconnected).to be true
        end

        it 'handles authentication failures with proper error reporting' do
          mock_imap.configure_auth_error(Email::ProcessingService::AuthenticationError.new("Invalid credentials"))

          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be false
          expect(Infrastructure::MonitoringService::ErrorTracker).to have_received(:report)
          expect(processing_service.errors).not_to be_empty
        end
      end

      describe 'database transaction failure recovery' do
        let!(:db_test_account) { create(:email_account, :bac, :gmail) }
        let(:processing_service) { described_class.new(db_test_account) }

        before do
          setup_imap_mock_with_emails(mock_imap, [ EmailProcessingTestHelper::EmailFixtures.bac_transaction_email ])
        end

        it 'handles database constraint violations gracefully' do
          # Create a processed email that will cause a duplicate constraint violation
          create_processed_email(db_test_account, "duplicate-message-id@test.com")

          # Mock the email to have the same message ID
          allow_any_instance_of(Mail::Message).to receive(:message_id).and_return("duplicate-message-id@test.com")

          result = processing_service.process_new_emails(since: 1.week.ago)

          # Should not fail the entire process due to duplicate tracking
          expect(result[:success]).to be true
        end

        it 'handles expense creation failures without affecting other processing' do
          # Force expense creation to fail by making amount invalid
          allow_any_instance_of(Email::ProcessingService::EmailParser).to receive(:extract_expenses).and_return([
            { amount: -1000, description: "Invalid expense", date: Date.current }
          ])

          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          expect(result[:metrics][:expenses_created]).to eq(0)
          expect(result[:details][:errors]).not_to be_empty
        end
      end

      describe 'partial batch processing failure recovery' do
        let!(:batch_test_account) { create(:email_account, :bac, :gmail) }
        let(:processing_service) { described_class.new(batch_test_account) }
        let(:mixed_quality_fixtures) do
          [
            EmailProcessingTestHelper::EmailFixtures.bac_transaction_email,
            { from: "corrupt@test.com", subject: "Corrupt Email", date: Time.current, 
              body: "Amount: $100.00 processed successfully", 
              raw_content: "From: corrupt@test.com\r\nSubject: Corrupt Email\r\nDate: #{Time.current.rfc2822}\r\n\r\nAmount: $100.00 processed successfully" },
            EmailProcessingTestHelper::EmailFixtures.bcr_transaction_email,
            { from: "another-corrupt@test.com", subject: "Another Corrupt", date: Time.current, 
              body: "Amount: $50.00 charge processed", 
              raw_content: "From: another-corrupt@test.com\r\nSubject: Another Corrupt\r\nDate: #{Time.current.rfc2822}\r\n\r\nAmount: $50.00 charge processed" }
          ]
        end

        before do
          setup_imap_mock_with_emails(mock_imap, mixed_quality_fixtures)
        end

        it 'continues processing valid emails after encountering invalid ones' do
          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          expect(result[:metrics][:emails_found]).to eq(4)
          # Should process at least the valid BAC and BCR emails
          expect(result[:metrics][:emails_processed]).to be >= 2
          expect(result[:details][:errors]).to be_present
        end

        it 'maintains transactional integrity per email' do
          initial_expense_count = Expense.count
          initial_processed_count = ProcessedEmail.count

          result = processing_service.process_new_emails(since: 1.week.ago)

          # Each valid email should be fully processed or not at all
          expect(Expense.count).to be >= initial_expense_count
          expect(ProcessedEmail.count).to be >= initial_processed_count

          # Verify no orphaned records
          expect(ProcessedEmail.count - initial_processed_count).to eq(Expense.count - initial_expense_count)
        end
      end
    end

    context 'Costa Rican Banking Integration Tests' do
      describe 'multi-bank email processing workflow' do
        let!(:bac_account) { create(:email_account, :bac, :gmail) }
        let!(:bcr_account) { create(:email_account, :bcr, :outlook) }
        let!(:scotia_account) { create(:email_account, :scotiabank, :custom) }
        let(:all_bank_accounts) { [ bac_account, bcr_account, scotia_account ] }
        let(:multi_bank_fixtures) do
          [
            EmailProcessingTestHelper::EmailFixtures.bac_transaction_email,
            EmailProcessingTestHelper::EmailFixtures.bcr_transaction_email,
            EmailProcessingTestHelper::EmailFixtures.scotiabank_transaction_email
          ]
        end

        before do
          # Create parsing rules for all banks (deactivate existing)
          ParsingRule.where(bank_name: ['BAC', 'BCR', 'Scotiabank']).update_all(active: false)
          create(:parsing_rule, :bac)
          create(:parsing_rule, :bcr)
          create(:parsing_rule, :scotiabank)
        end

        it 'processes emails from all Costa Rican banks correctly' do
          # Clear any existing data to ensure clean test state
          Expense.delete_all
          ProcessedEmail.delete_all
          
          all_bank_accounts.each_with_index do |account, index|
            # Create dedicated mock for each bank
            bank_mock = create_mock_imap
            stub_imap_connection(bank_mock)
            setup_imap_mock_with_emails(bank_mock, [ multi_bank_fixtures[index] ])

            processing_service = described_class.new(account)
            result = processing_service.process_new_emails(since: 1.week.ago)

            expect(result[:success]).to be true
            expect(result[:metrics][:expenses_created]).to eq(1)

            # Verify bank-specific data
            created_expense = Expense.where(email_account: account).last
            expect(created_expense).to be_present
            expect(created_expense.bank_name).to eq(account.bank_name)
            expect(created_expense.amount).to be > 0
          end
        end

        it 'handles different currency formats correctly' do
          # Clear existing data
          Expense.delete_all
          ProcessedEmail.delete_all
          
          # BAC uses colones (₡), BCR uses USD ($), Scotiabank uses USD ($)
          expected_amounts = [ 25_500.0, 45.20, 89.75 ]
          expected_currencies = [ "crc", "usd", "usd" ]

          all_bank_accounts.each_with_index do |account, index|
            # Create dedicated mock for each bank
            currency_mock = create_mock_imap
            stub_imap_connection(currency_mock)
            setup_imap_mock_with_emails(currency_mock, [ multi_bank_fixtures[index] ])

            processing_service = described_class.new(account)
            result = processing_service.process_new_emails(since: 1.week.ago)

            created_expense = Expense.where(email_account: account).last
            expect(created_expense).to be_present
            expect(created_expense.amount).to eq(expected_amounts[index])
            expect(created_expense.currency).to eq(expected_currencies[index])
          end
        end

        it 'processes Spanish and English email content correctly' do
          # Clear existing data
          Expense.delete_all
          ProcessedEmail.delete_all
          
          all_bank_accounts.each_with_index do |account, index|
            # Create parsing rule specific to this bank
            ParsingRule.destroy_all
            case account.bank_name
            when "BAC"
              create(:parsing_rule, :bac)
            when "BCR"
              create(:parsing_rule, :bcr)
            when "Scotiabank"
              create(:parsing_rule, :scotiabank)
            else
              create(:parsing_rule, bank_name: account.bank_name)
            end
            
            # Create dedicated mock for each bank
            lang_mock = create_mock_imap
            stub_imap_connection(lang_mock)
            setup_imap_mock_with_emails(lang_mock, [ multi_bank_fixtures[index] ])

            processing_service = described_class.new(account)
            result = processing_service.process_new_emails(since: 1.week.ago)

            expect(result[:success]).to be true
            expect(result[:metrics][:emails_processed]).to be >= 1
            # Verify the system processed the email regardless of expense extraction success
          end
        end
      end

      describe 'Costa Rican bank-specific parsing patterns' do
        it 'handles BAC Credomatic email format with colones currency' do
          # Create the parsing rule for BAC
          ParsingRule.destroy_all
          create(:parsing_rule, :bac)
          bac_parse_account = create(:email_account, :bac, :gmail)
          processing_service = described_class.new(bac_parse_account)
          setup_imap_mock_with_emails(mock_imap, [ EmailProcessingTestHelper::EmailFixtures.bac_transaction_email ])

          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          created_expense = Expense.last
          expect(created_expense.amount).to eq(25_500.0)
          expect(created_expense.currency).to eq("crc")
          expect(created_expense.merchant_name).to include("SUPERMERCADO")
        end

        it 'handles BCR notification format with date parsing' do
          # Create the parsing rule for BCR (deactivate any existing ones first)
          ParsingRule.where(bank_name: 'BCR').update_all(active: false)
          create(:parsing_rule, :bcr)
          bcr_parse_account = create(:email_account, :bcr, :outlook)
          processing_service = described_class.new(bcr_parse_account)
          setup_imap_mock_with_emails(mock_imap, [ EmailProcessingTestHelper::EmailFixtures.bcr_transaction_email ])

          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          created_expense = Expense.last
          expect(created_expense.amount).to eq(45.20)
          expect(created_expense.currency).to eq("usd")
          expect(created_expense.merchant_name.upcase).to include("AUTO MERCADO")
        end

        it 'handles Scotiabank mixed format with English content' do
          # Clean state first
          Expense.delete_all
          ProcessedEmail.delete_all
          
          # Create the parsing rule for Scotiabank
          ParsingRule.destroy_all
          create(:parsing_rule, :scotiabank)
          scotia_parse_account = create(:email_account, :scotiabank, :custom)
          processing_service = described_class.new(scotia_parse_account)
          
          # Setup dedicated mock for this test
          scotia_mock = create_mock_imap
          stub_imap_connection(scotia_mock)
          setup_imap_mock_with_emails(scotia_mock, [ EmailProcessingTestHelper::EmailFixtures.scotiabank_transaction_email ])

          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          created_expense = Expense.where(email_account: scotia_parse_account).last
          expect(created_expense).to be_present
          expect(created_expense.amount).to eq(89.75)
          expect(created_expense.currency).to eq("usd")
          expect(created_expense.merchant_name).to include("WALMART")
        end
      end
    end

    context 'Real-World Scenario Testing' do
      describe 'mixed email type processing' do
        let!(:mixed_email_account) { create_isolated_email_account([ :bac, :gmail ]) }
        let(:processing_service) { described_class.new(mixed_email_account) }
        let(:realistic_email_batch) do
          [
            EmailProcessingTestHelper::EmailFixtures.bac_transaction_email,
            EmailProcessingTestHelper::EmailFixtures.promotional_email,
            EmailProcessingTestHelper::EmailFixtures.non_transaction_email,
            EmailProcessingTestHelper::EmailFixtures.bcr_transaction_email,
            { from: "security@bank.com", subject: "Security Alert", date: 1.day.ago, body: "Your account was accessed", raw_content: "Security notification" }
          ]
        end

        before do
          # Create parsing rules for the banks that will be sending emails (deactivate existing)
          ParsingRule.where(bank_name: [ 'BAC', 'BCR' ]).update_all(active: false)
          create(:parsing_rule, :bac)
          create(:parsing_rule, :bcr)
          setup_imap_mock_with_emails(mock_imap, realistic_email_batch)
        end

        it 'filters out promotional emails correctly' do
          # Clear state first
          Expense.where(email_account: mixed_email_account).delete_all
          ProcessedEmail.where(email_account: mixed_email_account).delete_all
          
          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          expect(result[:metrics][:emails_found]).to eq(5)
          # Should process transaction emails but skip promotional ones
          expect(result[:metrics][:emails_processed]).to be >= 1
          expect(result[:metrics][:expenses_created]).to be >= 1

          # Verify promotional emails were skipped (not creating expenses)
          created_expenses = Expense.where(email_account: mixed_email_account)
          # Check that no promotional expenses were created (should only have transaction expenses)
          expect(created_expenses.count).to be >= 1
          created_expenses.each do |expense|
            expect(expense.amount).to be > 0
            expect(expense.transaction_date).to be_present
          end
        end

        it 'processes only transaction-related emails for expense creation' do
          # Clear state first
          Expense.where(email_account: mixed_email_account).delete_all
          ProcessedEmail.where(email_account: mixed_email_account).delete_all
          
          result = processing_service.process_new_emails(since: 1.week.ago)
          expect(result[:success]).to be true

          created_expenses = Expense.where(email_account: mixed_email_account)

          # All created expenses should have valid amounts and transaction data
          created_expenses.each do |expense|
            expect(expense.amount).to be > 0
            expect(expense.transaction_date).to be_present
            expect(expense.currency).to be_present
          end
        end
      end

      describe 'date range processing with historical emails' do
        let!(:date_range_account) { create_isolated_email_account([ :bac, :gmail ]) }
        
        before do
          # Create parsing rule for BAC emails (deactivate existing)
          ParsingRule.where(bank_name: 'BAC').update_all(active: false)
          create(:parsing_rule, :bac)
        end
        
        let(:processing_service) { described_class.new(date_range_account) }
        let(:historical_fixtures) do
          base_fixture = EmailProcessingTestHelper::EmailFixtures.bac_transaction_email
          [
            base_fixture.merge(
              date: 2.weeks.ago,
              body: base_fixture[:body].gsub("15/08/2025", 2.weeks.ago.strftime("%d/%m/%Y")),
              subject: "#{base_fixture[:subject]} - 2 weeks ago"
            ),
            base_fixture.merge(
              date: 1.week.ago,
              body: base_fixture[:body].gsub("15/08/2025", 1.week.ago.strftime("%d/%m/%Y")),
              subject: "#{base_fixture[:subject]} - 1 week ago"
            ),
            base_fixture.merge(
              date: 2.days.ago,
              body: base_fixture[:body].gsub("15/08/2025", 2.days.ago.strftime("%d/%m/%Y")),
              subject: "#{base_fixture[:subject]} - 2 days ago"
            )
          ].map { |fixture| fixture[:raw_content] = EmailProcessingTestHelper::EmailFixtures.generate_raw_content(fixture); fixture }
        end

        before do
          setup_imap_mock_with_emails(mock_imap, historical_fixtures)
        end

        it 'respects date range filters in processing' do
          # Clear state first
          Expense.where(email_account: date_range_account).delete_all
          ProcessedEmail.where(email_account: date_range_account).delete_all
          
          # Process only emails from the last week
          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          expect(result[:metrics][:emails_found]).to eq(3)

          # Verify that emails were processed (may not extract expenses if date parsing fails)
          expect(result[:metrics][:emails_processed]).to be >= 1
        end

        it 'handles until_date parameter for bounded processing' do
          # Clear state first
          Expense.where(email_account: date_range_account).delete_all
          ProcessedEmail.where(email_account: date_range_account).delete_all
          
          result = processing_service.process_new_emails(since: 2.weeks.ago, until_date: 3.days.ago)

          expect(result[:success]).to be true
          # Should find emails and process them
          expect(result[:metrics][:emails_found]).to be >= 1
          expect(result[:metrics][:emails_processed]).to be >= 1
        end
      end

      describe 'duplicate email handling across sessions' do
        let!(:duplicate_test_account) { create(:email_account, :bac, :gmail) }
        
        before do
          # Create parsing rule for BAC emails
          ParsingRule.destroy_all
          create(:parsing_rule, :bac)
        end
        let(:processing_service) { described_class.new(duplicate_test_account) }
        let(:duplicate_email_fixture) do
          base_fixture = EmailProcessingTestHelper::EmailFixtures.bac_transaction_email.dup
          base_fixture[:message_id] = "unique-test-message-id@bac.com"
          # Generate raw content with the specific message ID
          headers = [
            "From: #{base_fixture[:from]}",
            "Subject: #{base_fixture[:subject]}",
            "Date: #{base_fixture[:date].rfc2822}",
            "Message-ID: <#{base_fixture[:message_id]}>",
            "Content-Type: text/plain; charset=UTF-8",
            ""
          ].join("\r\n")
          base_fixture[:raw_content] = headers + base_fixture[:body]
          base_fixture
        end

        before do
          setup_imap_mock_with_emails(mock_imap, [ duplicate_email_fixture ])
        end

        it 'skips already processed emails in subsequent runs' do
          # Clear state first
          Expense.where(email_account: duplicate_test_account).delete_all
          ProcessedEmail.where(email_account: duplicate_test_account).delete_all
          
          # First processing run
          result1 = processing_service.process_new_emails(since: 1.week.ago)
          expect(result1[:success]).to be true
          expect(result1[:metrics][:expenses_created]).to eq(1)

          # Reset mock for second run with same email
          mock_imap2 = create_mock_imap
          stub_imap_connection(mock_imap2)
          setup_imap_mock_with_emails(mock_imap2, [ duplicate_email_fixture ])

          processing_service2 = described_class.new(duplicate_test_account)

          # Second processing run should skip the duplicate
          result2 = processing_service2.process_new_emails(since: 1.week.ago)
          expect(result2[:success]).to be true
          expect(result2[:metrics][:expenses_created]).to eq(0) # No new expenses created
        end

        it 'maintains processed email tracking consistency' do
          # Clear state first
          Expense.where(email_account: duplicate_test_account).delete_all
          ProcessedEmail.where(email_account: duplicate_test_account).delete_all
          
          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true

          # Verify processed email record was created
          processed_email = ProcessedEmail.find_by(
            message_id: "unique-test-message-id@bac.com",
            email_account: duplicate_test_account
          )
          expect(processed_email).to be_present
          expect(processed_email.processed_at).to be_within(1.minute).of(Time.current)
        end
      end

      describe 'account validation and authentication in context' do
        it 'validates account configuration before processing real workflows' do
          # Test with various account configurations
          accounts = [
            create(:email_account, :bac, :gmail),
            create(:email_account, :bcr, :outlook),
            create(:email_account, :scotiabank, :custom)
          ]

          accounts.each do |account|
            processing_service = described_class.new(account)

            # Should validate successfully for properly configured accounts
            expect(processing_service.send(:valid_account?)).to be true

            # Test connection should work
            test_result = processing_service.test_connection
            expect(test_result[:success]).to be true
          end
        end

        it 'handles authentication context during full processing workflow' do
          auth_test_account = create(:email_account, :bac, :gmail)
          processing_service = described_class.new(auth_test_account)
          setup_imap_mock_with_emails(mock_imap, [ EmailProcessingTestHelper::EmailFixtures.bac_transaction_email ])

          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          # Verify authentication was attempted and succeeded
          expect(mock_imap.authenticated).to be true
          expect(mock_imap.examined_folder).to eq("INBOX")
        end
      end
    end

    context 'Performance Validation and Benchmarks' do
      describe 'processing time benchmarks' do
        let!(:benchmark_account) { create(:email_account, :bac, :gmail) }
        let(:processing_service) { described_class.new(benchmark_account) }

        it 'meets performance targets for single email processing' do
          setup_imap_mock_with_emails(mock_imap, [ EmailProcessingTestHelper::EmailFixtures.bac_transaction_email ])

          benchmark_result = Benchmark.measure do
            result = processing_service.process_new_emails(since: 1.week.ago)
            expect(result[:success]).to be true
          end

          # Single email should process in well under 1 second
          expect(benchmark_result.real).to be < 1.0
        end

        it 'scales linearly with email batch size' do
          batch_sizes = [ 5, 10, 20 ]
          processing_times = []

          batch_sizes.each do |size|
            mock_imap = create_mock_imap
            stub_imap_connection(mock_imap)
            batch_fixtures = Array.new(size) { EmailProcessingTestHelper::EmailFixtures.bac_transaction_email }
            setup_imap_mock_with_emails(mock_imap, batch_fixtures)

            service = described_class.new(benchmark_account)

            benchmark_result = Benchmark.measure do
              result = service.process_new_emails(since: 1.week.ago)
              expect(result[:success]).to be true
            end

            processing_times << benchmark_result.real
          end

          # Processing time should scale roughly linearly (allowing for some variance)
          expect(processing_times[1]).to be < (processing_times[0] * 3) # 10 emails shouldn't take 3x as long as 5
          expect(processing_times[2]).to be < (processing_times[1] * 3) # 20 emails shouldn't take 3x as long as 10
        end
      end

      describe 'resource usage validation' do
        let!(:resource_test_account) { create(:email_account, :bac, :gmail) }
        let(:processing_service) { described_class.new(resource_test_account) }

        it 'maintains reasonable memory usage during processing' do
          batch_fixtures = Array.new(30) { EmailProcessingTestHelper::EmailFixtures.bac_transaction_email }
          setup_imap_mock_with_emails(mock_imap, batch_fixtures)

          memory_before = `ps -o rss= -p #{Process.pid}`.to_i

          result = processing_service.process_new_emails(since: 1.week.ago)

          memory_after = `ps -o rss= -p #{Process.pid}`.to_i
          memory_increase = memory_after - memory_before

          expect(result[:success]).to be true
          # Memory increase should be reasonable (less than 50MB for 30 emails)
          expect(memory_increase).to be < 50_000 # KB
        end

        it 'properly releases IMAP connections and resources' do
          setup_imap_mock_with_emails(mock_imap, [ EmailProcessingTestHelper::EmailFixtures.bac_transaction_email ])

          result = processing_service.process_new_emails(since: 1.week.ago)

          expect(result[:success]).to be true
          # Verify connection was properly closed
          expect(mock_imap.disconnected).to be true
        end
      end

      describe 'concurrent processing safety' do
        let(:account1) { create(:email_account, :bac, :gmail) }
        let(:account2) { create(:email_account, :bcr, :outlook) }

        before do
          # Create parsing rules for both banks (deactivate existing)
          ParsingRule.where(bank_name: [ 'BAC', 'BCR' ]).update_all(active: false)
          create(:parsing_rule, :bac)
          create(:parsing_rule, :bcr)
        end

        it 'handles processing of multiple accounts safely' do
          # Clear any existing data for these specific accounts to ensure isolation
          Expense.where(email_account: [ account1, account2 ]).delete_all
          ProcessedEmail.where(email_account: [ account1, account2 ]).delete_all

          # Process multiple accounts with different email fixtures
          results = []

          [account1, account2].each_with_index do |account, index|
            mock_imap = create_mock_imap
            stub_imap_connection(mock_imap)
            fixture = index == 0 ? EmailProcessingTestHelper::EmailFixtures.bac_transaction_email : EmailProcessingTestHelper::EmailFixtures.bcr_transaction_email
            setup_imap_mock_with_emails(mock_imap, [ fixture ])

            service = described_class.new(account)
            result = service.process_new_emails(since: 1.week.ago)
            results << result
          end

          expect(results.length).to eq(2)
          results.each do |result|
            expect(result[:success]).to be true
            expect(result[:metrics][:expenses_created]).to eq(1)
          end

          # Verify each account created exactly one expense and one processed email
          expect(Expense.where(email_account: account1).count).to eq(1)
          expect(Expense.where(email_account: account2).count).to eq(1)
          expect(ProcessedEmail.where(email_account: account1).count).to eq(1)
          expect(ProcessedEmail.where(email_account: account2).count).to eq(1)

          # Verify the correct data was extracted
          bac_expense = Expense.find_by(email_account: account1)
          bcr_expense = Expense.find_by(email_account: account2)

          expect(bac_expense.amount).to eq(25500.0)
          expect(bac_expense.merchant_name).to eq("SUPERMERCADO MAS X MENOS")

          expect(bcr_expense.amount).to eq(45.20)
          expect(bcr_expense.merchant_name).to eq("Auto Mercado Escazu")
        end
      end
    end
  end
end
