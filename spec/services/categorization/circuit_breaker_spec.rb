# frozen_string_literal: true

require "rails_helper"

RSpec.describe Categorization::Orchestrator::CircuitBreaker, type: :service, unit: true do
  let(:circuit_breaker) do
    described_class.new(
      failure_threshold: 3,
      timeout: 0.5.seconds # Short timeout for testing
    )
  end

  # Helper method to simulate time passing without actual sleep
  def travel(duration)
    new_time = Time.current + duration
    allow(Time).to receive(:current).and_return(new_time)
  end

  describe "#call" do
    context "when circuit is closed" do
      it "executes the block successfully" do
        result = circuit_breaker.call { "success" }
        expect(result).to eq("success")
        expect(circuit_breaker.state).to eq(:closed)
      end

      it "remains closed after successful calls" do
        5.times do
          circuit_breaker.call { "success" }
        end

        expect(circuit_breaker.state).to eq(:closed)
      end
    end

    context "when failures occur" do
      it "opens circuit after reaching failure threshold" do
        # Generate failures up to threshold
        3.times do
          expect {
            circuit_breaker.call { raise StandardError, "Test error" }
          }.to raise_error(StandardError)
        end

        expect(circuit_breaker.state).to eq(:open)
      end

      it "counts failures correctly" do
        # First two failures - circuit still closed
        2.times do
          expect {
            circuit_breaker.call { raise StandardError, "Test error" }
          }.to raise_error(StandardError)
        end

        expect(circuit_breaker.state).to eq(:closed)

        # Third failure - circuit opens
        expect {
          circuit_breaker.call { raise StandardError, "Test error" }
        }.to raise_error(StandardError)

        expect(circuit_breaker.state).to eq(:open)
      end
    end

    context "when circuit is open" do
      before do
        # Open the circuit
        3.times do
          begin
            circuit_breaker.call { raise StandardError, "Test error" }
          rescue StandardError
            # Expected
          end
        end
      end

      it "raises CircuitOpenError without executing block" do
        executed = false

        expect {
          circuit_breaker.call { executed = true }
        }.to raise_error(Categorization::Orchestrator::CircuitBreaker::CircuitOpenError)

        expect(executed).to be false
      end

      it "transitions to half-open after timeout" do
        expect(circuit_breaker.state).to eq(:open)

        # Simulate time passing using time travel
        travel(0.6.seconds)

        # Should transition to half-open and allow one request
        result = circuit_breaker.call { "recovery" }
        expect(result).to eq("recovery")
        expect(circuit_breaker.state).to eq(:closed)
      end
    end

    context "when circuit is half-open" do
      before do
        # Open the circuit
        3.times do
          begin
            circuit_breaker.call { raise StandardError }
          rescue StandardError
            # Expected
          end
        end

        # Simulate timeout to transition to half-open
        travel(0.6.seconds)
      end

      it "closes circuit on successful test request" do
        result = circuit_breaker.call { "success" }

        expect(result).to eq("success")
        expect(circuit_breaker.state).to eq(:closed)
      end

      it "reopens circuit on failed test request" do
        expect {
          circuit_breaker.call { raise StandardError, "Still failing" }
        }.to raise_error(StandardError)

        expect(circuit_breaker.state).to eq(:open)
      end

      it "allows limited requests in half-open state" do
        # First request should succeed
        circuit_breaker.call { "success" }

        # Circuit should now be closed
        expect(circuit_breaker.state).to eq(:closed)

        # Additional requests should work normally
        result = circuit_breaker.call { "another success" }
        expect(result).to eq("another success")
      end
    end
  end

  describe "#record_failure" do
    it "increments failure count" do
      expect(circuit_breaker.state).to eq(:closed)

      circuit_breaker.record_failure
      expect(circuit_breaker.state).to eq(:closed)

      circuit_breaker.record_failure
      expect(circuit_breaker.state).to eq(:closed)

      circuit_breaker.record_failure
      expect(circuit_breaker.state).to eq(:open)
    end
  end

  describe "#reset!" do
    it "resets circuit to initial state" do
      # Open the circuit
      3.times { circuit_breaker.record_failure }
      expect(circuit_breaker.state).to eq(:open)

      # Reset
      circuit_breaker.reset!

      expect(circuit_breaker.state).to eq(:closed)

      # Should work normally again
      result = circuit_breaker.call { "success" }
      expect(result).to eq("success")
    end
  end

  describe "thread safety" do
    it "handles concurrent failures safely" do
      threads = 10.times.map do
        Thread.new do
          begin
            circuit_breaker.call { raise StandardError }
          rescue StandardError, Categorization::Orchestrator::CircuitBreaker::CircuitOpenError
            # Expected
          end
        end
      end

      threads.each(&:join)

      # Circuit should be open after concurrent failures
      expect(circuit_breaker.state).to eq(:open)
    end

    it "handles concurrent successful calls safely" do
      results = Concurrent::Array.new

      threads = 10.times.map do |i|
        Thread.new do
          result = circuit_breaker.call { "success_#{i}" }
          results << result
        end
      end

      threads.each(&:join)

      expect(results.size).to eq(10)
      expect(circuit_breaker.state).to eq(:closed)
    end

    it "handles mixed success and failure safely" do
      errors = Concurrent::Array.new
      successes = Concurrent::Array.new

      threads = 20.times.map do |i|
        Thread.new do
          begin
            if i.even?
              result = circuit_breaker.call { "success" }
              successes << result
            else
              circuit_breaker.call { raise StandardError }
            end
          rescue StandardError, Categorization::Orchestrator::CircuitBreaker::CircuitOpenError => e
            errors << e
          end
        end
      end

      threads.each(&:join)

      # Should have recorded both successes and failures
      expect(successes.size).to be > 0
      expect(errors.size).to be > 0
    end
  end

  describe "integration with orchestrator" do
    let(:orchestrator) do
      Categorization::Orchestrator.new(
        circuit_breaker: circuit_breaker
      )
    end

    let(:expense) { create(:expense) }

    it "protects categorization operations" do
      # Simulate service failure
      allow(orchestrator.pattern_cache).to receive(:get_patterns_for_expense)
        .and_raise(StandardError, "Service unavailable")

      # First few failures should execute and fail normally
      3.times do
        result = orchestrator.categorize(expense)
        expect(result).to be_failed
      end

      # Circuit should now be open
      result = orchestrator.categorize(expense)
      expect(result).to be_failed
      expect(result.error).to include("Service temporarily unavailable")
    end

    it "recovers when service becomes available" do
      # Initially working
      allow(orchestrator.pattern_cache).to receive(:get_patterns_for_expense)
        .and_return([])

      result = orchestrator.categorize(expense)
      expect(result).to be_no_match # Working but no patterns

      # Simulate failures
      allow(orchestrator.pattern_cache).to receive(:get_patterns_for_expense)
        .and_raise(StandardError, "Service down")

      3.times do
        orchestrator.categorize(expense)
      end

      # Circuit open
      result = orchestrator.categorize(expense)
      expect(result.error).to include("Service temporarily unavailable")

      # Service recovers
      allow(orchestrator.pattern_cache).to receive(:get_patterns_for_expense)
        .and_return([])

      # Simulate time passing
      travel(0.6.seconds)

      # Should work again
      result = orchestrator.categorize(expense)
      expect(result).to be_no_match
    end
  end

  describe "configuration" do
    it "respects custom failure threshold" do
      cb = described_class.new(failure_threshold: 5, timeout: 1.second)

      # Should require 5 failures to open
      4.times do
        begin
          cb.call { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      expect(cb.state).to eq(:closed)

      # Fifth failure opens circuit
      expect { cb.call { raise StandardError } }.to raise_error(StandardError)
      expect(cb.state).to eq(:open)
    end

    it "respects custom timeout duration" do
      cb = described_class.new(failure_threshold: 1, timeout: 2.seconds)

      # Open circuit
      expect { cb.call { raise StandardError } }.to raise_error(StandardError)
      expect(cb.state).to eq(:open)

      # Mock time for first check
      travel(1.second)
      expect { cb.call { "test" } }.to raise_error(
        Categorization::Orchestrator::CircuitBreaker::CircuitOpenError
      )

      # Mock time for successful transition
      travel(1.1.seconds)
      result = cb.call { "success" }
      expect(result).to eq("success")
    end
  end
end
