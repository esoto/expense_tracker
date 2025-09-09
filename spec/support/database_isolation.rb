# frozen_string_literal: true

# Database Isolation Strategy for Test Suite
# Provides comprehensive database cleanup and isolation for different test types
module DatabaseIsolation
  # Models that need special cleanup ordering due to foreign key constraints
  CLEANUP_ORDER = [
    # Models with dependencies on other models (delete first)
    'PatternFeedback',
    'PatternLearningEvent',
    'BulkOperationItem',
    'ConflictResolution',
    'SyncConflict',
    'SyncMetric',
    'SyncSessionAccount',
    'SyncSession',
    'Expense',
    'ProcessedEmail',

    # Models with fewer dependencies (delete later)
    'EmailAccount',
    'Category',
    'ParsingRule',
    'CanonicalMerchant',
    'MerchantAlias',
    'UserCategoryPreference',
    'CategorizationPattern',
    'CompositePattern',
    'ExpensesMlConfidence',
    'Budget',
    'BulkOperation',
    'ApiToken',
    'AdminUser',
    'FailedBroadcastStore'
  ].freeze

  # Fast database cleanup for test isolation
  # Uses DELETE instead of TRUNCATE for better performance with transactional fixtures
  def self.clean_database!
    return unless Rails.env.test?

    ActiveRecord::Base.connection.execute('BEGIN')

    begin
      CLEANUP_ORDER.each do |model_name|
        if model_exists?(model_name)
          model_class = model_name.constantize
          model_class.delete_all
        end
      rescue NameError => e
        # Model doesn't exist, skip it
        Rails.logger.debug "Skipping cleanup for non-existent model: #{model_name}"
      end

      ActiveRecord::Base.connection.execute('COMMIT')
    rescue StandardError => e
      ActiveRecord::Base.connection.execute('ROLLBACK')
      raise e
    end
  end

  # Clean only email-related data for focused email service tests
  def self.clean_email_data!
    return unless Rails.env.test?

    # Use a more aggressive approach: disable foreign key checks temporarily
    connection = ActiveRecord::Base.connection

    if connection.adapter_name == 'PostgreSQL'
      # For PostgreSQL, use TRUNCATE CASCADE for efficiency
      tables_to_clean = %w[pattern_feedbacks pattern_learning_events processed_emails expenses email_accounts parsing_rules]

      existing_tables = tables_to_clean.select { |table| connection.table_exists?(table) }

      if existing_tables.any?
        begin
          connection.execute("TRUNCATE TABLE #{existing_tables.join(', ')} RESTART IDENTITY CASCADE")
        rescue ActiveRecord::StatementInvalid => e
          # Fallback to individual deletes if TRUNCATE fails
          Rails.logger.debug "TRUNCATE failed, falling back to DELETE: #{e.message}"
          existing_tables.reverse.each do |table|
            connection.execute("DELETE FROM #{table}")
          end
        end
      end
    else
      # Fallback for other database adapters
      email_cleanup_order = [
        'PatternFeedback', 'PatternLearningEvent', 'ProcessedEmail',
        'Expense', 'EmailAccount', 'ParsingRule'
      ]

      email_cleanup_order.each do |model_name|
        if model_exists?(model_name)
          model_class = model_name.constantize
          model_class.delete_all rescue nil
        end
      end
    end
  end

  # Reset auto-incrementing sequences to prevent ID conflicts
  def self.reset_sequences!
    return unless Rails.env.test?

    ActiveRecord::Base.connection.tables.each do |table|
      ActiveRecord::Base.connection.reset_pk_sequence!(table)
    end
  end

  private

  def self.model_exists?(model_name)
    model_name.constantize
    true
  rescue NameError
    false
  end
end

# Email Service Test Isolation
# Provides specific isolation strategies for email processing tests
module EmailServiceIsolation
  extend ActiveSupport::Concern

  included do
    # Use lighter-weight isolation that works with transactional fixtures
    before do
      # Clear Rails cache to prevent cached data interference
      Rails.cache.clear

      # Reset any stubbed/mocked services
      reset_service_mocks if respond_to?(:reset_service_mocks, true)
    end
  end

  private

  def reset_service_mocks
    # Reset monitoring service mocks
    allow(Infrastructure::MonitoringService::ErrorTracker).to receive(:report) if defined?(Infrastructure::MonitoringService::ErrorTracker)

    # Reset any other commonly stubbed services
    if defined?(Categorization::Engine)
      allow(Categorization::Engine).to receive(:create).and_call_original
    end
  end

  # Create isolated email account for test
  def create_isolated_email_account(traits = [], **attributes)
    # Ensure unique email to prevent conflicts
    unique_email = "test_#{SecureRandom.hex(8)}@#{SecureRandom.hex(4)}.com"

    default_attributes = {
      email: unique_email,
      provider: "gmail",
      bank_name: "BAC",
      active: true
    }

    create(:email_account, *traits, **default_attributes.merge(attributes))
  end

  # Create isolated parsing rule with unique bank name if needed
  def create_isolated_parsing_rule(bank_name, **attributes)
    # Instead of deleting, just deactivate existing rules for this bank
    ParsingRule.where(bank_name: bank_name).update_all(active: false)

    create(:parsing_rule, bank_name: bank_name, active: true, **attributes)
  end

  # Ensure test has clean email account state
  def with_clean_email_accounts(&block)
    # Store current count to verify cleanup
    initial_count = EmailAccount.count

    yield

    # Verify no email accounts leaked into other tests
    ensure
      # Clean up any accounts created during the test
      EmailAccount.where.not(id: EmailAccount.limit(initial_count).pluck(:id)).delete_all
  end
end

# Bank-Specific Test Isolation
# Handles bank-specific parsing rule conflicts
module BankSpecificIsolation
  extend ActiveSupport::Concern

  # Don't use automatic hooks - let tests control when to clean rules

  # Create bank-specific rule ensuring no conflicts
  def create_exclusive_parsing_rule(bank_name, **attributes)
    # First, disable any existing rules for this bank
    ParsingRule.where(bank_name: bank_name).update_all(active: false)

    # Create the new rule
    create(:parsing_rule, bank_name: bank_name, active: true, **attributes)
  end

  # Run test with specific bank configuration
  def with_bank_configuration(bank_name, &block)
    # Disable all rules except for specified bank
    ParsingRule.where.not(bank_name: bank_name).update_all(active: false)

    # Ensure bank has active rule
    rule = create_exclusive_parsing_rule(bank_name)

    yield rule
  ensure
    # Clean up after test
    ParsingRule.where(bank_name: bank_name).delete_all
  end
end
