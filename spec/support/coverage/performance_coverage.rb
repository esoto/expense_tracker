# frozen_string_literal: true

# Performance Test Coverage Configuration
# Tests focused on performance bottlenecks and optimization

require 'simplecov'

if ENV['TEST_TIER'] == 'performance'
  SimpleCov.start 'rails' do
  # Output directory for performance test coverage
  coverage_dir 'coverage/performance'

  # Project name for reports
  project_name 'Expense Tracker - Performance Tests'

  # Performance-critical groups
  add_group "Database Operations", "app/models"
  add_group "Query Services", "app/services" do |src_file|
    src_file.filename.include?('query') ||
    src_file.filename.include?('search') ||
    src_file.filename.include?('filter')
  end

  add_group "Bulk Operations", "app/services/bulk_operations"
  add_group "Background Jobs", "app/jobs"
  add_group "Caching", "app/services" do |src_file|
    src_file.filename.include?('cache') ||
    src_file.filename.include?('memoiz')
  end

  # Performance-sensitive areas
  add_group "Categorization Engine", "app/services/categorization"
  add_group "Email Processing", "app/services/email"
  add_group "Sync Operations", "app/services/sync"
  add_group "API Endpoints", "app/controllers/api"

  # Algorithm and computation heavy code
  add_group "Matchers & Algorithms" do |src_file|
    src_file.filename.include?('matcher') ||
    src_file.filename.include?('algorithm') ||
    src_file.filename.include?('calculator')
  end

  add_group "Data Processing" do |src_file|
    src_file.filename.include?('processor') ||
    src_file.filename.include?('parser') ||
    src_file.filename.include?('transformer')
  end

  # Database query optimization targets
  add_group "ActiveRecord Queries", "app/models" do |src_file|
    # Focus on models with complex queries
    complex_models = %w[expense category sync_session]
    complex_models.any? { |model| src_file.filename.include?(model) }
  end

  # Memory and CPU intensive operations
  add_group "Heavy Operations" do |src_file|
    src_file.filename.include?('batch') ||
    src_file.filename.include?('bulk') ||
    src_file.filename.include?('mass') ||
    src_file.filename.include?('aggregate')
  end

  # Skip files not relevant for performance testing
  add_filter '/config/'
  add_filter '/vendor/'
  add_filter '/spec/'
  add_filter '/app/views/'
  add_filter '/app/assets/'
  add_filter '/app/helpers/'

  # Performance test coverage expectations
  minimum_coverage 50  # Performance tests target specific bottlenecks
  minimum_coverage_by_file 40

  # Performance tests are selective by nature
  # refuse_coverage_drop

  # Format configurations
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::SimpleFormatter
  ])

  # Track branches for performance paths
  enable_coverage :branch

  # Merge policy for performance results
  merge_timeout 14400 # 4 hours (performance tests may be long-running)
    command_name "performance-tests-#{Time.now.to_i}"
  end

  puts "⚡ Performance Test Coverage: Tracking performance-critical code paths"
  puts "📁 Coverage output: coverage/performance/"
  puts "🎯 Target: >50% overall, >40% per file (focuses on bottlenecks and optimizations)"
end
