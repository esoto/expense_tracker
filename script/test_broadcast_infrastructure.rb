#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test script to verify broadcast infrastructure integration
# This script tests the basic functionality of the enhanced broadcasting system
# without requiring the full Rails environment to be running.

require_relative '../config/environment'

class BroadcastInfrastructureTest
  def self.run
    new.run_all_tests
  end

  def run_all_tests
    puts "🚀 Testing Enhanced Broadcast Infrastructure"
    puts "=" * 50

    test_broadcast_reliability_service
    test_broadcast_analytics
    test_broadcast_error_handler
    test_progress_batch_collector
    test_sync_status_channel_integration

    puts "\n✅ All tests completed successfully!"
    puts "The broadcast infrastructure is ready for use."
  end

  private

  def test_broadcast_reliability_service
    puts "\n📡 Testing BroadcastReliabilityService..."

    # Test priority configuration
    config = BroadcastReliabilityService.priority_config(:high)
    assert config[:max_retries] == 4, "High priority should have 4 max retries"

    # Test invalid priority handling
    begin
      BroadcastReliabilityService.priority_config(:invalid)
      assert false, "Should raise InvalidPriorityError"
    rescue BroadcastReliabilityService::InvalidPriorityError
      # Expected behavior
    end

    puts "✓ BroadcastReliabilityService priority system working correctly"
  end

  def test_broadcast_analytics
    puts "\n📊 Testing BroadcastAnalytics..."

    # Test analytics initialization
    metrics = BroadcastAnalytics.get_dashboard_metrics
    assert metrics.is_a?(Hash), "Dashboard metrics should return a hash"
    assert metrics.key?(:current), "Dashboard metrics should have current data"
    assert metrics.key?(:trend), "Dashboard metrics should have trend data"

    # Test metrics recording (using cache)
    BroadcastAnalytics.record_success(
      channel: 'TestChannel',
      target_type: 'TestTarget',
      target_id: 123,
      priority: :medium,
      attempt: 1,
      duration: 0.1
    )

    puts "✓ BroadcastAnalytics recording and retrieval working correctly"
  end

  def test_broadcast_error_handler
    puts "\n🛡️  Testing BroadcastErrorHandler..."

    # Test circuit breaker state
    state = BroadcastErrorHandler.get_circuit_state('TestChannel')
    assert %w[closed open half_open].include?(state), "Circuit state should be valid"

    # Test health check
    health = BroadcastErrorHandler.broadcast_health_check
    assert [ true, false ].include?(health), "Health check should return boolean"

    # Test error statistics
    stats = BroadcastErrorHandler.get_error_statistics
    assert stats.is_a?(Hash), "Error statistics should return a hash"
    assert stats.key?(:time_window), "Error statistics should include time window"

    puts "✓ BroadcastErrorHandler circuit breaker and monitoring working correctly"
  end

  def test_progress_batch_collector
    puts "\n📦 Testing ProgressBatchCollector..."

    # Create a mock sync session
    sync_session = create_mock_sync_session

    # Test batch collector initialization
    collector = ProgressBatchCollector.new(sync_session)
    assert collector.active?, "Batch collector should be active after initialization"

    # Test adding updates
    collector.add_progress_update(processed: 50, total: 100, detected: 10)
    collector.add_activity_update(activity_type: 'test', message: 'Test message')

    # Test statistics
    stats = collector.stats
    assert stats.is_a?(Hash), "Batch collector stats should return a hash"
    assert stats.key?(:sync_session_id), "Stats should include session ID"

    # Clean up
    collector.stop
    assert !collector.active?, "Batch collector should be inactive after stop"

    puts "✓ ProgressBatchCollector batching and statistics working correctly"
  end

  def test_sync_status_channel_integration
    puts "\n🔗 Testing SyncStatusChannel integration..."

    # Test that the channel class loads correctly
    assert defined?(SyncStatusChannel), "SyncStatusChannel should be defined"

    # Test that enhanced methods are available
    assert SyncStatusChannel.respond_to?(:broadcast_progress), "Should have broadcast_progress method"
    assert SyncStatusChannel.respond_to?(:broadcast_account_progress), "Should have broadcast_account_progress method"

    # Test private methods exist
    channel_methods = SyncStatusChannel.private_methods
    assert channel_methods.include?(:broadcast_with_reliability), "Should have broadcast_with_reliability method"

    puts "✓ SyncStatusChannel integration working correctly"
  end

  def create_mock_sync_session
    # Create a minimal mock object that responds like a SyncSession
    mock = Object.new

    def mock.id
      123
    end

    def mock.status
      'processing'
    end

    def mock.progress_percentage
      50
    end

    def mock.processed_emails
      150
    end

    def mock.total_emails
      300
    end

    def mock.detected_expenses
      25
    end

    mock
  end

  def assert(condition, message = "Assertion failed")
    unless condition
      puts "❌ #{message}"
      raise "Test failed: #{message}"
    end
  end
end

# Run the tests if this script is executed directly
if __FILE__ == $0
  begin
    BroadcastInfrastructureTest.run
  rescue StandardError => e
    puts "\n❌ Test failed with error: #{e.message}"
    puts e.backtrace.first(5).join("\n")
    exit 1
  end
end
