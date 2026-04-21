# frozen_string_literal: true

# Canonical DatabaseCleaner configuration.
# Replaces conflicting configs that were spread across 3 files.
#
# Strategy:
#   - Transaction for everything (fast, isolated)
#   - Deletion for system tests (browser needs committed data)
#   - Suite-level deletion excludes seed tables
RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.clean_with(:deletion, except: %w[
      ar_internal_metadata schema_migrations categories
    ])
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end

  config.before(:each, type: :system) do
    DatabaseCleaner.strategy = :deletion
  end

  # System tests need committed data visible to the browser thread
  config.before(:each, type: :system) do
    self.class.use_transactional_tests = false
  end

  config.after(:each, type: :system) do
    self.class.use_transactional_tests = true
  end

  # Performance tests may use before(:all) with persistent data
  config.before(:each, :performance) do
    DatabaseCleaner.strategy = :deletion
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  rescue StandardError, RSpec::Mocks::MockExpectationError
    # Tests that stub DB connections (health_controller, dashboard_helper) raise
    # StandardError during cleanup. RSpec mock errors need separate rescue since
    # MockExpectationError inherits from Exception, not StandardError.
  end
end
