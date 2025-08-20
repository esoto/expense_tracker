# frozen_string_literal: true

# Combined Coverage Configuration
# Merges and analyzes coverage from all test tiers

require 'simplecov'

if ENV['TEST_TIER'] == 'combined'
  SimpleCov.start 'rails' do
  # Output directory for combined coverage
  coverage_dir 'coverage/combined'

  # Project name for reports
  project_name 'Expense Tracker - Combined Coverage Analysis'

  # Comprehensive grouping for combined analysis
  add_group "Controllers", "app/controllers"
  add_group "Models", "app/models"
  add_group "Services", "app/services"
  add_group "Jobs", "app/jobs"
  add_group "Helpers", "app/helpers"
  add_group "Channels", "app/channels"
  add_group "Mailers", "app/mailers"
  add_group "Views", "app/views"
  add_group "JavaScript", "app/javascript"

  # Service layer breakdown
  add_group "Email Services", "app/services/email"
  add_group "Categorization Services", "app/services/categorization"
  add_group "Infrastructure Services", "app/services/infrastructure"
  add_group "Bulk Operations", "app/services/bulk_operations"
  add_group "Sync Services", "app/services/sync"

  # API and external interfaces
  add_group "API Controllers", "app/controllers/api"
  add_group "Webhooks", "app/controllers/webhooks"

  # Frontend components
  add_group "View Templates", "app/views"
  add_group "Stimulus Controllers", "app/javascript/controllers"

  # Coverage quality analysis
  add_group "Well Tested (>90%)" do |src_file|
    src_file.covered_percent > 90
  end

  add_group "Needs Attention (<70%)" do |src_file|
    src_file.covered_percent < 70
  end

  add_group "Critical Missing (<50%)" do |src_file|
    src_file.covered_percent < 50
  end

  # File complexity analysis
  add_group "Complex Files (>100 lines)" do |src_file|
    src_file.lines.count > 100
  end

  add_group "Large Files (>200 lines)" do |src_file|
    src_file.lines.count > 200
  end

  # Skip non-application files
  add_filter '/config/'
  add_filter '/vendor/'
  add_filter '/spec/'
  add_filter '/features/'
  add_filter '/db/'

  # Combined coverage expectations (highest since it includes all tests)
  minimum_coverage 90
  minimum_coverage_by_file 85

  # Enforce high standards for combined coverage
  refuse_coverage_drop

  # Enhanced formatting for combined reports
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::SimpleFormatter
  ])

  # Track branches for complete analysis
  enable_coverage :branch

  # Merge all test tier results
  merge_timeout 21600 # 6 hours
  command_name "combined-coverage-#{Time.now.to_i}"

    # Merge results from all test tiers
    SimpleCov.command_name 'Combined Test Suite'
  end

  puts "🎯 Combined Coverage: Merging results from all test tiers"
  puts "📁 Coverage output: coverage/combined/"
  puts "🎯 Target: >90% overall, >85% per file (comprehensive coverage across all test types)"
end
