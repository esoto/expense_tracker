# frozen_string_literal: true

require "rails_helper"
require_relative "../../support/monitoring_service_test_helper"

RSpec.describe Services::Infrastructure::MonitoringService, type: :service, unit: true do
  include MonitoringServiceTestHelper

  describe "Main Interface (Tier 4 - Simple Delegation)" do
    before do
      setup_time_helpers
    end

    describe ".queue_metrics" do
      it "delegates to QueueMonitor.metrics" do
        expect(Services::Infrastructure::MonitoringService::QueueMonitor).to receive(:metrics).and_return({ test: "data" })

        result = described_class.queue_metrics

        expect(result).to eq({ test: "data" })
      end
    end

    describe ".job_metrics" do
      it "delegates to JobMonitor.metrics" do
        expect(Services::Infrastructure::MonitoringService::JobMonitor).to receive(:metrics).and_return({ jobs: "metrics" })

        result = described_class.job_metrics

        expect(result).to eq({ jobs: "metrics" })
      end
    end

    describe ".performance_metrics" do
      it "delegates to PerformanceTracker.metrics with component" do
        expect(Services::Infrastructure::MonitoringService::PerformanceTracker).to receive(:metrics)
          .with("email_processor")
          .and_return({ perf: "data" })

        result = described_class.performance_metrics("email_processor")

        expect(result).to eq({ perf: "data" })
      end

      it "delegates to PerformanceTracker.metrics without component" do
        expect(Services::Infrastructure::MonitoringService::PerformanceTracker).to receive(:metrics)
          .with(nil)
          .and_return({ all: "metrics" })

        result = described_class.performance_metrics

        expect(result).to eq({ all: "metrics" })
      end
    end

    describe ".error_summary" do
      it "delegates to ErrorTracker.summary with default time window" do
        expect(Services::Infrastructure::MonitoringService::ErrorTracker).to receive(:summary)
          .with(time_window: 1.hour)
          .and_return({ errors: "summary" })

        result = described_class.error_summary

        expect(result).to eq({ errors: "summary" })
      end

      it "delegates to ErrorTracker.summary with custom time window" do
        expect(Services::Infrastructure::MonitoringService::ErrorTracker).to receive(:summary)
          .with(time_window: 2.hours)
          .and_return({ errors: "custom" })

        result = described_class.error_summary(time_window: 2.hours)

        expect(result).to eq({ errors: "custom" })
      end
    end

    describe ".system_health" do
      it "delegates to SystemHealth.check" do
        expect(Services::Infrastructure::MonitoringService::SystemHealth).to receive(:check)
          .and_return({ health: "good" })

        result = described_class.system_health

        expect(result).to eq({ health: "good" })
      end
    end

    describe ".analytics" do
      it "delegates to Analytics.get_metrics with service and default time window" do
        expect(Services::Infrastructure::MonitoringService::Analytics).to receive(:get_metrics)
          .with(service: "sync", time_window: 1.hour)
          .and_return({ analytics: "data" })

        result = described_class.analytics(service: "sync")

        expect(result).to eq({ analytics: "data" })
      end

      it "delegates to Analytics.get_metrics with custom parameters" do
        expect(Services::Infrastructure::MonitoringService::Analytics).to receive(:get_metrics)
          .with(service: "email", time_window: 3.hours)
          .and_return({ custom: "analytics" })

        result = described_class.analytics(service: "email", time_window: 3.hours)

        expect(result).to eq({ custom: "analytics" })
      end

      it "delegates to Analytics.get_metrics without service" do
        expect(Services::Infrastructure::MonitoringService::Analytics).to receive(:get_metrics)
          .with(service: nil, time_window: 1.hour)
          .and_return({ all: "services" })

        result = described_class.analytics

        expect(result).to eq({ all: "services" })
      end
    end

    describe ".cache_metrics" do
      it "delegates to CacheMonitor.metrics" do
        expect(Services::Infrastructure::MonitoringService::CacheMonitor).to receive(:metrics)
          .and_return({ cache: "metrics" })

        result = described_class.cache_metrics

        expect(result).to eq({ cache: "metrics" })
      end
    end
  end
end
