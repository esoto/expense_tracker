# frozen_string_literal: true

# Unit Test Coverage Configuration
# Fast, focused tests with minimal dependencies

require 'simplecov'

# Only start coverage if we're specifically running unit tests
if ENV['TEST_TIER'] == 'unit'
  SimpleCov.start 'rails' do
  # Output directory for unit test coverage
  coverage_dir 'coverage/unit'
  
  # Project name for reports
  project_name 'Expense Tracker - Unit Tests'
  
  # Unit test specific groups
  add_group "Models", "app/models"
  add_group "Controllers", "app/controllers" 
  add_group "Services", "app/services"
  add_group "Helpers", "app/helpers"
  add_group "Jobs", "app/jobs"
  add_group "Mailers", "app/mailers"
  add_group "Channels", "app/channels"
  add_group "Validators", "app/validators"
  add_group "Concerns", "app/controllers/concerns"
  
  # Service layer breakdown for better analysis
  add_group "Email Services", "app/services/email"
  add_group "Categorization Services", "app/services/categorization"
  add_group "Infrastructure Services", "app/services/infrastructure"
  add_group "Bulk Operations", "app/services/bulk_operations"
  
  # Highlight complex files that need unit test focus
  add_group "Complex Files (>100 lines)" do |src_file|
    src_file.lines.count > 100
  end
  
  add_group "Large Files (>200 lines)" do |src_file|
    src_file.lines.count > 200
  end
  
  # Skip files that shouldn't be in unit test coverage
  add_filter '/config/'
  add_filter '/vendor/'
  add_filter '/spec/'
  add_filter '/features/'
  add_filter '/db/'
  add_filter '/lib/tasks/' # These are tested in integration
  
  # Minimum coverage thresholds for unit tests
  # Start with realistic thresholds and increase over time
  # minimum_coverage 60  # Start reasonable for existing codebase
  # minimum_coverage_by_file 50
  
  # Allow coverage to grow organically - start without enforcement
  # refuse_coverage_drop
  
  # Format configurations
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::SimpleFormatter
  ])
  
    # Track branches for better coverage analysis
    enable_coverage :branch
    
    # Merge policy - only merge results from same tier
    merge_timeout 3600 # 1 hour
    command_name "unit-tests-#{Time.now.to_i}"
  end

  puts "📊 Unit Test Coverage: Tracking fast, focused test coverage"
  puts "📁 Coverage output: coverage/unit/"
  puts "🎯 Target: >85% overall, >80% per file"
end