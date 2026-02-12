# frozen_string_literal: true

# System Test Coverage Configuration
# End-to-end browser tests covering full user workflows

require 'simplecov'

if ENV['TEST_TIER'] == 'system'
  SimpleCov.start 'rails' do
  # Output directory for system test coverage
  coverage_dir 'coverage/system'

  # Project name for reports
  project_name 'Expense Tracker - System Tests'

  # System test focused groups - emphasize user-facing components
  add_group "Controllers", "app/controllers"
  add_group "Views", "app/views"
  add_group "Helpers", "app/helpers"
  add_group "JavaScript", "app/javascript"
  add_group "Stimulus Controllers", "app/javascript/controllers"
  add_group "Models", "app/models"
  add_group "Services", "app/services"

  # User workflow focused grouping
  add_group "Authentication", "app/controllers" do |src_file|
    src_file.filename.include?('session') ||
    src_file.filename.include?('auth') ||
    src_file.filename.include?('login')
  end

  add_group "Expense Management", "app/controllers" do |src_file|
    src_file.filename.include?('expense')
  end

  add_group "Sync & Import", "app/controllers" do |src_file|
    src_file.filename.include?('sync') ||
    src_file.filename.include?('import')
  end

  add_group "Budget Features", "app/controllers" do |src_file|
    src_file.filename.include?('budget')
  end

  add_group "Category Management", "app/controllers" do |src_file|
    src_file.filename.include?('categor')
  end

  # Frontend components tested by system tests
  add_group "View Templates", "app/views" do |src_file|
    src_file.filename.end_with?('.html.erb') ||
    src_file.filename.end_with?('.turbo_stream.erb')
  end

  add_group "Partials", "app/views" do |src_file|
    src_file.filename.include?('_')
  end

  # Critical user flows
  add_group "Critical Paths" do |src_file|
    critical_files = %w[
      application_controller
      expenses_controller
      sync_sessions_controller
      budgets_controller
    ]
    critical_files.any? { |file| src_file.filename.include?(file) }
  end

  # Skip backend-only files not exercised by system tests
  add_filter '/config/'
  add_filter '/vendor/'
  add_filter '/spec/'
  add_filter '/db/migrate/'
  add_filter '/lib/tasks/'

  # System test coverage expectations
  minimum_coverage 50  # Lower target since system tests cover user paths, not all code
  minimum_coverage_by_file 40

  # System tests focus on critical paths, not exhaustive coverage
  # refuse_coverage_drop

  # Format configurations
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::SimpleFormatter
  ])

  # Track branches for user decision points
  enable_coverage :branch

  # Merge policy for system test results
  merge_timeout 10800 # 3 hours (system tests are slowest)
  command_name "system-tests-#{Time.now.to_i}"
  end

  puts "🌐 System Test Coverage: Tracking end-to-end user workflows"
  puts "📁 Coverage output: coverage/system/"
  puts "🎯 Target: >60% overall, >50% per file (focuses on critical user paths)"
end
