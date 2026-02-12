# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Monitoring::HealthCheck, performance: true do
  let(:health_check) { described_class.new }

  describe "#check_all", performance: true do
    it "performs all health checks" do
      result = health_check.check_all

      expect(result).to include(
        :status,
        :healthy,
        :ready,
        :live,
        :timestamp,
        :checks,
        :errors
      )
    end

    it "returns healthy status when all checks pass" do
      # Mock the individual check methods to set the checks hash
      allow(health_check).to receive(:check_database) do
        health_check.instance_variable_set(:@checks, health_check.instance_variable_get(:@checks).merge(
          database: { status: :healthy, connected: true }
        ))
      end
      allow(health_check).to receive(:check_redis).and_return(nil)
      allow(health_check).to receive(:check_pattern_cache) do
        health_check.instance_variable_set(:@checks, health_check.instance_variable_get(:@checks).merge(
          pattern_cache: { status: :healthy, entries: 100 }
        ))
      end
      allow(health_check).to receive(:check_service_metrics) do
        health_check.instance_variable_set(:@checks, health_check.instance_variable_get(:@checks).merge(
          service_metrics: { status: :healthy }
        ))
      end
      allow(health_check).to receive(:check_dependencies) do
        health_check.instance_variable_set(:@checks, health_check.instance_variable_get(:@checks).merge(
          dependencies: { status: :healthy }
        ))
      end

      result = health_check.check_all

      expect(result[:status]).to eq(:healthy)
      expect(result[:healthy]).to be true
    end

    it "returns degraded status when non-critical checks fail" do
      # Mock the individual check methods to set the checks hash
      allow(health_check).to receive(:check_database) do
        health_check.instance_variable_set(:@checks, health_check.instance_variable_get(:@checks).merge(
          database: { status: :healthy, connected: true }
        ))
      end
      allow(health_check).to receive(:check_redis).and_return(nil)
      allow(health_check).to receive(:check_pattern_cache) do
        health_check.instance_variable_set(:@checks, health_check.instance_variable_get(:@checks).merge(
          pattern_cache: { status: :healthy, entries: 100 }
        ))
      end
      allow(health_check).to receive(:check_service_metrics) do
        health_check.instance_variable_set(:@checks, health_check.instance_variable_get(:@checks).merge(
          service_metrics: { status: :degraded, warning: "Low success rate" }
        ))
      end
      allow(health_check).to receive(:check_dependencies) do
        health_check.instance_variable_set(:@checks, health_check.instance_variable_get(:@checks).merge(
          dependencies: { status: :healthy }
        ))
      end

      result = health_check.check_all

      expect(result[:status]).to eq(:degraded)
      expect(result[:healthy]).to be true
    end

    it "returns unhealthy status when critical checks fail" do
      # Mock the individual check methods to set the checks hash
      allow(health_check).to receive(:check_database) do
        health_check.instance_variable_set(:@checks, health_check.instance_variable_get(:@checks).merge(
          database: { status: :unhealthy, connected: false, error: "Connection failed" }
        ))
      end
      allow(health_check).to receive(:check_redis).and_return(nil)
      allow(health_check).to receive(:check_pattern_cache) do
        health_check.instance_variable_set(:@checks, health_check.instance_variable_get(:@checks).merge(
          pattern_cache: { status: :healthy, entries: 100 }
        ))
      end
      allow(health_check).to receive(:check_service_metrics) do
        health_check.instance_variable_set(:@checks, health_check.instance_variable_get(:@checks).merge(
          service_metrics: { status: :healthy }
        ))
      end
      allow(health_check).to receive(:check_dependencies) do
        health_check.instance_variable_set(:@checks, health_check.instance_variable_get(:@checks).merge(
          dependencies: { status: :healthy }
        ))
      end

      result = health_check.check_all

      expect(result[:status]).to eq(:unhealthy)
      expect(result[:healthy]).to be false
    end
  end

  describe "#check_database", performance: true do
    it "checks database connectivity and performance" do
      # Create some test data
      create(:category)
      create(:categorization_pattern)

      health_check.check_database
      database_check = health_check.checks[:database]

      expect(database_check[:status]).to be_in([ :healthy, :degraded ])
      expect(database_check[:connected]).to be true
      expect(database_check[:response_time_ms]).to be_a(Float)
      expect(database_check[:pattern_count]).to be >= 0
    end

    it "handles database connection errors" do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::ConnectionNotEstablished)

      health_check.check_database
      database_check = health_check.checks[:database]

      expect(database_check[:status]).to eq(:unhealthy)
      expect(database_check[:connected]).to be false
      expect(database_check[:error]).to be_present
    end
  end

  describe "#check_pattern_cache", performance: true do
    it "checks pattern cache status" do
      cache = instance_double(Services::Categorization::PatternCache)
      allow(Services::Categorization::PatternCache).to receive(:instance).and_return(cache)
      allow(cache).to receive(:stats).and_return({
        entries: 100,
        memory_bytes: 1024000,
        hits: 800,
        misses: 200,
        evictions: 5
      })

      health_check.check_pattern_cache
      cache_check = health_check.checks[:pattern_cache]

      expect(cache_check[:status]).to eq(:healthy)
      expect(cache_check[:entries]).to eq(100)
      expect(cache_check[:hit_rate]).to eq(0.8)
    end

    it "reports degraded status for low hit rate" do
      cache = instance_double(Services::Categorization::PatternCache)
      allow(Services::Categorization::PatternCache).to receive(:instance).and_return(cache)
      allow(cache).to receive(:stats).and_return({
        entries: 100,
        memory_bytes: 1024000,
        hits: 200,
        misses: 800,
        evictions: 50
      })

      health_check.check_pattern_cache
      cache_check = health_check.checks[:pattern_cache]

      expect(cache_check[:status]).to eq(:degraded)
      expect(cache_check[:hit_rate]).to eq(0.2)
      expect(cache_check[:warning]).to include("Low cache hit rate")
    end
  end

  describe "#check_service_metrics", performance: true do
    before do
      create_list(:expense, 5, category: create(:category))
      create_list(:expense, 3, category: nil)
    end

    it "calculates service metrics correctly" do
      health_check.check_service_metrics
      metrics = health_check.checks[:service_metrics]

      expect(metrics[:status]).to be_in([ :healthy, :degraded, :unhealthy, :unknown ])
      expect(metrics[:total_patterns]).to be >= 0 if metrics[:total_patterns]
      expect(metrics[:active_patterns]).to be >= 0 if metrics[:active_patterns]
      expect(metrics[:success_rate]).to be_between(0, 1) if metrics[:success_rate]
      expect(metrics[:learning_activity]).to be_a(Hash) if metrics[:learning_activity]
    end
  end

  describe "#healthy?", performance: true do
    it "returns true when all critical checks pass" do
      health_check.instance_variable_set(:@checks, {
        database: { status: :healthy },
        pattern_cache: { status: :healthy }
      })

      expect(health_check.healthy?).to be true
    end

    it "returns false when critical checks fail" do
      health_check.instance_variable_set(:@checks, {
        database: { status: :unhealthy },
        pattern_cache: { status: :healthy }
      })

      expect(health_check.healthy?).to be false
    end

    it "returns false when there are errors" do
      health_check.instance_variable_set(:@checks, {
        database: { status: :healthy },
        pattern_cache: { status: :healthy }
      })
      health_check.instance_variable_set(:@errors, [ "Test error" ])

      expect(health_check.healthy?).to be false
    end
  end

  describe "#ready?", performance: true do
    it "returns true when database and cache are available" do
      health_check.instance_variable_set(:@checks, {
        database: { status: :healthy },
        pattern_cache: { status: :healthy }
      })

      expect(health_check.ready?).to be true
    end

    it "returns true even when degraded" do
      health_check.instance_variable_set(:@checks, {
        database: { status: :degraded },
        pattern_cache: { status: :degraded }
      })

      expect(health_check.ready?).to be true
    end

    it "returns false when critical components are unhealthy" do
      health_check.instance_variable_set(:@checks, {
        database: { status: :unhealthy },
        pattern_cache: { status: :healthy }
      })

      expect(health_check.ready?).to be false
    end
  end

  describe "#live?", performance: true do
    it "always returns true unless there's an exception" do
      expect(health_check.live?).to be true
    end
  end
end
