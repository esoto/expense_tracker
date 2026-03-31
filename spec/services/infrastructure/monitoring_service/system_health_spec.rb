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
      allow(described_class).to receive(:check_database).and_return({ status: "healthy", response_time: 5.2 })
      allow(described_class).to receive(:check_cache).and_return({ status: "healthy", response_time: 1.8 })
      allow(described_class).to receive(:check_disk_space).and_return({ status: "healthy", percent_used: 45.5 })
      allow(described_class).to receive(:check_memory).and_return({ status: "healthy", percent_used: 65.2 })
      allow(described_class).to receive(:check_services).and_return({ solid_queue: "running", action_cable: "running" })
      allow(described_class).to receive(:calculate_overall_health).and_return("healthy")

      result = described_class.check

      expect(result).to include(
        database: { status: "healthy", response_time: 5.2 },
        cache: { status: "healthy", response_time: 1.8 },
        disk_space: { status: "healthy", percent_used: 45.5 },
        memory: { status: "healthy", percent_used: 65.2 },
        services: { solid_queue: "running", action_cable: "running" },
        overall: "healthy"
      )
    end

    it "calls all individual health check methods" do
      expect(described_class).to receive(:check_database).and_return({ status: "healthy" })
      expect(described_class).to receive(:check_cache).and_return({ status: "healthy" })
      expect(described_class).to receive(:check_disk_space).and_return({ status: "healthy" })
      expect(described_class).to receive(:check_memory).and_return({ status: "healthy" })
      expect(described_class).to receive(:check_services).and_return({})
      expect(described_class).to receive(:calculate_overall_health).and_return("healthy")

      described_class.check
    end

    it "does not include a :redis key in the health report" do
      allow(described_class).to receive(:check_database).and_return({ status: "healthy" })
      allow(described_class).to receive(:check_cache).and_return({ status: "healthy" })
      allow(described_class).to receive(:check_disk_space).and_return({ status: "healthy" })
      allow(described_class).to receive(:check_memory).and_return({ status: "healthy" })
      allow(described_class).to receive(:check_services).and_return({})
      allow(described_class).to receive(:calculate_overall_health).and_return("healthy")

      result = described_class.check

      expect(result).not_to have_key(:redis)
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

  describe ".check_cache" do
    context "when cache is healthy" do
      it "performs a write/read/delete cycle and returns healthy status" do
        cache_mock = double("Cache", clear: nil)
        allow(Rails).to receive(:cache).and_return(cache_mock)
        allow(SecureRandom).to receive(:hex).with(4).and_return("abcd1234")

        expect(cache_mock).to receive(:write).with("health_check:abcd1234", "ok", expires_in: 10.seconds)
        expect(cache_mock).to receive(:read).with("health_check:abcd1234").and_return("ok")
        expect(cache_mock).to receive(:delete).with("health_check:abcd1234")

        allow(described_class).to receive(:measure_cache_response_time).and_return(3.8)

        result = described_class.send(:check_cache)

        expect(result).to eq({
          status: "healthy",
          response_time: 3.8
        })
      end
    end

    context "when cache read returns a mismatched value" do
      it "returns degraded status" do
        cache_mock = double("Cache", clear: nil)
        allow(Rails).to receive(:cache).and_return(cache_mock)
        allow(SecureRandom).to receive(:hex).with(4).and_return("abcd1234")

        allow(cache_mock).to receive(:write)
        allow(cache_mock).to receive(:read).with("health_check:abcd1234").and_return(nil)
        allow(cache_mock).to receive(:delete)

        result = described_class.send(:check_cache)

        expect(result).to eq({
          status: "degraded",
          error: "Cache write/read mismatch"
        })
      end
    end

    context "when cache raises an exception" do
      it "returns unhealthy status with error message" do
        cache_mock = double("Cache", clear: nil)
        allow(Rails).to receive(:cache).and_return(cache_mock)
        allow(SecureRandom).to receive(:hex).with(4).and_return("abcd1234")
        allow(cache_mock).to receive(:write).and_raise(StandardError.new("Cache unavailable"))

        result = described_class.send(:check_cache)

        expect(result).to eq({
          status: "unhealthy",
          error: "Cache unavailable"
        })
      end
    end

    it "does not call Rails.cache.redis" do
      cache_mock = double("Cache", clear: nil)
      allow(Rails).to receive(:cache).and_return(cache_mock)
      allow(SecureRandom).to receive(:hex).with(4).and_return("abcd1234")
      allow(cache_mock).to receive(:write)
      allow(cache_mock).to receive(:read).and_return("ok")
      allow(cache_mock).to receive(:delete)
      allow(described_class).to receive(:measure_cache_response_time).and_return(1.0)

      expect(cache_mock).not_to receive(:redis)

      described_class.send(:check_cache)
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
        solid_queue_process = double("SolidQueue::Process")
        stub_const("SolidQueue::Process", solid_queue_process)
        allow(solid_queue_process).to receive(:any?).and_return(true)

        mock_action_cable_adapter(available: true)

        result = described_class.send(:check_services)

        expect(result).to eq({
          solid_queue: "running",
          action_cable: "running"
        })
      end
    end

    context "when SolidQueue is not running" do
      it "returns stopped status for SolidQueue" do
        solid_queue_process = double("SolidQueue::Process")
        stub_const("SolidQueue::Process", solid_queue_process)
        allow(solid_queue_process).to receive(:any?).and_return(false)

        mock_action_cable_adapter(available: true)

        result = described_class.send(:check_services)

        expect(result).to eq({
          solid_queue: "stopped",
          action_cable: "running"
        })
      end
    end

    context "when ActionCable is not available" do
      it "returns unknown status for ActionCable" do
        solid_queue_process = double("SolidQueue::Process")
        stub_const("SolidQueue::Process", solid_queue_process)
        allow(solid_queue_process).to receive(:any?).and_return(true)

        mock_action_cable_adapter(available: false)

        result = described_class.send(:check_services)

        expect(result).to eq({
          solid_queue: "running",
          action_cable: "unknown"
        })
      end
    end

    context "when both services have issues" do
      it "returns appropriate status for both services" do
        solid_queue_process = double("SolidQueue::Process")
        stub_const("SolidQueue::Process", solid_queue_process)
        allow(solid_queue_process).to receive(:any?).and_return(false)

        mock_action_cable_adapter(available: false)

        result = described_class.send(:check_services)

        expect(result).to eq({
          solid_queue: "stopped",
          action_cable: "unknown"
        })
      end
    end

    it "does not call redis_connection_for_subscriptions on ActionCable pubsub" do
      solid_queue_process = double("SolidQueue::Process")
      stub_const("SolidQueue::Process", solid_queue_process)
      allow(solid_queue_process).to receive(:any?).and_return(true)

      pubsub = double("ActionCable::SubscriptionAdapter")
      server = double("ActionCable::Server::Base")
      allow(server).to receive(:pubsub).and_return(pubsub)
      allow(ActionCable).to receive(:server).and_return(server)

      expect(pubsub).not_to receive(:redis_connection_for_subscriptions)

      described_class.send(:check_services)
    end
  end

  describe ".calculate_overall_health" do
    context "when all checks are healthy" do
      it "returns healthy status" do
        allow(described_class).to receive(:check_database).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_cache).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_disk_space).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_memory).and_return({ status: "healthy" })

        result = described_class.send(:calculate_overall_health)

        expect(result).to eq("healthy")
      end
    end

    context "when one check has warning status" do
      it "returns degraded status" do
        allow(described_class).to receive(:check_database).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_cache).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_disk_space).and_return({ status: "warning" })
        allow(described_class).to receive(:check_memory).and_return({ status: "healthy" })

        result = described_class.send(:calculate_overall_health)

        expect(result).to eq("degraded")
      end
    end

    context "when one check is critical" do
      it "returns unhealthy status" do
        allow(described_class).to receive(:check_database).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_cache).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_disk_space).and_return({ status: "critical" })
        allow(described_class).to receive(:check_memory).and_return({ status: "healthy" })

        result = described_class.send(:calculate_overall_health)

        expect(result).to eq("unhealthy")
      end
    end

    context "when one check is unhealthy" do
      it "returns unhealthy status" do
        allow(described_class).to receive(:check_database).and_return({ status: "unhealthy" })
        allow(described_class).to receive(:check_cache).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_disk_space).and_return({ status: "healthy" })
        allow(described_class).to receive(:check_memory).and_return({ status: "healthy" })

        result = described_class.send(:calculate_overall_health)

        expect(result).to eq("unhealthy")
      end
    end

    context "when multiple checks have issues" do
      it "prioritizes critical/unhealthy over warning" do
        allow(described_class).to receive(:check_database).and_return({ status: "critical" })
        allow(described_class).to receive(:check_cache).and_return({ status: "warning" })
        allow(described_class).to receive(:check_disk_space).and_return({ status: "warning" })
        allow(described_class).to receive(:check_memory).and_return({ status: "healthy" })

        result = described_class.send(:calculate_overall_health)

        expect(result).to eq("unhealthy")
      end
    end

    it "calls check_cache and does not define check_redis" do
      allow(described_class).to receive(:check_database).and_return({ status: "healthy" })
      allow(described_class).to receive(:check_disk_space).and_return({ status: "healthy" })
      allow(described_class).to receive(:check_memory).and_return({ status: "healthy" })

      expect(described_class).to receive(:check_cache).and_return({ status: "healthy" })

      described_class.send(:calculate_overall_health)

      expect(described_class.private_methods).not_to include(:check_redis)
    end
  end

  describe ".measure_db_response_time" do
    it "measures database response time in milliseconds" do
      connection = mock_database_connection(active: true)

      start_time = current_time
      end_time = current_time + 0.015 # 15ms
      allow(Time).to receive(:current).and_return(start_time, end_time)

      result = described_class.send(:measure_db_response_time)

      expect(result).to eq(15.0)
      expect(connection).to have_received(:execute).with("SELECT 1")
    end

    it "handles very fast responses" do
      connection = mock_database_connection(active: true)

      start_time = current_time
      end_time = current_time + 0.001
      allow(Time).to receive(:current).and_return(start_time, end_time)

      result = described_class.send(:measure_db_response_time)

      expect(result).to eq(1.0)
      expect(connection).to have_received(:execute).with("SELECT 1")
    end
  end

  describe ".measure_cache_response_time" do
    it "measures cache response time in milliseconds using write/read" do
      cache_mock = double("Cache", clear: nil)
      allow(Rails).to receive(:cache).and_return(cache_mock)
      allow(cache_mock).to receive(:write)
      allow(cache_mock).to receive(:read)
      allow(cache_mock).to receive(:delete)

      start_time = current_time
      end_time = current_time + 0.0025 # 2.5ms
      allow(Time).to receive(:current).and_return(start_time, end_time)

      result = described_class.send(:measure_cache_response_time)

      expect(result).to eq(2.5)
      expect(cache_mock).to have_received(:write).with("health_check:ping", "pong", expires_in: 5.seconds)
      expect(cache_mock).to have_received(:read).with("health_check:ping")
      expect(cache_mock).to have_received(:delete).with("health_check:ping")
    end

    it "does not call Rails.cache.redis" do
      cache_mock = double("Cache", clear: nil)
      allow(Rails).to receive(:cache).and_return(cache_mock)
      allow(cache_mock).to receive(:write)
      allow(cache_mock).to receive(:read)
      allow(cache_mock).to receive(:delete)

      expect(cache_mock).not_to receive(:redis)

      described_class.send(:measure_cache_response_time)
    end

    it "returns a numeric value" do
      cache_mock = double("Cache", clear: nil)
      allow(Rails).to receive(:cache).and_return(cache_mock)
      allow(cache_mock).to receive(:write)
      allow(cache_mock).to receive(:read)
      allow(cache_mock).to receive(:delete)

      result = described_class.send(:measure_cache_response_time)

      expect(result).to be_a(Numeric)
    end

    it "handles slow cache responses" do
      cache_mock = double("Cache", clear: nil)
      allow(Rails).to receive(:cache).and_return(cache_mock)
      allow(cache_mock).to receive(:write)
      allow(cache_mock).to receive(:read)
      allow(cache_mock).to receive(:delete)

      start_time = current_time
      end_time = current_time + 0.1 # 100ms
      allow(Time).to receive(:current).and_return(start_time, end_time)

      result = described_class.send(:measure_cache_response_time)

      expect(result).to eq(100.0)
    end
  end
end
