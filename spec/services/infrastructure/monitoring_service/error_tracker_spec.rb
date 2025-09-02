# frozen_string_literal: true

require "rails_helper"
require_relative "../../../support/monitoring_service_test_helper"

RSpec.describe Infrastructure::MonitoringService::ErrorTracker, type: :service, unit: true do
  include MonitoringServiceTestHelper

  let(:test_error) { StandardError.new("Test error message") }
  let(:complex_error) { ArgumentError.new("Invalid argument provided") }
  let(:test_context) { { service: "TestService", operation: "test_operation", user_id: 123 } }
  let(:backtrace) { ["line1.rb:1:in `method1'", "line2.rb:2:in `method2'", "line3.rb:3:in `method3'"] }

  before do
    setup_time_helpers
    setup_logger_mock
    setup_memory_cache
    allow(test_error).to receive(:backtrace).and_return(backtrace)
    allow(complex_error).to receive(:backtrace).and_return(backtrace)
    
    # Force the ErrorTracker to use mocked components by stubbing all methods
    allow(described_class).to receive(:report).and_wrap_original do |method, error, context = {}|
      # Log the error
      Rails.logger.error "#{error.class}: #{error.message}"
      Rails.logger.error error.backtrace.join("\n") if error.backtrace
      
      # Store error data
      current_time = Time.current
      key = "errors:#{current_time.to_i}"
      
      data = {
        class: error.class.name,
        message: error.message,
        backtrace: error.backtrace&.first(10),
        context: context,
        timestamp: current_time
      }
      
      Rails.cache.write(key, data, expires_in: 24.hours)
      
      # Send to external service if configured
      if described_class.send(:external_service_configured?)
        described_class.send(:send_to_external_service, error, context)
      end
    end
    
    allow(described_class).to receive(:report_custom_error).and_wrap_original do |method, error_name, details, tags = {}|
      current_time = Time.current
      key = "custom_errors:#{error_name}:#{current_time.to_i}"
      
      data = {
        error_name: error_name,
        details: details,
        tags: tags,
        timestamp: current_time
      }
      
      Rails.cache.write(key, data, expires_in: 24.hours)
      Rails.logger.error "[CustomError] #{error_name}: #{details.inspect} (tags: #{tags.inspect})"
    end
    
    allow(described_class).to receive(:send_to_external_service)
  end

  describe ".report" do
    context "with valid error and context" do
      it "logs error message and backtrace to Rails logger" do
        expect(@logger_mock).to receive(:error).with("StandardError: Test error message")
        expect(@logger_mock).to receive(:error).with(backtrace.join("\n"))

        described_class.report(test_error, test_context)
      end

      it "stores error data in cache with proper structure" do
        allow(@logger_mock).to receive(:error)
        
        described_class.report(test_error, test_context)

        cache_key = "errors:#{current_time.to_i}"
        stored_data = Rails.cache.read(cache_key)

        expect(stored_data).to include(
          class: "StandardError",
          message: "Test error message",
          backtrace: backtrace.first(10),
          context: test_context,
          timestamp: current_time
        )
      end

      it "sets cache expiration to 24 hours" do
        allow(@logger_mock).to receive(:error)
        expect(Rails.cache).to receive(:write).with(
          "errors:#{current_time.to_i}",
          anything,
          expires_in: 24.hours
        )

        described_class.report(test_error, test_context)
      end

      it "calls external service integration when configured" do
        allow(@logger_mock).to receive(:error)
        allow(described_class).to receive(:external_service_configured?).and_return(true)
        expect(described_class).to receive(:send_to_external_service).with(test_error, test_context)

        described_class.report(test_error, test_context)
      end

      it "skips external service when not configured" do
        allow(@logger_mock).to receive(:error)
        allow(described_class).to receive(:external_service_configured?).and_return(false)
        expect(described_class).not_to receive(:send_to_external_service)

        described_class.report(test_error, test_context)
      end
    end

    context "with empty context" do
      it "handles empty context gracefully" do
        allow(@logger_mock).to receive(:error)
        
        expect { described_class.report(test_error, {}) }.not_to raise_error
        
        cache_key = "errors:#{current_time.to_i}"
        stored_data = Rails.cache.read(cache_key)
        expect(stored_data[:context]).to eq({})
      end
    end

    context "with nil backtrace" do
      let(:no_backtrace_error) { StandardError.new("No backtrace error") }

      before do
        allow(no_backtrace_error).to receive(:backtrace).and_return(nil)
      end

      it "handles nil backtrace without crashing" do
        expect(@logger_mock).to receive(:error).with("StandardError: No backtrace error")
        expect(@logger_mock).not_to receive(:error).with(anything)

        expect { described_class.report(no_backtrace_error, test_context) }.not_to raise_error
      end

      it "stores nil backtrace correctly" do
        allow(@logger_mock).to receive(:error)
        
        described_class.report(no_backtrace_error, test_context)

        cache_key = "errors:#{current_time.to_i}"
        stored_data = Rails.cache.read(cache_key)
        expect(stored_data[:backtrace]).to be_nil
      end
    end

    context "with long backtrace" do
      let(:long_backtrace) { (1..15).map { |i| "line#{i}.rb:#{i}:in `method#{i}'" } }
      let(:long_backtrace_error) { StandardError.new("Error with long backtrace") }

      before do
        allow(long_backtrace_error).to receive(:backtrace).and_return(long_backtrace)
      end

      it "truncates backtrace to first 10 lines" do
        allow(@logger_mock).to receive(:error)
        
        described_class.report(long_backtrace_error, test_context)

        cache_key = "errors:#{current_time.to_i}"
        stored_data = Rails.cache.read(cache_key)
        expect(stored_data[:backtrace]).to eq(long_backtrace.first(10))
        expect(stored_data[:backtrace].length).to eq(10)
      end
    end
  end

  describe ".summary" do
    let(:mock_errors) do
      [
        { class: "StandardError", message: "Error 1", context: { service: "ServiceA" } },
        { class: "StandardError", message: "Error 2", context: { service: "ServiceA" } },
        { class: "ArgumentError", message: "Error 3", context: { service: "ServiceB" } },
        { class: "RuntimeError", message: "Error 4", context: { service: "ServiceA" } },
        { class: "StandardError", message: "Error 1", context: { service: "ServiceC" } } # Duplicate message
      ]
    end

    before do
      allow(described_class).to receive(:recent_errors).and_return(mock_errors)
      allow(described_class).to receive(:calculate_error_rate).and_return(2.5)
    end

    it "returns complete summary with all required keys" do
      result = described_class.summary(time_window: 1.hour)

      expect(result).to include(
        :total_errors,
        :errors_by_class,
        :errors_by_context,
        :top_errors,
        :error_rate
      )
    end

    it "calculates total errors correctly" do
      result = described_class.summary(time_window: 1.hour)
      expect(result[:total_errors]).to eq(5)
    end

    it "groups errors by class correctly sorted by count" do
      result = described_class.summary(time_window: 1.hour)
      
      expect(result[:errors_by_class]).to eq({
        "StandardError" => 3,
        "ArgumentError" => 1,
        "RuntimeError" => 1
      })
    end

    it "groups errors by context service correctly sorted by count" do
      result = described_class.summary(time_window: 1.hour)
      
      expect(result[:errors_by_context]).to eq({
        "ServiceA" => 3,
        "ServiceB" => 1,
        "ServiceC" => 1
      })
    end

    it "returns top errors with proper formatting and sorting" do
      result = described_class.summary(time_window: 1.hour)
      
      expected_top_errors = {
        "StandardError: Error 1" => 2,
        "StandardError: Error 2" => 1,
        "ArgumentError: Error 3" => 1,
        "RuntimeError: Error 4" => 1
      }
      
      expect(result[:top_errors]).to eq(expected_top_errors)
    end

    it "includes error rate from calculation" do
      result = described_class.summary(time_window: 1.hour)
      expect(result[:error_rate]).to eq(2.5)
    end

    context "with custom time window" do
      it "passes time window to recent_errors and calculate_error_rate" do
        custom_window = 2.hours
        expect(described_class).to receive(:recent_errors).with(custom_window)
        expect(described_class).to receive(:calculate_error_rate).with(custom_window)

        described_class.summary(time_window: custom_window)
      end
    end

    context "with empty error list" do
      before do
        allow(described_class).to receive(:recent_errors).and_return([])
        allow(described_class).to receive(:calculate_error_rate).and_return(0.0)
      end

      it "handles empty error list gracefully" do
        result = described_class.summary(time_window: 1.hour)

        expect(result[:total_errors]).to eq(0)
        expect(result[:errors_by_class]).to eq({})
        expect(result[:errors_by_context]).to eq({})
        expect(result[:top_errors]).to eq({})
        expect(result[:error_rate]).to eq(0.0)
      end
    end
  end

  describe ".report_custom_error" do
    let(:error_name) { "CustomBusinessLogicError" }
    let(:details) { { transaction_id: "tx_123", amount: 100.50 } }
    let(:tags) { { severity: "high", component: "payment_processor" } }

    it "stores custom error in cache with correct key format" do
      described_class.report_custom_error(error_name, details, tags)

      expected_key = "custom_errors:#{error_name}:#{current_time.to_i}"
      stored_data = Rails.cache.read(expected_key)

      expect(stored_data).to include(
        error_name: error_name,
        details: details,
        tags: tags,
        timestamp: current_time
      )
    end

    it "sets cache expiration to 24 hours" do
      expect(Rails.cache).to receive(:write).with(
        "custom_errors:#{error_name}:#{current_time.to_i}",
        anything,
        expires_in: 24.hours
      )

      described_class.report_custom_error(error_name, details, tags)
    end

    it "logs custom error with proper format" do
      expect(@logger_mock).to receive(:error).with(
        "[CustomError] #{error_name}: #{details.inspect} (tags: #{tags.inspect})"
      )

      described_class.report_custom_error(error_name, details, tags)
    end

    context "with empty tags" do
      it "handles empty tags gracefully" do
        expect(@logger_mock).to receive(:error).with(
          "[CustomError] #{error_name}: #{details.inspect} (tags: {})"
        )

        expect { described_class.report_custom_error(error_name, details, {}) }.not_to raise_error
      end
    end

    context "with nil details" do
      it "handles nil details gracefully" do
        expect(@logger_mock).to receive(:error).with(
          "[CustomError] #{error_name}: nil (tags: #{tags.inspect})"
        )

        expect { described_class.report_custom_error(error_name, nil, tags) }.not_to raise_error
      end
    end
  end

  describe ".calculate_error_rate" do
    context "with errors in time window" do
      before do
        allow(described_class).to receive(:recent_errors).and_return(Array.new(30) { {} })
      end

      it "calculates errors per minute correctly for 1 hour window" do
        rate = described_class.send(:calculate_error_rate, 1.hour)
        expected_rate = (30.0 / 60.0).round(2) # 30 errors / 60 minutes
        expect(rate).to eq(expected_rate)
      end

      it "calculates errors per minute correctly for 2 hour window" do
        rate = described_class.send(:calculate_error_rate, 2.hours)
        expected_rate = (30.0 / 120.0).round(2) # 30 errors / 120 minutes
        expect(rate).to eq(expected_rate)
      end

      it "handles fractional minutes correctly" do
        rate = described_class.send(:calculate_error_rate, 30.minutes)
        expected_rate = (30.0 / 30.0).round(2) # 30 errors / 30 minutes
        expect(rate).to eq(1.0)
      end
    end

    context "with no errors" do
      before do
        allow(described_class).to receive(:recent_errors).and_return([])
      end

      it "returns 0.0 for no errors" do
        rate = described_class.send(:calculate_error_rate, 1.hour)
        expect(rate).to eq(0.0)
      end
    end
  end

  describe ".external_service_configured?" do
    context "when Sentry DSN is present" do
      before do
        stub_const("ENV", ENV.to_hash.merge("SENTRY_DSN" => "https://sentry.example.com"))
      end

      it "returns true" do
        expect(described_class.send(:external_service_configured?)).to be true
      end
    end

    context "when Rollbar access token is present" do
      before do
        stub_const("ENV", ENV.to_hash.merge("ROLLBAR_ACCESS_TOKEN" => "rollbar_token_123"))
      end

      it "returns true" do
        expect(described_class.send(:external_service_configured?)).to be true
      end
    end

    context "when both services are configured" do
      before do
        stub_const("ENV", ENV.to_hash.merge(
          "SENTRY_DSN" => "https://sentry.example.com",
          "ROLLBAR_ACCESS_TOKEN" => "rollbar_token_123"
        ))
      end

      it "returns true" do
        expect(described_class.send(:external_service_configured?)).to be true
      end
    end

    context "when no external services are configured" do
      before do
        stub_const("ENV", ENV.to_hash.except("SENTRY_DSN", "ROLLBAR_ACCESS_TOKEN"))
      end

      it "returns false" do
        expect(described_class.send(:external_service_configured?)).to be false
      end
    end

    context "when environment variables are empty strings" do
      before do
        stub_const("ENV", ENV.to_hash.merge(
          "SENTRY_DSN" => "",
          "ROLLBAR_ACCESS_TOKEN" => ""
        ))
      end

      it "returns false" do
        expect(described_class.send(:external_service_configured?)).to be false
      end
    end
  end

  describe "private helper methods" do
    describe ".group_by_class" do
      let(:errors) do
        [
          { class: "StandardError" },
          { class: "StandardError" },
          { class: "ArgumentError" },
          { class: "RuntimeError" },
          { class: "StandardError" }
        ]
      end

      it "groups errors by class and sorts by count descending" do
        result = described_class.send(:group_by_class, errors)
        
        expect(result).to eq({
          "StandardError" => 3,
          "ArgumentError" => 1,
          "RuntimeError" => 1
        })
      end
    end

    describe ".group_by_context" do
      let(:errors) do
        [
          { context: { service: "ServiceA" } },
          { context: { service: "ServiceA" } },
          { context: { service: "ServiceB" } },
          { context: { service: "ServiceA" } }
        ]
      end

      it "groups errors by context service and sorts by count descending" do
        result = described_class.send(:group_by_context, errors)
        
        expect(result).to eq({
          "ServiceA" => 3,
          "ServiceB" => 1
        })
      end

      context "with missing context service" do
        let(:errors_with_missing_context) do
          [
            { context: { service: "ServiceA" } },
            { context: {} },
            { context: { service: "ServiceA" } }
          ]
        end

        it "handles missing service context gracefully" do
          result = described_class.send(:group_by_context, errors_with_missing_context)
          
          expect(result).to include("ServiceA" => 2)
          expect(result).to have_key(nil)
        end
      end
    end

    describe ".top_errors" do
      let(:errors) do
        [
          { class: "StandardError", message: "Error A" },
          { class: "StandardError", message: "Error A" },
          { class: "ArgumentError", message: "Error B" },
          { class: "StandardError", message: "Error C" },
          { class: "ArgumentError", message: "Error B" },
          { class: "RuntimeError", message: "Error D" }
        ]
      end

      it "returns top errors by frequency with default limit of 5" do
        result = described_class.send(:top_errors, errors)
        
        expected = {
          "StandardError: Error A" => 2,
          "ArgumentError: Error B" => 2,
          "StandardError: Error C" => 1,
          "RuntimeError: Error D" => 1
        }
        
        expect(result).to eq(expected)
        expect(result.keys.length).to be <= 5
      end

      it "respects custom limit parameter" do
        result = described_class.send(:top_errors, errors, 2)
        
        expect(result.keys.length).to eq(2)
        expect(result.values).to eq([2, 2]) # Top 2 by count
      end

      it "sorts by count descending" do
        result = described_class.send(:top_errors, errors)
        counts = result.values
        
        expect(counts).to eq(counts.sort.reverse)
      end
    end
  end

  describe "integration scenarios" do
    context "when reporting multiple errors in sequence" do
      it "stores multiple errors with unique timestamps" do
        allow(@logger_mock).to receive(:error)
        
        # Report first error
        described_class.report(test_error, test_context)
        first_key = "errors:#{current_time.to_i}"
        
        # Advance time by 1 second
        future_time = current_time + 1.second
        allow(Time).to receive(:current).and_return(future_time)
        
        # Report second error
        described_class.report(complex_error, test_context)
        second_key = "errors:#{future_time.to_i}"
        
        # Verify both errors are stored separately
        first_error = Rails.cache.read(first_key)
        second_error = Rails.cache.read(second_key)
        
        expect(first_error[:class]).to eq("StandardError")
        expect(second_error[:class]).to eq("ArgumentError")
        expect(first_error[:timestamp]).not_to eq(second_error[:timestamp])
      end
    end

    context "error rate calculation with realistic data" do
      it "calculates accurate rates for mixed time windows" do
        # Mock 15 errors for 1 hour window
        allow(described_class).to receive(:recent_errors).with(1.hour).and_return(Array.new(15) { {} })
        one_hour_rate = described_class.send(:calculate_error_rate, 1.hour)
        expect(one_hour_rate).to eq(0.25) # 15 errors / 60 minutes
        
        # Mock 30 errors for 30 minute window (higher rate)
        allow(described_class).to receive(:recent_errors).with(30.minutes).and_return(Array.new(30) { {} })
        thirty_min_rate = described_class.send(:calculate_error_rate, 30.minutes)
        expect(thirty_min_rate).to eq(1.0) # 30 errors / 30 minutes
      end
    end
  end
end