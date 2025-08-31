# frozen_string_literal: true

require "rails_helper"

RSpec.describe Categorization::ErrorHandling, type: :unit do
  # Test the CategorizationError hierarchy
  describe "CategorizationError and Subclasses" do
    describe ::Categorization::ErrorHandling::CategorizationError do
      it "initializes with message, context, and retry_after" do
        error = described_class.new(
          "Test error",
          context: { test: "data" },
          retry_after: 5
        )

        expect(error.message).to eq("Test error")
        expect(error.context).to eq({ test: "data" })
        expect(error.retry_after).to eq(5)
      end

      it "initializes with just a message" do
        error = described_class.new("Simple error")

        expect(error.message).to eq("Simple error")
        expect(error.context).to eq({})
        expect(error.retry_after).to be_nil
      end
    end

    # Test all subclasses inherit properly
    [
      ::Categorization::ErrorHandling::PatternNotFoundError,
      ::Categorization::ErrorHandling::InvalidExpenseError,
      ::Categorization::ErrorHandling::CacheError,
      ::Categorization::ErrorHandling::DatabaseError,
      ::Categorization::ErrorHandling::TimeoutError,
      ::Categorization::ErrorHandling::RateLimitError
    ].each do |error_class|
      describe error_class do
        it "inherits from CategorizationError" do
          expect(error_class.superclass).to eq(::Categorization::ErrorHandling::CategorizationError)
        end

        it "supports context and retry_after attributes" do
          error = error_class.new(
            "Subclass error",
            context: { type: error_class.name },
            retry_after: 10
          )

          expect(error.context).to eq({ type: error_class.name })
          expect(error.retry_after).to eq(10)
        end
      end
    end
  end

  describe ::Categorization::ErrorHandling::RetryHandler do
    let(:retry_handler) { described_class }
    let(:logger) { double('Logger') }

    before do
      allow(Rails).to receive(:logger).and_return(logger)
      allow(logger).to receive(:warn)
      allow(logger).to receive(:error)
      allow(retry_handler).to receive(:sleep) # Mock sleep to speed up tests
    end

    describe ".with_retry" do
      context "when operation succeeds without retries" do
        it "executes the block and returns the result" do
          result = retry_handler.with_retry("test_operation") { "success" }
          expect(result).to eq("success")
          expect(logger).not_to have_received(:warn)
        end
      end

      context "when operation fails with retryable error" do
        context "and succeeds on retry" do
          it "retries and succeeds" do
            attempt = 0
            result = retry_handler.with_retry("test_operation") do
              attempt += 1
              raise ActiveRecord::ConnectionTimeoutError, "Timeout" if attempt == 1
              "success after retry"
            end

            expect(result).to eq("success after retry")
            expect(logger).to have_received(:warn).with(/Retry 1\/3/)
            expect(retry_handler).to have_received(:sleep)
          end
        end

        context "and fails after all retries" do
          it "raises the error after MAX_RETRIES attempts" do
            expect {
              retry_handler.with_retry("test_operation") do
                raise ActiveRecord::StatementTimeout, "Query timeout"
              end
            }.to raise_error(ActiveRecord::StatementTimeout)

            expect(logger).to have_received(:warn).exactly(3).times
            expect(logger).to have_received(:error).with(/Failed after 4 retries/)
          end

          context "with Rollbar defined" do
            before do
              stub_const("Rollbar", double)
              allow(Rollbar).to receive(:error)
            end

            it "reports to Rollbar" do
              expect {
                retry_handler.with_retry("test_operation") do
                  raise Redis::TimeoutError, "Redis timeout"
                end
              }.to raise_error(Redis::TimeoutError)

              expect(Rollbar).to have_received(:error).with(
                instance_of(Redis::TimeoutError),
                operation: "test_operation",
                retries: 4
              )
            end
          end

          context "with Sentry defined" do
            before do
              stub_const("Sentry", double)
              allow(Sentry).to receive(:capture_exception)
            end

            it "reports to Sentry" do
              expect {
                retry_handler.with_retry("test_operation") do
                  raise Net::ReadTimeout, "Network timeout"
                end
              }.to raise_error(Net::ReadTimeout)

              expect(Sentry).to have_received(:capture_exception).with(
                instance_of(Net::ReadTimeout),
                extra: { operation: "test_operation", retries: 4 }
              )
            end
          end
        end
      end

      context "when operation fails with non-retryable error" do
        it "raises immediately without retry" do
          expect {
            retry_handler.with_retry("test_operation") do
              raise StandardError, "Non-retryable error"
            end
          }.to raise_error(StandardError, "Non-retryable error")

          expect(logger).not_to have_received(:warn)
          expect(logger).to have_received(:error).with(/Failed after 1 retries/)
        end
      end
    end

    describe ".should_retry?" do
      it "returns true for connection timeout errors" do
        error = ActiveRecord::ConnectionTimeoutError.new("Connection timeout")
        expect(retry_handler.send(:should_retry?, error)).to be true
      end

      it "returns true for statement timeout errors" do
        error = ActiveRecord::StatementTimeout.new("Statement timeout")
        expect(retry_handler.send(:should_retry?, error)).to be true
      end

      it "returns true for Redis timeout errors" do
        error = Redis::TimeoutError.new("Redis timeout")
        expect(retry_handler.send(:should_retry?, error)).to be true
      end

      it "returns true for network timeout errors" do
        error = Net::ReadTimeout.new("Network timeout")
        expect(retry_handler.send(:should_retry?, error)).to be true
      end

      it "returns true for DatabaseError with connection message" do
        error = ::Categorization::ErrorHandling::DatabaseError.new("connection lost")
        expect(retry_handler.send(:should_retry?, error)).to be true
      end

      it "returns true for CacheError with timeout message" do
        error = ::Categorization::ErrorHandling::CacheError.new("cache timeout")
        expect(retry_handler.send(:should_retry?, error)).to be true
      end

      it "returns false for DatabaseError without connection/timeout" do
        error = ::Categorization::ErrorHandling::DatabaseError.new("constraint violation")
        expect(retry_handler.send(:should_retry?, error)).to be false
      end

      it "returns false for generic errors" do
        error = StandardError.new("Generic error")
        expect(retry_handler.send(:should_retry?, error)).to be false
      end
    end

    describe ".calculate_delay" do
      before do
        allow(retry_handler).to receive(:rand).and_return(0.5) # Fixed random for predictable tests
      end

      it "calculates exponential backoff with jitter" do
        # BASE_DELAY = 0.1, jitter = 10% of delay
        expect(retry_handler.send(:calculate_delay, 1)).to be_within(0.01).of(0.105) # 0.1 + 0.005
        expect(retry_handler.send(:calculate_delay, 2)).to be_within(0.01).of(0.21)  # 0.2 + 0.01
        expect(retry_handler.send(:calculate_delay, 3)).to be_within(0.01).of(0.42)  # 0.4 + 0.02
      end

      it "caps delay at MAX_DELAY" do
        expect(retry_handler.send(:calculate_delay, 10)).to eq(5.0) # MAX_DELAY
      end
    end
  end

  describe ::Categorization::ErrorHandling::FallbackStrategy do
    let(:fallback_strategy) { described_class }
    let(:logger) { double('Logger') }
    let(:cache) { double('Cache') }

    before do
      allow(Rails).to receive(:logger).and_return(logger)
      allow(Rails).to receive(:cache).and_return(cache)
      allow(logger).to receive(:warn)
      allow(cache).to receive(:increment)
    end

    describe ".execute" do
      context "when primary action succeeds" do
        it "returns primary action result without calling fallback" do
          primary = -> { "primary result" }
          fallback = -> { "fallback result" }

          result = fallback_strategy.execute(primary, fallback, { service: "test" })

          expect(result).to eq("primary result")
          expect(logger).not_to have_received(:warn)
          expect(cache).not_to have_received(:increment)
        end
      end

      context "when primary action fails" do
        it "executes fallback action" do
          primary = -> { raise StandardError, "Primary failed" }
          fallback = -> { "fallback result" }

          result = fallback_strategy.execute(primary, fallback, { service: "test" })

          expect(result).to eq("fallback result")
          expect(logger).to have_received(:warn).with(/Primary action failed.*using fallback/)
        end

        it "increments fallback counter with context" do
          primary = -> { raise StandardError, "Primary failed" }
          fallback = -> { "fallback" }

          fallback_strategy.execute(primary, fallback, { service: "categorization" })

          expect(cache).to have_received(:increment).with(
            "fallback:categorization:count",
            1,
            expires_in: 1.hour
          )
        end

        it "raises if fallback also fails" do
          primary = -> { raise StandardError, "Primary failed" }
          fallback = -> { raise StandardError, "Fallback failed" }

          expect {
            fallback_strategy.execute(primary, fallback, { service: "test" })
          }.to raise_error(StandardError, "Fallback failed")
        end
      end
    end
  end

  describe ::Categorization::ErrorHandling::ErrorRecovery do
    let(:error_recovery) { described_class }
    let(:logger) { double('Logger') }
    let(:cache) { double('Cache') }

    before do
      allow(Rails).to receive(:logger).and_return(logger)
      allow(Rails).to receive(:cache).and_return(cache)
      allow(logger).to receive(:error)
      allow(logger).to receive(:info)
    end

    describe ".recover_from_cache_failure" do
      before do
        cache_warmer = Class.new do
          def self.warm_critical_paths; end
        end
        stub_const("Categorization::ErrorHandling::CacheWarmer", cache_warmer)
        allow(cache_warmer).to receive(:warm_critical_paths)
        allow(cache).to receive(:clear)
      end

      it "clears cache and warms critical paths" do
        result = error_recovery.recover_from_cache_failure

        expect(logger).to have_received(:error).with(/Cache failure detected/)
        expect(cache).to have_received(:clear)
        expect(Categorization::ErrorHandling::CacheWarmer).to have_received(:warm_critical_paths)
        expect(result).to eq({
          status: :degraded,
          message: "Operating without cache"
        })
      end
    end

    describe ".recover_from_database_failure" do
      before do
        allow(ActiveRecord::Base).to receive(:connected_to?)
      end

      context "when read replica is available" do
        before do
          allow(ActiveRecord::Base).to receive(:connected_to?).with(role: :reading).and_return(true)
        end

        it "switches to read replica" do
          result = error_recovery.recover_from_database_failure

          expect(logger).to have_received(:error).with(/Database failure detected/)
          expect(logger).to have_received(:info).with(/Switching to read replica/)
          expect(result).to eq({
            status: :degraded,
            message: "Using read replica"
          })
        end
      end

      context "when read replica is not available" do
        before do
          allow(ActiveRecord::Base).to receive(:connected_to?).with(role: :reading).and_return(false)
        end

        it "falls back to cache-only mode" do
          result = error_recovery.recover_from_database_failure

          expect(logger).to have_received(:error).with(/Database failure detected/)
          expect(result).to eq({
            status: :degraded,
            message: "Database unavailable, using cache only"
          })
        end
      end
    end
  end

  describe ::Categorization::ErrorHandling::ErrorContext do
    let(:error_context) { described_class }
    let(:expense) { build(:expense, id: 123, merchant_name: "Test Merchant", amount: 100.50) }
    let(:logger) { double('Logger') }

    before do
      allow(Rails).to receive(:env).and_return("test")
      allow(Socket).to receive(:gethostname).and_return("test-host")
      allow(Rails).to receive(:logger).and_return(logger)
      allow(logger).to receive(:tagged).and_yield
      allow(logger).to receive(:info)
      allow(logger).to receive(:error)
    end

    describe ".build" do
      context "with full expense data" do
        it "builds complete context" do
          context = error_context.build(
            expense: expense,
            operation: "categorize",
            metadata: { attempt: 1 }
          )

          expect(context).to include(
            expense_id: 123,
            merchant: "Test Merchant",
            amount: 100.50,
            operation: "categorize",
            rails_env: "test",
            host: "test-host",
            metadata: { attempt: 1 }
          )
          expect(context[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        end
      end

      context "with nil expense" do
        it "builds context with nil values" do
          context = error_context.build(
            expense: nil,
            operation: "batch_process",
            metadata: {}
          )

          expect(context).to include(
            expense_id: nil,
            merchant: nil,
            amount: nil,
            operation: "batch_process"
          )
        end
      end

      context "with partial expense data" do
        it "handles missing attributes gracefully" do
          partial_expense = double(id: 456, merchant_name: nil, amount: nil)

          context = error_context.build(
            expense: partial_expense,
            operation: "validate",
            metadata: { source: "api" }
          )

          expect(context).to include(
            expense_id: 456,
            merchant: nil,
            amount: nil,
            metadata: { source: "api" }
          )
        end
      end
    end

    describe ".log_with_context" do
      it "logs with tagged context and JSON format" do
        context = {
          operation: "categorize",
          expense_id: 123,
          merchant: "Test"
        }

        error_context.log_with_context(:info, "Test message", context)

        expect(logger).to have_received(:tagged).with("categorize")
        expect(logger).to have_received(:info).with(/Test message.*Context:.*categorize/)
      end

      it "supports different log levels" do
        context = { operation: "error_test" }

        error_context.log_with_context(:error, "Error occurred", context)

        expect(logger).to have_received(:error).with(/Error occurred.*Context:/)
      end
    end
  end

  describe ::Categorization::ErrorHandling::HealthCheck do
    let(:health_check) { described_class }

    before do
      allow(Rails).to receive(:cache).and_return(double)
      allow(Time).to receive(:current).and_return(Time.parse("2024-01-15 10:00:00"))
    end

    describe ".check" do
      context "when all checks are healthy" do
        before do
          allow(health_check).to receive(:check_database).and_return({
            status: :healthy,
            response_time_ms: 1
          })
          allow(health_check).to receive(:check_cache).and_return({
            status: :healthy
          })
          allow(health_check).to receive(:check_patterns).and_return({
            status: :healthy,
            active_patterns: 50
          })
          allow(health_check).to receive(:check_performance).and_return({
            status: :healthy,
            avg_response_ms: 8
          })
        end

        it "returns overall healthy status" do
          result = health_check.check

          expect(result[:status]).to eq(:healthy)
          expect(result[:timestamp]).to match(/2024-01-15T10:00:00/)
          expect(result[:checks]).to include(
            database: { status: :healthy, response_time_ms: 1 },
            cache: { status: :healthy },
            patterns: { status: :healthy, active_patterns: 50 },
            performance: { status: :healthy, avg_response_ms: 8 }
          )
        end
      end

      context "when some checks are degraded" do
        before do
          allow(health_check).to receive(:check_database).and_return({ status: :healthy })
          allow(health_check).to receive(:check_cache).and_return({ status: :degraded })
          allow(health_check).to receive(:check_patterns).and_return({ status: :healthy })
          allow(health_check).to receive(:check_performance).and_return({ status: :degraded })
        end

        it "returns overall degraded status" do
          result = health_check.check
          expect(result[:status]).to eq(:degraded)
        end
      end

      context "when any check is critical" do
        before do
          allow(health_check).to receive(:check_database).and_return({ status: :critical })
          allow(health_check).to receive(:check_cache).and_return({ status: :healthy })
          allow(health_check).to receive(:check_patterns).and_return({ status: :degraded })
          allow(health_check).to receive(:check_performance).and_return({ status: :healthy })
        end

        it "returns overall critical status" do
          result = health_check.check
          expect(result[:status]).to eq(:critical)
        end
      end
    end

    describe ".check_database" do
      context "when database is accessible" do
        before do
          pattern_double = double
          allow(CategorizationPattern).to receive(:limit).with(1).and_return(pattern_double)
          allow(pattern_double).to receive(:first).and_return(double)
        end

        it "returns healthy status" do
          result = health_check.send(:check_database)
          expect(result[:status]).to eq(:healthy)
          expect(result[:response_time_ms]).to eq(1)
        end
      end

      context "when database raises error" do
        before do
          allow(CategorizationPattern).to receive(:limit).and_raise(
            ActiveRecord::ConnectionNotEstablished, "Database connection failed"
          )
        end

        it "returns critical status with error" do
          result = health_check.send(:check_database)
          expect(result[:status]).to eq(:critical)
          expect(result[:error]).to include("Database connection failed")
        end
      end
    end

    describe ".check_cache" do
      let(:cache) { double('Cache') }

      before do
        allow(Rails).to receive(:cache).and_return(cache)
      end

      context "when cache is working" do
        before do
          allow(cache).to receive(:write).with("health_check", "ok", expires_in: 1.minute)
          allow(cache).to receive(:read).with("health_check").and_return("ok")
        end

        it "returns healthy status" do
          result = health_check.send(:check_cache)
          expect(result[:status]).to eq(:healthy)
        end
      end

      context "when cache read returns different value" do
        before do
          allow(cache).to receive(:write)
          allow(cache).to receive(:read).with("health_check").and_return("not_ok")
        end

        it "returns degraded status" do
          result = health_check.send(:check_cache)
          expect(result[:status]).to eq(:degraded)
        end
      end

      context "when cache raises error" do
        before do
          allow(cache).to receive(:write).and_raise(Redis::CannotConnectError, "Redis down")
        end

        it "returns critical status with error" do
          result = health_check.send(:check_cache)
          expect(result[:status]).to eq(:critical)
          expect(result[:error]).to include("Redis down")
        end
      end
    end

    describe ".check_patterns" do
      context "when active patterns exist" do
        before do
          active_scope = double
          allow(CategorizationPattern).to receive(:active).and_return(active_scope)
          allow(active_scope).to receive(:count).and_return(25)
        end

        it "returns healthy status with count" do
          result = health_check.send(:check_patterns)
          expect(result[:status]).to eq(:healthy)
          expect(result[:active_patterns]).to eq(25)
        end
      end

      context "when no active patterns" do
        before do
          active_scope = double
          allow(CategorizationPattern).to receive(:active).and_return(active_scope)
          allow(active_scope).to receive(:count).and_return(0)
        end

        it "returns degraded status" do
          result = health_check.send(:check_patterns)
          expect(result[:status]).to eq(:degraded)
          expect(result[:message]).to eq("No active patterns")
        end
      end

      context "when pattern check raises error" do
        before do
          allow(CategorizationPattern).to receive(:active).and_raise(
            StandardError, "Pattern check failed"
          )
        end

        it "returns critical status with error" do
          result = health_check.send(:check_patterns)
          expect(result[:status]).to eq(:critical)
          expect(result[:error]).to include("Pattern check failed")
        end
      end
    end

    describe ".check_performance" do
      let(:tracker) { double('PerformanceTracker') }

      before do
        # Stub the constant in the Categorization module namespace
        stub_const("Categorization::PerformanceTracker", Class.new)
        allow(Categorization::PerformanceTracker).to receive(:new).and_return(tracker)
      end

      context "when performance is good (<=10ms)" do
        before do
          allow(tracker).to receive(:summary).and_return({
            categorizations: { avg_ms: 8 }
          })
        end

        it "returns healthy status" do
          result = health_check.send(:check_performance)
          expect(result).to eq({ status: :healthy, avg_response_ms: 8 })
        end
      end

      context "when performance is degraded (10-25ms)" do
        before do
          allow(tracker).to receive(:summary).and_return({
            categorizations: { avg_ms: 20 }
          })
        end

        it "returns degraded status" do
          result = health_check.send(:check_performance)
          expect(result).to eq({ status: :degraded, avg_response_ms: 20 })
        end
      end

      context "when performance is critical (>25ms)" do
        before do
          allow(tracker).to receive(:summary).and_return({
            categorizations: { avg_ms: 30 }
          })
        end

        it "returns critical status" do
          result = health_check.send(:check_performance)
          expect(result).to eq({ status: :critical, avg_response_ms: 30 })
        end
      end

      context "when no metrics available" do
        before do
          allow(tracker).to receive(:summary).and_return({})
        end

        it "handles missing metrics gracefully" do
          result = health_check.send(:check_performance)
          expect(result).to eq({ status: :healthy, avg_response_ms: 0 })
        end
      end
    end
  end
end
