# frozen_string_literal: true

# Shared helper for Infrastructure::MonitoringService tests
# Provides common mocking patterns and test utilities
module MonitoringServiceTestHelper
  extend ActiveSupport::Concern

  included do
    # Time helpers
    let(:current_time) { Time.zone.local(2024, 1, 15, 10, 30, 0) }
    let(:one_hour_ago) { current_time - 1.hour }
    let(:one_day_ago) { current_time - 1.day }

    # Common mock setups
    def setup_time_helpers
      allow(Time).to receive(:current).and_return(current_time)
      allow(Time.zone).to receive(:now).and_return(current_time)
      allow(Date).to receive(:current).and_return(current_time.to_date)
    end

    # Rails.cache mocking with MemoryStore
    def setup_memory_cache
      @memory_cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(@memory_cache)
      @memory_cache
    end

    # Logger mocking
    def setup_logger_mock
      @logger_mock = instance_double(ActiveSupport::Logger)
      allow(Rails).to receive(:logger).and_return(@logger_mock)
      allow(@logger_mock).to receive(:error)
      allow(@logger_mock).to receive(:info)
      allow(@logger_mock).to receive(:warn)
      allow(@logger_mock).to receive(:debug)
      @logger_mock
    end

    # SolidQueue mocking helpers
    def mock_solid_queue_models
      # Mock SolidQueue::Job
      @solid_queue_job = double("SolidQueue::Job")
      stub_const("SolidQueue::Job", @solid_queue_job)
      allow(@solid_queue_job).to receive(:pending).and_return(@solid_queue_job)
      allow(@solid_queue_job).to receive(:finished).and_return(@solid_queue_job)
      allow(@solid_queue_job).to receive(:where).and_return(@solid_queue_job)
      allow(@solid_queue_job).to receive(:group).and_return(@solid_queue_job)
      allow(@solid_queue_job).to receive(:count).and_return({})
      allow(@solid_queue_job).to receive(:average).and_return({})
      allow(@solid_queue_job).to receive(:pluck).and_return([])
      allow(@solid_queue_job).to receive(:empty?).and_return(false)
      allow(@solid_queue_job).to receive(:not).and_return(@solid_queue_job)

      # Mock SolidQueue::FailedExecution
      @solid_queue_failed = double("SolidQueue::FailedExecution")
      stub_const("SolidQueue::FailedExecution", @solid_queue_failed)
      allow(@solid_queue_failed).to receive(:where).and_return(@solid_queue_failed)
      allow(@solid_queue_failed).to receive(:count).and_return(0)

      # Mock SolidQueue::ScheduledExecution
      @solid_queue_scheduled = double("SolidQueue::ScheduledExecution")
      stub_const("SolidQueue::ScheduledExecution", @solid_queue_scheduled)
      allow(@solid_queue_scheduled).to receive(:where).and_return(@solid_queue_scheduled)
      allow(@solid_queue_scheduled).to receive(:count).and_return(0)

      # Mock SolidQueue::Process
      @solid_queue_process = double("SolidQueue::Process")
      stub_const("SolidQueue::Process", @solid_queue_process)
      allow(@solid_queue_process).to receive(:where).and_return(@solid_queue_process)
      allow(@solid_queue_process).to receive(:count).and_return(0)

      {
        job: @solid_queue_job,
        failed: @solid_queue_failed,
        scheduled: @solid_queue_scheduled,
        process: @solid_queue_process
      }
    end

    # Pattern Cache mocking
    def mock_pattern_cache(metrics = {})
      default_metrics = {
        hit_rate: 85.5,
        hits: 1000,
        misses: 200,
        memory_cache_entries: 500,
        redis_available: true,
        average_lookup_time_ms: 2.5
      }

      cache_instance = double("Categorization::PatternCache instance")
      allow(cache_instance).to receive(:metrics).and_return(default_metrics.merge(metrics))

      pattern_cache_class = double("Categorization::PatternCache")
      stub_const("Categorization::PatternCache", pattern_cache_class)
      allow(pattern_cache_class).to receive(:instance).and_return(cache_instance)

      cache_instance
    end

    # System command mocking
    def mock_system_commands
      # Mock disk space check
      filesystem_stat = double("Sys::Filesystem::Stat",
        blocks: 1000000,
        blocks_available: 800000
      )
      allow(Sys::Filesystem).to receive(:stat).and_return(filesystem_stat) if defined?(Sys::Filesystem)

      # Mock memory check
      allow_any_instance_of(Kernel).to receive(:`).with("free -m").and_return(
        "              total        used        free      shared  buff/cache   available\n" \
        "Mem:          16384        8192        4096         512        4096        7680\n"
      )
    end

    # ActiveRecord connection mocking
    def mock_database_connection(active: true)
      connection = double("ActiveRecord::ConnectionAdapters::PostgreSQLAdapter")
      allow(connection).to receive(:active?).and_return(active)
      allow(connection).to receive(:execute).with("SELECT 1")

      allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
      connection
    end

    # Redis connection mocking
    def mock_redis_connection(available: true)
      redis_mock = double("Redis")
      if available
        allow(redis_mock).to receive(:ping).and_return("PONG")
      else
        allow(redis_mock).to receive(:ping).and_raise(Redis::CannotConnectError)
      end

      cache_mock = double("Cache")
      allow(cache_mock).to receive(:redis).and_return(redis_mock)
      allow(Rails).to receive(:cache).and_return(cache_mock) unless Rails.cache.is_a?(ActiveSupport::Cache::MemoryStore)

      redis_mock
    end

    # ActionCable mocking
    def mock_action_cable(status: "running")
      pubsub = double("ActionCable::SubscriptionAdapter::Redis")
      redis_connection = double("Redis")

      if status == "running"
        allow(redis_connection).to receive(:ping).and_return("PONG")
      else
        allow(redis_connection).to receive(:ping).and_raise(StandardError)
      end

      allow(pubsub).to receive(:redis_connection_for_subscriptions).and_return(redis_connection)

      server = double("ActionCable::Server::Base")
      allow(server).to receive(:pubsub).and_return(pubsub)

      allow(ActionCable).to receive(:server).and_return(server)
    end

    # Factory helpers for creating test data
    def create_sync_sessions(count: 3, status: :completed, time_window: 1.hour)
      sessions = []
      count.times do |i|
        session = create(:sync_session,
          status: status,
          created_at: current_time - (time_window / 2),
          started_at: current_time - (time_window / 2),
          completed_at: status == :completed ? current_time - (time_window / 3) : nil,
          processed_emails: 10 + i  # Use correct attribute name
        )
        sessions << session
      end
      sessions
    end

    def create_expenses_with_categories(count: 5, time_window: 1.hour, from_email: false)
      expenses = []
      count.times do |i|
        # Create expenses with raw_email_content for email-sourced expenses
        expense = create(:expense,
          category: create(:category),
          auto_categorized: i.even?,
          created_at: current_time - (time_window / 2),
          updated_at: current_time - (time_window / 3),
          raw_email_content: (from_email || i < 3) ? "Email content" : nil  # Use raw_email_content to indicate email source
        )
        expenses << expense
      end
      expenses
    end

    def create_bulk_operations(count: 2, time_window: 1.hour)
      operations = []
      count.times do |i|
        operation = create(:bulk_operation,
          operation_type: :categorization,
          expense_count: 10 + (i * 5),
          status: i.odd? ? :undone : :completed,
          created_at: current_time - (time_window / 2)
        )
        operations << operation
      end
      operations
    end

    # Assertion helpers
    def expect_metric_structure(metrics, required_keys)
      required_keys.each do |key|
        expect(metrics).to have_key(key), "Missing required key: #{key}"
      end
    end

    def expect_numeric_metric(value, min: nil, max: nil)
      expect(value).to be_a(Numeric)
      expect(value).to be >= min if min
      expect(value).to be <= max if max
    end

    def expect_percentage(value)
      expect_numeric_metric(value, min: 0, max: 100)
    end

    def expect_timestamp(value, within: 1.day)
      expect(value).to be_a(Time).or be_a(ActiveSupport::TimeWithZone)
      expect(value).to be_within(within).of(current_time)
    end
  end
end
