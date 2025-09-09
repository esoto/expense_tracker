# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Categorization::Monitoring::DashboardAdapter do
  let(:adapter) { described_class.new }
  let(:adapter_with_override) { described_class.new(strategy_override: :original) }

  describe '#initialize' do
    it 'creates a new adapter instance' do
      expect(adapter).to be_a(described_class)
    end

    it 'accepts strategy override' do
      expect(adapter_with_override.strategy_override).to eq(:original)
    end

    it 'validates strategy override' do
      expect { described_class.new(strategy_override: :invalid) }
        .to raise_error(ArgumentError, /Invalid strategy/)
    end
  end

  describe '.instance' do
    it 'returns a singleton instance' do
      instance1 = described_class.instance
      instance2 = described_class.instance
      expect(instance1.object_id).to eq(instance2.object_id)
    end
  end

  describe '.current_strategy' do
    context 'with environment variable' do
      before { ENV['DASHBOARD_STRATEGY'] = 'original' }
      after { ENV.delete('DASHBOARD_STRATEGY') }

      it 'uses strategy from environment' do
        expect(described_class.current_strategy).to eq(:original)
      end
    end

    context 'with invalid environment variable' do
      before { ENV['DASHBOARD_STRATEGY'] = 'invalid' }
      after { ENV.delete('DASHBOARD_STRATEGY') }

      it 'falls back to config or default' do
        expect(described_class.current_strategy).to be_in([ :optimized, :original ])
      end
    end

    context 'without environment variable' do
      it 'uses config or default strategy' do
        expect(described_class.current_strategy).to eq(:optimized)
      end
    end
  end

  describe '#strategy_name' do
    it 'returns current strategy name' do
      expect(adapter.strategy_name).to be_in([ :original, :optimized ])
    end

    it 'respects strategy override' do
      expect(adapter_with_override.strategy_name).to eq(:original)
    end
  end

  describe '#strategy_info' do
    it 'returns detailed strategy information' do
      info = adapter.strategy_info
      expect(info).to include(:name, :class, :cached, :source)
    end

    it 'indicates correct source for override' do
      info = adapter_with_override.strategy_info
      expect(info[:source]).to eq(:override)
    end

    it 'indicates cached for optimized strategy' do
      adapter_optimized = described_class.new(strategy_override: :optimized)
      info = adapter_optimized.strategy_info
      expect(info[:cached]).to be true
    end

    it 'indicates not cached for original strategy' do
      info = adapter_with_override.strategy_info
      expect(info[:cached]).to be false
    end
  end

  describe '#switch_strategy' do
    it 'switches to valid strategy' do
      adapter.switch_strategy(:original)
      expect(adapter.strategy_name).to eq(:original)

      adapter.switch_strategy(:optimized)
      expect(adapter.strategy_name).to eq(:optimized)
    end

    it 'raises error for invalid strategy' do
      expect { adapter.switch_strategy(:invalid) }
        .to raise_error(ArgumentError, /Invalid strategy/)
    end

    it 'clears cache when switching' do
      expect(adapter).to receive(:clear_cache)
      adapter.switch_strategy(:original)
    end
  end

  describe 'metrics methods' do
    shared_examples 'metrics method' do |method_name|
      it "delegates #{method_name} to strategy class" do
        result = adapter.send(method_name)
        expect(result).to be_a(Hash)
      end

      it "handles errors gracefully for #{method_name}" do
        # Mock the actual strategy class method to raise an error
        strategy_class = adapter.strategy_name == :original ?
          Categorization::Monitoring::DashboardHelper :
          Categorization::Monitoring::DashboardHelperOptimized

        # Use the appropriate method name based on strategy
        actual_method = if adapter.strategy_name == :optimized
          case method_name
          when :categorization_metrics then :categorization_metrics_optimized
          when :pattern_metrics then :pattern_metrics_optimized
          when :learning_metrics then :learning_metrics_optimized
          when :system_metrics then :system_metrics_safe
          else method_name
          end
        else
          method_name
        end

        allow(strategy_class).to receive(actual_method).and_raise(StandardError, 'Test error')
        result = adapter.send(method_name)
        expect(result).to include(:error, :message, :timestamp)
      end
    end

    include_examples 'metrics method', :metrics_summary
    include_examples 'metrics method', :categorization_metrics
    include_examples 'metrics method', :pattern_metrics
    include_examples 'metrics method', :cache_metrics
    include_examples 'metrics method', :performance_metrics
    include_examples 'metrics method', :learning_metrics
    include_examples 'metrics method', :system_metrics
  end

  describe '#clear_cache' do
    it 'clears internal caches' do
      adapter.clear_cache
      stats = adapter.cache_stats
      expect(stats[:entries]).to eq(0)
    end
  end

  describe '#cache_stats' do
    it 'returns cache statistics' do
      stats = adapter.cache_stats
      expect(stats).to include(:entries, :timestamps)
    end
  end

  describe 'instrumentation' do
    it 'sends ActiveSupport notifications' do
      # Allow cache notifications to pass through
      allow(ActiveSupport::Notifications).to receive(:instrument).and_call_original

      # Expect our specific notification
      expect(ActiveSupport::Notifications).to receive(:instrument)
        .with('dashboard_adapter.categorization', hash_including(:method, :strategy, :duration))
        .and_call_original

      adapter.metrics_summary
    end

    it 'logs slow operations' do
      strategy_class = adapter.strategy_name == :original ?
        Categorization::Monitoring::DashboardHelper :
        Categorization::Monitoring::DashboardHelperOptimized

      allow(strategy_class).to receive(:metrics_summary) do
        sleep 0.11 # Simulate slow operation
        {}
      end

      expect(Rails.logger).to receive(:warn).with(/Slow dashboard operation/)
      adapter.metrics_summary
    end
  end

  describe 'strategy selection' do
    context 'when using original strategy' do
      let(:original_adapter) { described_class.new(strategy_override: :original) }

      it 'uses DashboardHelper methods' do
        expect(Categorization::Monitoring::DashboardHelper).to receive(:categorization_metrics).and_return({})
        original_adapter.categorization_metrics
      end
    end

    context 'when using optimized strategy' do
      let(:optimized_adapter) { described_class.new(strategy_override: :optimized) }

      it 'uses DashboardHelperOptimized methods' do
        expect(Categorization::Monitoring::DashboardHelperOptimized).to receive(:categorization_metrics_optimized).and_return({})
        optimized_adapter.categorization_metrics
      end
    end
  end

  describe 'error handling' do
    it 'returns error hash when strategy method fails' do
      allow(Categorization::Monitoring::DashboardHelperOptimized).to receive(:metrics_summary)
        .and_raise(StandardError, 'Database connection error')

      result = adapter.metrics_summary
      expect(result[:error]).to be true
      expect(result[:message]).to include('Database connection error')
    end

    it 'logs errors with backtrace' do
      error = StandardError.new('Test error')
      error.set_backtrace([ 'line1', 'line2', 'line3' ])

      allow(Categorization::Monitoring::DashboardHelperOptimized).to receive(:metrics_summary)
        .and_raise(error)

      expect(Rails.logger).to receive(:error).with(/Dashboard adapter error/)
      expect(Rails.logger).to receive(:error).with(/line1/)

      adapter.metrics_summary
    end
  end

  describe 'thread safety' do
    it 'uses mutex for cache operations' do
      mutex = adapter.instance_variable_get(:@mutex)
      expect(mutex).to be_a(Mutex)
    end

    it 'safely handles concurrent access' do
      threads = 5.times.map do
        Thread.new do
          adapter.cache_stats
          adapter.clear_cache
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end
end
