# frozen_string_literal: true

require 'ostruct'

module BroadcastServiceTestHelper
  def setup_broadcast_test_environment(options = {})
    # Use MemoryStore for caching in tests
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    # Mock ActionCable server with test recorder (unless disabled)
    unless options[:skip_action_cable_mock]
      @broadcast_recorder = BroadcastRecorder.new
      allow(ActionCable).to receive(:server).and_return(@broadcast_recorder)
    end

    # Setup analytics mock with proper tracking (unless disabled)
    unless options[:skip_analytics_mock]
      @analytics_recorder = AnalyticsRecorder.new
      allow(Infrastructure::BroadcastService::Analytics).to receive(:record) do |channel, target, priority, result|
        @analytics_recorder.record(channel, target, priority, result)
      end
      allow(Infrastructure::BroadcastService::Analytics).to receive(:get_metrics) do |options = {}|
        @analytics_recorder.get_metrics(options)
      end
    end

    # Reset feature flags to default state
    Infrastructure::BroadcastService::FeatureFlags.reset!

    # Clear any existing failed broadcasts
    FailedBroadcastStore.destroy_all if defined?(FailedBroadcastStore)
  end

  # New method for minimal test setup (just cache)
  def setup_minimal_broadcast_test_environment
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Infrastructure::BroadcastService::FeatureFlags.reset!
  end

  def teardown_broadcast_test_environment
    Rails.cache = @original_cache
    @broadcast_recorder = nil
    @analytics_recorder = nil
  end

  # Minimal setup for unit tests that don't need full mocking infrastructure
  def setup_minimal_test_environment
    # Use MemoryStore for caching but don't mock any services
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  def teardown_minimal_test_environment
    Rails.cache.clear if Rails.cache.is_a?(ActiveSupport::Cache::MemoryStore)
    Rails.cache = @original_cache
  end

  def with_feature_flag(flag, value)
    original = Infrastructure::BroadcastService::FeatureFlags.flags[flag]
    Infrastructure::BroadcastService::FeatureFlags.flags[flag] = value
    yield
  ensure
    Infrastructure::BroadcastService::FeatureFlags.flags[flag] = original
  end

  def with_rate_limit(target, count)
    key = "rate_limit:#{target.class.name}:#{target.id}"
    Rails.cache.write(key, count, expires_in: 1.minute)
  end

  def open_circuit_breaker(channel)
    Rails.cache.write("circuit_breaker:#{channel}", true, expires_in: 5.minutes)
  end

  def close_circuit_breaker(channel)
    Rails.cache.delete("circuit_breaker:#{channel}")
  end

  def trigger_circuit_breaker(channel, error_count = 5)
    key = "broadcast_errors:#{channel}"
    Rails.cache.write(key, error_count, expires_in: 5.minutes)
    open_circuit_breaker(channel) if error_count >= 5
  end

  # Test recorder for ActionCable broadcasts
  class BroadcastRecorder
    attr_reader :broadcasts

    def initialize
      @broadcasts = []
    end

    def broadcast(channel, data)
      @broadcasts << { channel: channel, data: data, timestamp: Time.current }
      true
    end

    def clear
      @broadcasts.clear
    end

    def broadcast_count
      @broadcasts.size
    end

    def last_broadcast
      @broadcasts.last
    end

    def broadcasts_for(channel)
      @broadcasts.select { |b| b[:channel] == channel }
    end
  end

  # Analytics recorder for test environment
  class AnalyticsRecorder
    attr_reader :records

    def initialize
      @records = []
    end

    def record(channel, target, priority, result)
      @records << {
        channel: channel,
        target: target,
        priority: priority,
        result: result,
        timestamp: Time.current
      }
    end

    def get_metrics(options = {})
      time_window = options[:time_window] || 1.hour
      cutoff_time = Time.current - time_window

      # Filter records by time window
      relevant_records = @records.select { |r| r[:timestamp] >= cutoff_time }

      # Initialize metrics structure
      metrics = {
        total_broadcasts: relevant_records.size,
        success_count: 0,
        failure_count: 0,
        success_rate: 0.0,
        average_duration: 0.0,
        by_channel: {},
        by_priority: {}
      }

      return metrics if relevant_records.empty?

      # Calculate metrics
      total_duration = 0.0
      successful_broadcasts = 0

      relevant_records.each do |record|
        channel = record[:channel]
        priority = record[:priority]
        result = record[:result]

        # Track success/failure
        if result[:success]
          metrics[:success_count] += 1
          successful_broadcasts += 1
          total_duration += result[:duration] if result[:duration]
        else
          metrics[:failure_count] += 1
        end

        # Track by channel
        metrics[:by_channel][channel] ||= { count: 0, duration: 0 }
        if result[:success]
          metrics[:by_channel][channel][:count] += 1
          metrics[:by_channel][channel][:duration] += result[:duration] if result[:duration]
        end

        # Track by priority
        metrics[:by_priority][priority] ||= { count: 0, duration: 0 }
        if result[:success]
          metrics[:by_priority][priority][:count] += 1
          metrics[:by_priority][priority][:duration] += result[:duration] if result[:duration]
        end
      end

      # Calculate success rate and average duration
      metrics[:success_rate] = metrics[:total_broadcasts] > 0 ?
        (metrics[:success_count].to_f / metrics[:total_broadcasts] * 100).round(2) : 0.0
      metrics[:average_duration] = successful_broadcasts > 0 ? total_duration / successful_broadcasts : 0.0

      metrics
    end

    def clear
      @records.clear
    end
  end

  # Simple test record that reuses existing table structure
  class BroadcastTestRecord < ApplicationRecord
    self.table_name = 'expenses' # Reuse existing table for tests

    def self.create_for_test(id: nil)
      # Ensure EmailAccount exists for foreign key constraint
      email_account = EmailAccount.find_or_create_by(email: 'test@broadcast.example.com') do |ea|
        ea.provider = 'custom'
        ea.bank_name = 'Test Bank'
        ea.encrypted_password = 'test123'
        ea.active = true
        ea.settings = { host: 'localhost', port: 993 }
      end

      attributes = {
        amount: 100.0,
        transaction_date: Date.current,
        email_account_id: email_account.id,
        status: 'pending'
      }

      # If ID is specified and record exists, try to clean it up safely
      if id
        attributes[:id] = id
        if exists?(id)
          # Use destroy_all to avoid loading the record
          where(id: id).destroy_all
        end
      end

      create!(attributes)
    end
  end


  # Factory methods for test data
  def create_test_target(id: nil)
    # Create a proper ActiveRecord model that's ActiveJob serializable
    BroadcastTestRecord.create_for_test(id: id)
  end

  def create_test_data(size: :small)
    case size
    when :small
      { message: "Test message", timestamp: Time.current.iso8601 }
    when :medium
      { message: "Test message" * 100, data: Array.new(50) { |i| "item_#{i}" } }
    when :large
      { message: "Test message" * 1000, data: Array.new(5000) { |i| "item_#{i}" } }
    when :oversized
      { message: "x" * 70_000 }
    else
      { message: "Default test data" }
    end
  end
end
