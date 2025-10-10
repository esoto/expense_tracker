# frozen_string_literal: true

# This file contains fixes for the Services::Email::ProcessingService integration tests
# to resolve all 15 failing tests by addressing:
# 1. Auto-categorization engine injection issues
# 2. Multi-bank processing conflicts
# 3. Database state contamination
# 4. Complex error recovery scenarios

module IntegrationTestFixes
  # Custom test helper to ensure clean test isolation
  module TestIsolation
    def self.included(base)
      base.class_eval do
        # Ensure parsing rules don't accumulate
        before(:each) do
          ParsingRule.destroy_all
          ProcessedEmail.destroy_all
          Category.destroy_all
          Expense.destroy_all
        end

        # Create isolated email account without automatic associations
        def create_isolated_email_account(traits = [])
          account = FactoryBot.build(:email_account, *traits)
          account.save!(validate: false)
          account
        end

        # Create expense without automatic category assignment
        def build_expense_without_category(email_account, attributes = {})
          expense = email_account.expenses.build(
            amount: attributes[:amount] || 100.0,
            description: attributes[:description] || "Test expense",
            transaction_date: attributes[:transaction_date] || Date.current,
            merchant_name: attributes[:merchant_name] || "Test Merchant",
            merchant_normalized: attributes[:merchant_normalized] || "test merchant",
            currency: attributes[:currency] || "usd",
            status: attributes[:status] || "pending",
            bank_name: email_account.bank_name
          )
          expense.category = nil # Explicitly set to nil
          expense
        end
      end
    end
  end

  # Enhanced mock categorization engine with proper result handling
  class MockCategorizationEngine
    attr_reader :categorization_calls

    def initialize(category: nil, confidence: 0.9, method: "mock_engine", should_fail: false)
      @category = category
      @confidence = confidence
      @method = method
      @should_fail = should_fail
      @categorization_calls = []
    end

    def categorize(expense)
      @categorization_calls << expense

      if @should_fail
        raise StandardError, "Categorization engine error"
      end

      Result.new(
        successful: @category.present? && @confidence > 0.7,
        category: @category,
        confidence: @confidence,
        method: @method
      )
    end

    class Result
      attr_reader :category, :confidence, :method

      def initialize(successful:, category:, confidence:, method:)
        @successful = successful
        @category = category
        @confidence = confidence
        @method = method
      end

      def successful?
        @successful
      end
    end
  end

  # Fix for multi-bank processing conflicts
  class BankSpecificRuleManager
    def self.setup_for_bank(bank_name, exclusive: true)
      if exclusive
        # Deactivate all other bank rules to prevent conflicts
        ParsingRule.where.not(bank_name: bank_name).update_all(active: false)
      end

      # Ensure only one active rule per bank
      ParsingRule.where(bank_name: bank_name).where.not(id: ParsingRule.where(bank_name: bank_name).first&.id).destroy_all

      # Create or activate the rule for this bank
      rule = ParsingRule.find_or_create_by(bank_name: bank_name) do |r|
        r.pattern_type = "transaction"
        r.pattern = bank_specific_pattern(bank_name)
        r.active = true
        r.priority = 100
      end
      rule.update!(active: true)
      rule
    end

    def self.bank_specific_pattern(bank_name)
      case bank_name.upcase
      when 'BAC'
        '(?:Compra|Purchase).*?(?:por|for)\s+\$?([\d,]+(?:\.\d{2})?)'
      when 'BCR'
        'Transacción.*?Monto:\s*₡?([\d,]+(?:\.\d{2})?)'
      when 'BN'
        'Débito.*?₡?([\d,]+(?:\.\d{2})?)'
      when 'PROMERICA'
        'Transaction.*?\$?([\d,]+(?:\.\d{2})?)'
      when 'SCOTIABANK'
        '(?:Purchase|Compra).*?Amount:\s*\$?([\d,]+(?:\.\d{2})?)'
      else
        'Amount:\s*\$?([\d,]+(?:\.\d{2})?)'
      end
    end
  end

  # Enhanced email fixture management
  class EmailFixtureManager
    def self.create_date_ranged_fixtures(count: 5, start_date: 2.weeks.ago, end_date: Date.current)
      fixtures = []
      date_interval = (end_date - start_date) / count

      count.times do |i|
        email_date = start_date + (date_interval * i)
        fixtures << create_email_fixture(
          date: email_date,
          subject: "Transaction #{i + 1}",
          amount: 100.0 + (i * 10),
          merchant: "Merchant #{i + 1}"
        )
      end

      fixtures
    end

    def self.create_email_fixture(date:, subject:, amount:, merchant:)
      {
        raw_content: build_raw_email(date, subject, amount, merchant),
        date: date,
        amount: amount,
        merchant: merchant,
        subject: subject
      }
    end

    def self.build_raw_email(date, subject, amount, merchant)
      <<~EMAIL
        From: notifications@bank.com
        To: user@example.com
        Subject: #{subject}
        Date: #{date.rfc2822}

        Transaction notification:
        Merchant: #{merchant}
        Amount: $#{amount}
        Date: #{date.strftime('%Y-%m-%d')}

        Thank you for using our services.
      EMAIL
    end
  end

  # ProcessedEmail tracking helper
  class ProcessedEmailTracker
    def self.mark_as_processed(email_account, email_uid, processed_at = Time.current)
      ProcessedEmail.create!(
        email_account: email_account,
        email_uid: email_uid,
        processed_at: processed_at,
        message_id: "msg-#{email_uid}@test.com",
        subject: "Test Email #{email_uid}",
        from_address: "test@bank.com",
        email_date: processed_at
      )
    end

    def self.clear_all_for_account(email_account)
      ProcessedEmail.where(email_account: email_account).destroy_all
    end
  end

  # Error recovery test helper
  class ErrorRecoverySimulator
    def self.simulate_partial_batch_failure(mock_imap, success_count: 2, failure_count: 1)
      total_emails = success_count + failure_count
      email_fixtures = []

      # Create successful emails
      success_count.times do |i|
        email_fixtures << EmailFixtureManager.create_email_fixture(
          date: i.days.ago,
          subject: "Success Transaction #{i + 1}",
          amount: 100.0 + i,
          merchant: "Success Merchant #{i + 1}"
        )
      end

      # Create emails that will cause failures
      failure_count.times do |i|
        email_fixtures << {
          raw_content: "INVALID EMAIL CONTENT",
          should_fail: true
        }
      end

      setup_mock_imap_with_mixed_results(mock_imap, email_fixtures)
    end

    def self.setup_mock_imap_with_mixed_results(mock_imap, fixtures)
      message_ids = (1..fixtures.length).to_a
      allow(mock_imap).to receive(:search).and_return(message_ids)

      fetch_data = {}
      fixtures.each_with_index do |fixture, index|
        uid = index + 1
        if fixture[:should_fail]
          # This will cause parsing to fail
          fetch_data[uid] = { raw_content: fixture[:raw_content] }
        else
          fetch_data[uid] = { raw_content: fixture[:raw_content] }
        end
      end

      mock_imap.configure_fetch_results(message_ids, fetch_data)
    end
  end

  # Monitoring service mock helper
  class MonitoringServiceMocker
    def self.setup_mocks
      # Create proper test doubles for monitoring
      error_tracker = class_double("Services::Infrastructure::MonitoringService::ErrorTracker").as_stubbed_const
      allow(error_tracker).to receive(:report)

      metrics_tracker = class_double("Services::Infrastructure::MonitoringService::MetricsTracker").as_stubbed_const
      allow(metrics_tracker).to receive(:record)
      allow(metrics_tracker).to receive(:increment)

      health_checker = class_double("Services::Infrastructure::MonitoringService::HealthChecker").as_stubbed_const
      allow(health_checker).to receive(:check)

      {
        error_tracker: error_tracker,
        metrics_tracker: metrics_tracker,
        health_checker: health_checker
      }
    end
  end
end
