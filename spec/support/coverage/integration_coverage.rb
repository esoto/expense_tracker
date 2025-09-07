# frozen_string_literal: true

# Integration Test Coverage Configuration
# Tests with database interactions and service integrations

require 'simplecov'

if ENV['TEST_TIER'] == 'integration'
  SimpleCov.start 'rails' do
  # Output directory for integration test coverage
  coverage_dir 'coverage/integration'

  # Project name for reports
  project_name 'Expense Tracker - Integration Tests'

  # Integration-focused groups
  add_group "Controllers", "app/controllers"
  add_group "Models", "app/models"
  add_group "Services", "app/services"
  add_group "Jobs", "app/jobs"
  add_group "Channels", "app/channels"
  add_group "Mailers", "app/mailers"

  # Integration-specific service analysis
  add_group "Email Processing", "app/services/email"
  add_group "Sync Services", "app/services/sync"
  add_group "Background Processing", "app/jobs"
  add_group "API Controllers", "app/controllers/api"
  add_group "Webhooks", "app/controllers/webhooks"

  # Database and persistence layer
  add_group "ActiveRecord Models", "app/models" do |src_file|
    src_file.filename.include?('/models/') && !src_file.filename.include?('/concerns/')
  end

  add_group "Model Concerns", "app/models/concerns"

  # Complex integrations that need thorough testing
  add_group "Service Orchestrators" do |src_file|
    src_file.filename.include?('orchestrator') ||
    src_file.filename.include?('coordinator') ||
    src_file.filename.include?('manager')
  end

  # External integrations
  add_group "External APIs" do |src_file|
    src_file.filename.include?('client') ||
    src_file.filename.include?('adapter') ||
    src_file.filename.include?('fetcher')
  end

  # Skip files not relevant for integration testing
  add_filter '/config/'
  add_filter '/vendor/'
  add_filter '/spec/'
  add_filter '/features/'
  add_filter '/app/assets/'
  add_filter '/app/views/' # Views tested in system tests

  # Integration test coverage thresholds
  minimum_coverage 75  # Lower than unit since integration tests are more selective
  minimum_coverage_by_file 70

  # Allow some coverage variance in integration tests
  refuse_coverage_drop

  # Format configurations
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::SimpleFormatter
  ])

  # Track branches for integration flows
  enable_coverage :branch

  # Merge policy for integration results
  merge_timeout 7200 # 2 hours (integration tests take longer)
  command_name "integration-tests-#{Time.now.to_i}"
  end

  puts "🔗 Integration Test Coverage: Tracking service interactions and database operations"
  puts "📁 Coverage output: coverage/integration/"
  puts "🎯 Target: >75% overall, >70% per file"
end
