# frozen_string_literal: true

# Integration Test Configuration
# Ensures proper database isolation and predictable test data for integration tests

require 'database_cleaner/active_record'

RSpec.configure do |config|
  # Configure DatabaseCleaner for integration tests
  # Note: We don't load seeds here - categories persist from db:test:prepare
  # This avoids the overhead of loading seeds on every test run

  # For integration tests, use truncation to ensure complete isolation
  # This is slower but more reliable for integration tests
  config.before(:each, integration: true) do
    if defined?(DatabaseCleaner)
      DatabaseCleaner.strategy = :truncation, {
        except: %w[ar_internal_metadata schema_migrations categories]
      }
      DatabaseCleaner.start
    end
  end

  # Clean up after each integration test
  config.after(:each, integration: true) do
    DatabaseCleaner.clean if defined?(DatabaseCleaner)
  end

  # Helper method to ensure predictable test data
  config.before(:each, integration: true) do |_example|
    # Clear Rails cache to avoid stale data
    Rails.cache.clear if defined?(Rails.cache)

    # Reset any class-level caches that might affect tests
    if defined?(Categorization::PatternCache)
      Categorization::PatternCache.instance.clear if Categorization::PatternCache.instance.respond_to?(:clear)
    end
  end
end

# Integration Test Helpers
module IntegrationTestHelpers
  # Create predictable test data for integration tests
  def create_integration_email_account(provider: 'gmail', email: nil)
    email ||= case provider
              when 'gmail' then 'test@gmail.com'
              when 'outlook' then 'test@outlook.com'
              when 'custom' then 'test@custom.com'
              else "test@#{provider}.com"
              end

    FactoryBot.create(:email_account, provider: provider, email: email, bank_name: 'BAC')
  end

  # Ensure database is in expected state
  def ensure_clean_database(except: [])
    tables_to_check = %w[expenses email_accounts sync_sessions] - except

    tables_to_check.each do |table|
      model = table.classify.constantize rescue nil
      if model&.any?
        raise "Database not clean: #{table} has #{model.count} records"
      end
    end
  end

  # Debug helper for integration tests
  def debug_database_state
    puts "\n=== DATABASE STATE ==="
    puts "Expenses: #{Expense.count}"
    puts "EmailAccounts: #{EmailAccount.count}"
    puts "Categories: #{Category.count}"
    puts "SyncSessions: #{SyncSession.count if defined?(SyncSession)}"
    puts "==================\n"
  end
end

RSpec.configure do |config|
  config.include IntegrationTestHelpers, integration: true
end