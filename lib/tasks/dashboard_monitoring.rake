# frozen_string_literal: true

namespace :dashboard do
  desc "Display current dashboard metrics using the configured strategy"
  task metrics: :environment do
    adapter = Categorization::Monitoring::DashboardAdapter.new

    puts "="*60
    puts "Dashboard Metrics Report"
    puts "="*60
    puts "Strategy: #{adapter.strategy_name}"
    puts "Source: #{adapter.strategy_info[:source]}"
    puts "-"*60

    metrics = adapter.metrics_summary

    # Display categorization metrics
    if metrics[:categorization]
      puts "\nCategorization Metrics:"
      puts "  Total Expenses: #{metrics[:categorization][:total_expenses]}"
      puts "  Categorized: #{metrics[:categorization][:categorized]}"
      puts "  Success Rate: #{metrics[:categorization][:success_rate]}%"
    end

    # Display pattern metrics
    if metrics[:patterns]
      puts "\nPattern Metrics:"
      puts "  Total Patterns: #{metrics[:patterns][:total]}"
      puts "  Active: #{metrics[:patterns][:active]}"
      puts "  High Confidence: #{metrics[:patterns][:high_confidence]}"
    end

    # Display cache metrics
    if metrics[:cache]
      puts "\nCache Metrics:"
      puts "  Entries: #{metrics[:cache][:entries]}"
      puts "  Hit Rate: #{metrics[:cache][:hit_rate]}%"
      puts "  Memory: #{metrics[:cache][:memory_mb]} MB"
    end

    puts "="*60
  end

  desc "Compare performance between dashboard strategies"
  task compare_strategies: :environment do
    require "benchmark"

    puts "="*60
    puts "Dashboard Strategy Performance Comparison"
    puts "="*60

    original = Categorization::Monitoring::DashboardAdapter.new(strategy_override: :original)
    optimized = Categorization::Monitoring::DashboardAdapter.new(strategy_override: :optimized)

    # Warm up caches
    original.metrics_summary
    optimized.metrics_summary

    # Clear caches for fair comparison
    original.clear_cache
    optimized.clear_cache
    Rails.cache.clear if Rails.cache.respond_to?(:clear)

    puts "\nBenchmarking metrics_summary (10 iterations):"
    puts "-"*40

    Benchmark.bm(20) do |x|
      x.report("Original Strategy:") do
        10.times { original.metrics_summary }
      end

      x.report("Optimized Strategy:") do
        10.times { optimized.metrics_summary }
      end
    end

    puts "\nDetailed Method Comparison:"
    puts "-"*40

    methods = [ :categorization_metrics, :pattern_metrics, :learning_metrics ]

    methods.each do |method|
      puts "\n#{method}:"

      time_original = Benchmark.realtime { 5.times { original.send(method) } }
      time_optimized = Benchmark.realtime { 5.times { optimized.send(method) } }

      improvement = ((time_original - time_optimized) / time_original * 100).round(2)

      puts "  Original:  #{(time_original * 1000).round(2)}ms (5 calls)"
      puts "  Optimized: #{(time_optimized * 1000).round(2)}ms (5 calls)"
      puts "  Improvement: #{improvement}%"
    end

    puts "="*60
  end

  desc "Switch dashboard strategy (STRATEGY=original|optimized)"
  task switch_strategy: :environment do
    strategy = ENV["STRATEGY"]&.to_sym

    unless strategy && [ :original, :optimized ].include?(strategy)
      puts "Error: Please specify STRATEGY=original or STRATEGY=optimized"
      exit 1
    end

    puts "Switching dashboard strategy to: #{strategy}"
    puts "Set DASHBOARD_STRATEGY=#{strategy} in your environment to make this permanent"

    adapter = Categorization::Monitoring::DashboardAdapter.new(strategy_override: strategy)

    puts "\nTesting new strategy..."
    start_time = Time.current
    metrics = adapter.metrics_summary
    duration = (Time.current - start_time) * 1000

    puts "✓ Strategy switched successfully"
    puts "  Response time: #{duration.round(2)}ms"
    puts "  Metrics retrieved: #{metrics.keys.join(', ')}"
  end
end
