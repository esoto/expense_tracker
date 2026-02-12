# frozen_string_literal: true

require "rails_helper"
require_relative "../../../support/monitoring_service_test_helper"

RSpec.describe Services::Infrastructure::MonitoringService::SystemHealth, type: :service, unit: true do
  include MonitoringServiceTestHelper

  before do
    setup_time_helpers
    setup_logger_mock
  end

  describe ".check" do
    it "returns comprehensive health report with all components" do
      # Mock all individual check methods
      allow(described_class).to receive(:check_database).and_return({ status: "healthy", response_time: 5.2 })
      allow(described_class).to receive(:check_redis).and_return({ status: "healthy", response_time: 1.8 })
      allow(described_class).to receive(:check_disk_space).and_return({ status: "healthy", percent_used: 45.5 })
      allow(described_class).to receive(:check_memory).and_return({ status: "healthy", percent_used: 65.2 })
      allow(described_class).to receive(:check_services).and_return({ solid_queue: "running", action_cable: "PONG" })
      allow(described_class).to receive(:calculate_overall_health).and_return("healthy")

      result = described_class.check

      expect(result).to include(
        database: { status: "healthy", response_time: 5.2 },
        redis: { status: "healthy", response_time: 1.8 },
        disk_space: { status: "healthy", percent_used: 45.5 },
        memory: { status: "healthy", percent_used: 65.2 },
        services: { solid_queue: "running", action_cable: "PONG" },
        overall: "healthy"
      )
    end

    it "calls all individual health check methods" do
      expect(described_class).to receive(:check_database).and_return({ status: "healthy" })
      expect(described_class).to receive(:check_redis).and_return({ status: "healthy" })
      expect(described_class).to receive(:check_disk_space).and_return({ status: "healthy" })
      expect(described_class).to receive(:check_memory).and_return({ status: "healthy" })
      expect(described_class).to receive(:check_services).and_return({})
      expect(described_class).to receive(:calculate_overall_health).and_return("healthy")

      described_class.check
    end
  end

  describe ".check_database" do
    context "when database is healthy" do
      it "returns healthy status with response time" do
        connection = mock_database_connection(active: true)
        allow(described_class).to receive(:measure_db_response_time).and_return(12.5)

        result = described_class.send(:check_database)

        expect(result).to eq({
          status: "healthy",
          response_time: 12.5
        })
        expect(connection).to have_received(:active?)
      end
    end

    context "when database connection is inactive" do
      it "returns unhealthy status with error message" do
        mock_database_connection(active: false)
        allow(ActiveRecord::Base.connection).to receive(:active?).and_raise(StandardError.new("Connection failed"))

        result = described_class.send(:check_database)

        expect(result).to eq({
          status: "unhealthy",
          error: "Connection failed"
        })
      end
    end

    context "when database raises an exception" do
      it "returns unhealthy status with error message" do
        allow(ActiveRecord::Base).to receive(:connection).and_raise(ActiveRecord::ConnectionNotEstablished.new("Database unavailable"))

        result = described_class.send(:check_database)

        expect(result).to eq({
          status: "unhealthy",
          error: "Database unavailable"
        })
      end
    end
  end

  describe ".check_redis" do
    context "when Redis is healthy" do
      it "returns healthy status with response time" do
        # Mock the Redis connection properly
        redis_mock = double("Redis")
        allow(redis_mock).to receive(:ping).and_return("PONG")

        cache_mock = double("Cache")
        allow(cache_mock).to receive(:redis).and_return(redis_mock)
        allow(cache_mock).to receive(:clear) # Add clear method for test cleanup
        allow(Rails).to receive(:cache).and_return(cache_mock)

        allow(described_class).to receive(:measure_redis_response_time).and_return(3.8)

        result = described_class.send(:check_redis)

        expect(result).to eq({
          status: "healthy",
          response_time: 3.8
        })
      end
    end

    context "when Redis is unavailable" do
      it "returns unhealthy status with error message" do
        redis_mock = double("Redis")
        allow(redis_mock).to receive(:ping).and_raise(Redis::CannotConnectError.new("Redis unavailable"))

        cache_mock = double("Cache")
        allow(cache_mock).to receive(:redis).and_return(redis_mock)
        allow(cache_mock).to receive(:clear) # Add clear method for test cleanup
        allow(Rails).to receive(:cache).and_return(cache_mock)

        result = described_class.send(:check_redis)

        expect(result).to eq({
          status: "unhealthy",
          error: "Redis unavailable"
        })
      end
    end

    context "when Redis ping returns unexpected response" do
      it "returns unhealthy status with error message" do
        redis_mock = double("Redis")
        allow(redis_mock).to receive(:ping).and_raise(Redis::TimeoutError.new("Redis timeout"))

        cache_mock = double("Cache")
        allow(cache_mock).to receive(:redis).and_return(redis_mock)
        allow(cache_mock).to receive(:clear) # Add clear method for test cleanup
        allow(Rails).to receive(:cache).and_return(cache_mock)

        result = described_class.send(:check_redis)

        expect(result).to eq({
          status: "unhealthy",
          error: "Redis timeout"
        })
      end
    end
  end

  describe ".check_disk_space" do
    context "when disk space is healthy (< 80%)" do
      it "returns healthy status with percent usage" do
        filesystem_stat = double("Sys::Filesystem::Stat",
          blocks: 1000000,
          blocks_available: 800000  # 20% used
        )
        stub_const("Sys::Filesystem", double("Sys::Filesystem"))
        allow(Sys::Filesystem).to receive(:stat).with("/").and_return(filesystem_stat)

        result = described_class.send(:check_disk_space)

        expect(result).to eq({
          status: "healthy",
          percent_used: 20.0
        })
      end
    end

    context "when disk space is in warning range (80-90%)" do
      it "returns warning status with percent usage" do
        filesystem_stat = double("Sys::Filesystem::Stat",
          blocks: 1000000,
          blocks_available: 150000  # 85% used
        )
        stub_const("Sys::Filesystem", double("Sys::Filesystem"))
        allow(Sys::Filesystem).to receive(:stat).with("/").and_return(filesystem_stat)

        result = described_class.send(:check_disk_space)

        expect(result).to eq({
          status: "warning",
          percent_used: 85.0
        })
      end
    end

    context "when disk space is critical (> 90%)" do
      it "returns critical status with percent usage" do
        filesystem_stat = double("Sys::Filesystem::Stat",
          blocks: 1000000,
          blocks_available: 50000  # 95% used
        )
        stub_const("Sys::Filesystem", double("Sys::Filesystem"))
        allow(Sys::Filesystem).to receive(:stat).with("/").and_return(filesystem_stat)

        result = described_class.send(:check_disk_space)

        expect(result).to eq({
          status: "critical",
          percent_used: 95.0
        })
      end
    end

    context "when disk space check fails" do
      it "returns unknown status" do
        stub_const("Sys::Filesystem", double("Sys::Filesystem"))
        allow(Sys::Filesystem).to receive(:stat).with("/").and_raise(StandardError.new("Filesystem error"))

        result = described_class.send(:check_disk_space)

        expect(result).to eq({
          status: "unknown"
        })
      end
    end

    context "when blocks_available equals blocks (edge case)" do
      it "calculates 0% usage correctly" do
        filesystem_stat = double("Sys::Filesystem::Stat",
          blocks: 1000000,
          blocks_available: 1000000  # 0% used
        )
        stub_const("Sys::Filesystem", double("Sys::Filesystem"))
        allow(Sys::Filesystem).to receive(:stat).with("/").and_return(filesystem_stat)

        result = described_class.send(:check_disk_space)

        expect(result).to eq({
          status: "healthy",
          percent_used: 0.0
        })
      end
    end
  end

  describe ".check_memory" do
    context "when memory usage is healthy (< 80%)" do
      it "returns healthy status with percent usage" do
        # Mock free -m output: 16GB total, 8GB used = 50% used
        allow_any_instance_of(Kernel).to receive(:`).with("free -m").and_return(
          "              total        used        free      shared  buff/cache   available\n" \
          "Mem:          16384        8192        4096         512        4096        7680\n"
        )

        result = described_class.send(:check_memory)

        expect(result).to eq({
          status: "healthy",
          percent_used: 50.0
        })
      end
    end

    context "when memory usage is in warning range (80-90%)" do
      it "returns warning status with percent usage" do
        # Mock free -m output: 16GB total, 14GB used = 85.94% used
        allow_any_instance_of(Kernel).to receive(:`).with("free -m").and_return(
          "              total        used        free      shared  buff/cache   available\n" \
          "Mem:          16384       14080         256         512        2048         512\n"
        )

        result = described_class.send(:check_memory)

        expect(result).to eq({
          status: "warning",
          percent_used: 85.94
        })
      end
    end

    context "when memory usage is critical (> 90%)" do
      it "returns critical status with percent usage" do
        # Mock free -m output: 16GB total, 15GB used = 91.55% used
        allow_any_instance_of(Kernel).to receive(:`).with("free -m").and_return(
          "              total        used        free      shared  buff/cache   available\n" \
          "Mem:          16384       15000         128         512        1256         128\n"
        )

        result = described_class.send(:check_memory)

        expect(result).to eq({
          status: "critical",
          percent_used: 91.55
        })
      end
    end

    context "when memory check fails" do
      it "returns unknown status" do
        allow_any_instance_of(Kernel).to receive(:`).with("free -m").and_raise(StandardError.new("Command failed"))

        result = described_class.send(:check_memory)

        expect(result).to eq({
          status: "unknown"
        })
      end
    end

    context "when free command returns unexpected format" do
      it "returns unknown status" do
        allow_any_instance_of(Kernel).to receive(:`).with("free -m").and_return("Invalid output")

        result = described_class.send(:check_memory)

        expect(result).to eq({
          status: "unknown"
        })
      end
    end

    context "with edge case of exactly 80% usage" do
      it "returns healthy status (boundary condition)" do
        # Mock free -m output: 16GB total, 13.1GB used = exactly 80% used
        allow_any_instance_of(Kernel).to receive(:`).with("free -m").and_return(
          "              total        used        free      shared  buff/cache   available\n" \
          "Mem:          16384       13107         256         512        2509         512\n"
        )

        result = described_class.send(:check_memory)

        expect(result).to eq({
          status: "healthy",
          percent_used: 80.0
        })
      end
    end

    context "with edge case of exactly 90% usage" do
      it "returns warning status (boundary condition)" do
        # Mock free -m output: 16GB total, 14.7GB used = exactly 90% used
        allow_any_instance_of(Kernel).to receive(:`).with("free -m").and_return(
          "              total        used        free      shared  buff/cache   available\n" \
          "Mem:          16384       14746         256         512        870         512\n"
        )

        result = described_class.send(:check_memory)

        expect(result).to eq({
          status: "warning",
          percent_used: 90.0
        })
      end
    end
  end

  describe ".check_services" do
    context "when all services are running" do
      it "returns status for all services" do
        # Mock SolidQueue::Process
        solid_queue_process = double("SolidQueue::Process")
        stub_const("SolidQueue::Process", solid_queue_process)
        allow(solid_queue_process).to receive(:any?).and_return(true)

        # Mock ActionCable
        mock_action_cable(status: "running")

        result = described_class.send(:check_services)

        expect(result).to eq({
          solid_queue: "running",
          action_cable: "PONG"
        })
      end
    end

    context "when SolidQueue is not running" do
      it "returns stopped status for SolidQueue" do
        # Mock SolidQueue::Process
        solid_queue_process = double("SolidQueue::Process")
        stub_const("SolidQueue::Process", solid_queue_process)
        allow(solid_queue_process).to receive(:any?).and_return(false)

        # Mock ActionCable
        mock_action_cable(status: "running")

        result = described_class.send(:check_services)

        expect(result).to eq({
          solid_queue: "stopped",
          action_cable: "PONG"
        })
      end
    end

    context "when ActionCable is not available" do
      it "returns unknown status for ActionCable" do
        # Mock SolidQueue::Process
        solid_queue_process = double("SolidQueue::Process")
        stub_const("SolidQueue::Process", solid_queue_process)
        allow(solid_queue_process).to receive(:any?).and_return(true)

        # Mock ActionCable failure
        mock_action_cable(status: "unknown")

        result = described_class.send(:check_services)

        expect(result).to eq({
          solid_queue: "running",
          action_cable: "unknown"
        })
      end
    end

    context "when both services have issues" do
      it "returns appropriate status for both services" do
        # Mock SolidQueue::Process
        solid_queue_process = double("SolidQueue::Process")
        stub_const("SolidQueue::Process", solid_queue_process)
        allow(solid_queue_process).to receive(:any?).and_return(false)

        # Mock ActionCable failure
        mock_action_cable(status: "unknown")

        result = described_class.send(:check_services)

        expect(result).to eq({
          solid_queue: "stopped",
          action_cable: "unknown"
        })
      end
    end
  end

  describe ".calculate_overall_health" do
    context "when all checks are healthy" do
      it "returns healthy status" do
        allow(described_class).to receive(:check_database).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_redis).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_disk_space).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_memory).and_return({ status: "healthy" })

        result = described_class.send(:calculate_overall_health)

        expect(result).to eq("healthy")
      end
    end

    context "when one check has warning status" do
      it "returns degraded status" do
        allow(described_class).to receive(:check_database).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_redis).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_disk_space).and_return({ status: "warning" })
        allow(described_class).to receive(:check_memory).and_return({ status: "healthy" })

        result = described_class.send(:calculate_overall_health)

        expect(result).to eq("degraded")
      end
    end

    context "when one check is critical" do
      it "returns unhealthy status" do
        allow(described_class).to receive(:check_database).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_redis).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_disk_space).and_return({ status: "critical" })
        allow(described_class).to receive(:check_memory).and_return({ status: "healthy" })

        result = described_class.send(:calculate_overall_health)

        expect(result).to eq("unhealthy")
      end
    end

    context "when one check is unhealthy" do
      it "returns unhealthy status" do
        allow(described_class).to receive(:check_database).and_return({ status: "unhealthy" })
        allow(described_class).to receive(:check_redis).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_disk_space).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_memory).and_return({ status: "healthy" })

        result = described_class.send(:calculate_overall_health)

        expect(result).to eq("unhealthy")
      end
    end

    context "when multiple checks have issues" do
      it "prioritizes critical/unhealthy over warning" do
        allow(described_class).to receive(:check_database).and_return({ status: "critical" })
        allow(described_class).to receive(:check_redis).and_return({ status: "warning" })
        allow(described_class).to receive(:check_disk_space).and_return({ status: "warning" })
        allow(described_class).to receive(:check_memory).and_return({ status: "healthy" })

        result = described_class.send(:calculate_overall_health)

        expect(result).to eq("unhealthy")
      end
    end
  end

  describe ".measure_db_response_time" do
    it "measures database response time in milliseconds" do
      connection = mock_database_connection(active: true)

      # Mock Time.current to control time measurement
      start_time = current_time
      end_time = current_time + 0.015 # 15ms
      allow(Time).to receive(:current).and_return(start_time, end_time)

      result = described_class.send(:measure_db_response_time)

      expect(result).to eq(15.0)
      expect(connection).to have_received(:execute).with("SELECT 1")
    end

    it "handles very fast responses" do
      connection = mock_database_connection(active: true)

      # Mock Time.current to control time measurement (1ms response)
      start_time = current_time
      end_time = current_time + 0.001
      allow(Time).to receive(:current).and_return(start_time, end_time)

      result = described_class.send(:measure_db_response_time)

      expect(result).to eq(1.0)
      expect(connection).to have_received(:execute).with("SELECT 1")
    end
  end

  describe ".measure_redis_response_time" do
    it "measures Redis response time in milliseconds" do
      # Mock the Redis connection properly
      redis_mock = double("Redis")
      allow(redis_mock).to receive(:ping).and_return("PONG")

      cache_mock = double("Cache")
      allow(cache_mock).to receive(:redis).and_return(redis_mock)
      allow(cache_mock).to receive(:clear) # Add clear method for test cleanup
      allow(Rails).to receive(:cache).and_return(cache_mock)

      # Mock Time.current to control time measurement
      start_time = current_time
      end_time = current_time + 0.0025 # 2.5ms
      allow(Time).to receive(:current).and_return(start_time, end_time)

      result = described_class.send(:measure_redis_response_time)

      expect(result).to eq(2.5)
      expect(redis_mock).to have_received(:ping)
    end

    it "handles very slow responses" do
      # Mock the Redis connection properly
      redis_mock = double("Redis")
      allow(redis_mock).to receive(:ping).and_return("PONG")

      cache_mock = double("Cache")
      allow(cache_mock).to receive(:redis).and_return(redis_mock)
      allow(cache_mock).to receive(:clear) # Add clear method for test cleanup
      allow(Rails).to receive(:cache).and_return(cache_mock)

      # Mock Time.current to control time measurement (100ms response)
      start_time = current_time
      end_time = current_time + 0.1
      allow(Time).to receive(:current).and_return(start_time, end_time)

      result = described_class.send(:measure_redis_response_time)

      expect(result).to eq(100.0)
      expect(redis_mock).to have_received(:ping)
    end
  end
end
