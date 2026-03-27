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
      ar_internal_metadata schema_migrations categories admin_users
    ])
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end

  config.before(:each, type: :system) do
    DatabaseCleaner.strategy = :deletion
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  rescue StandardError, RSpec::Mocks::MockExpectationError
    # Silently ignore cleanup errors caused by tests that stub the connection pool
  end
end
