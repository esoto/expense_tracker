# frozen_string_literal: true

require "benchmark"

# Try to load benchmark-memory gem if available
begin
  require "benchmark/memory"
  MEMORY_PROFILING_AVAILABLE = true
rescue LoadError
  MEMORY_PROFILING_AVAILABLE = false
end

namespace :performance do
  desc "Run comprehensive performance benchmarks for pattern cache and categorization"
  task benchmark: :environment do
    puts "\n" + "="*80
    puts "PERFORMANCE BENCHMARK SUITE"
    puts "="*80
    puts "Started at: #{Time.current}"
    puts "Rails Environment: #{Rails.env}"
    puts "="*80 + "\n"

    # Initialize services
    pattern_cache = Categorization::PatternCache.instance
    engine = Services::Categorization::Engine.instance

    # Ensure cache is warmed
    puts "\nWarming cache..."
    warm_stats = pattern_cache.warm_cache
    puts "Cache warmed: #{warm_stats[:patterns]} patterns, #{warm_stats[:composites]} composites"

    # Create test data
    test_expenses = create_test_expenses

    # Run benchmarks
    results = {}

    puts "\n" + "-"*80
    puts "PATTERN LOOKUP BENCHMARKS"
    puts "-"*80

    results[:pattern_lookup] = benchmark_pattern_lookups(pattern_cache, test_expenses)

    puts "\n" + "-"*80
    puts "CATEGORIZATION BENCHMARKS"
    puts "-"*80

    results[:categorization] = benchmark_categorization(engine, test_expenses)

    puts "\n" + "-"*80
    puts "BULK OPERATIONS BENCHMARKS"
    puts "-"*80

    results[:bulk_operations] = benchmark_bulk_operations(test_expenses)

    puts "\n" + "-"*80
    puts "CACHE PERFORMANCE BENCHMARKS"
    puts "-"*80

    results[:cache_performance] = benchmark_cache_performance(pattern_cache)

    puts "\n" + "-"*80
    puts "MEMORY USAGE ANALYSIS"
    puts "-"*80

    results[:memory] = analyze_memory_usage(pattern_cache)

    # Generate summary report
    generate_summary_report(results)

    # Check against targets
    check_performance_targets(results)
  end

  desc "Run quick performance check"
  task quick_check: :environment do
    puts "\nQuick Performance Check"
    puts "="*40

    pattern_cache = Categorization::PatternCache.instance

    # Test pattern lookup
    expense = Expense.first || create_test_expense

    time = Benchmark.realtime do
      100.times { pattern_cache.get_pattern(expense.description) }
    end

    avg_time_ms = (time / 100 * 1000).round(3)

    puts "Average pattern lookup time: #{avg_time_ms}ms"
    puts "Cache metrics: #{pattern_cache.metrics.slice(:hit_rate, :hits, :misses)}"

    if avg_time_ms < 1
      puts "✓ Performance target met (< 1ms)"
    else
      puts "✗ Performance target NOT met (target: < 1ms, actual: #{avg_time_ms}ms)"
    end
  end

  desc "Stress test pattern cache"
  task stress_test: :environment do
    puts "\nPattern Cache Stress Test"
    puts "="*40

    pattern_cache = Categorization::PatternCache.instance

    # Create many unique CategorizationPattern records
    # These will be automatically cached when fetched
    category = Category.first || Category.create!(name: "Stress Test Category")
    pattern_records = []

    puts "Creating #{100} unique patterns for stress test..."

    # Measure write performance through pattern creation and first fetch
    write_time = Benchmark.realtime do
      100.times do |i|
        pattern = CategorizationPattern.create!(
          pattern_value: "test_pattern_#{i}_#{SecureRandom.hex(4)}",
          pattern_type: "keyword",
          category: category,
          confidence_weight: rand(1.0..5.0),
          active: true
        )
        pattern_records << pattern
        # First fetch will cache it
        pattern_cache.get_pattern(pattern.id)
      end
    end

    puts "Write time: #{write_time.round(3)}s (#{(pattern_records.size / write_time).round} patterns/sec)"

    # Measure read performance on cached patterns
    pattern_ids = pattern_records.map(&:id).sample([ pattern_records.size, 50 ].min)
    total_lookups = pattern_ids.size * 10
    read_time = Benchmark.realtime do
      pattern_ids.each { |id| 10.times { pattern_cache.get_pattern(id) } }
    end

    puts "Read time for #{total_lookups} lookups: #{read_time.round(3)}s"
    puts "Average lookup: #{(read_time / total_lookups * 1000).round(3)}ms"

    # Check memory usage
    memory_entries = pattern_cache.metrics[:memory_cache_entries]
    puts "Memory cache entries: #{memory_entries}"

    if memory_entries < 50_000
      puts "✓ Memory usage within limits"
    else
      puts "✗ High memory usage detected"
    end

    # Clean up test data
    puts "Cleaning up test patterns..."
    CategorizationPattern.where(id: pattern_records.map(&:id)).destroy_all
  end

  private

  def create_test_expenses
    # Create or fetch test expenses
    expenses = []

    if Expense.count > 100
      expenses = Expense.limit(100).to_a
    else
      # Create test expenses
      categories = Category.limit(5).to_a
      categories = [ Category.create!(name: "Test Category") ] if categories.empty?

      100.times do |i|
        expenses << Expense.create!(
          description: "Test expense #{i} - #{[ 'grocery', 'restaurant', 'gas', 'utilities' ].sample}",
          amount: rand(10.0..500.0),
          transaction_date: Date.current - rand(1..30).days,
          category: categories.sample,
          source: "test"
        )
      end
    end

    expenses
  end

  def create_test_expense
    category = Category.first || Category.create!(name: "Test Category")
    Expense.create!(
      description: "Test expense - #{SecureRandom.hex(4)}",
      amount: rand(10.0..500.0),
      transaction_date: Date.current,
      category: category,
      source: "test"
    )
  end

  def benchmark_pattern_lookups(pattern_cache, expenses)
    results = {}

    # Benchmark cached lookups (should be < 1ms)
    descriptions = expenses.map(&:description)

    # First pass to cache
    descriptions.each { |d| pattern_cache.get_pattern(d) }

    # Measure cached lookups
    time = Benchmark.realtime do
      1000.times do
        pattern_cache.get_pattern(descriptions.sample)
      end
    end

    results[:cached_lookup_ms] = (time / 1000 * 1000).round(3)
    puts "Cached pattern lookup: #{results[:cached_lookup_ms]}ms average"

    # Benchmark uncached lookups
    new_descriptions = 10.times.map { |i| "New description #{i} #{SecureRandom.hex(4)}" }

    time = Benchmark.realtime do
      new_descriptions.each { |d| pattern_cache.get_pattern(d) }
    end

    results[:uncached_lookup_ms] = (time / new_descriptions.size * 1000).round(3)
    puts "Uncached pattern lookup: #{results[:uncached_lookup_ms]}ms average"

    # Test composite patterns
    composite_key = "#{descriptions.first}||#{descriptions.last}"

    time = Benchmark.realtime do
      100.times { pattern_cache.get_composite_pattern(composite_key) }
    end

    results[:composite_lookup_ms] = (time / 100 * 1000).round(3)
    puts "Composite pattern lookup: #{results[:composite_lookup_ms]}ms average"

    results
  end

  def benchmark_categorization(engine, expenses)
    results = {}

    # Single expense categorization
    single_times = []

    expenses.first(10).each do |expense|
      time = Benchmark.realtime do
        engine.categorize(expense)
      end
      single_times << time * 1000
    end

    results[:single_categorization_ms] = (single_times.sum / single_times.size).round(3)
    puts "Single expense categorization: #{results[:single_categorization_ms]}ms average"

    # Batch categorization
    batch_time = Benchmark.realtime do
      engine.categorize_batch(expenses)
    end

    results[:batch_total_ms] = (batch_time * 1000).round(3)
    results[:batch_per_expense_ms] = (batch_time / expenses.size * 1000).round(3)

    puts "Batch categorization (#{expenses.size} expenses):"
    puts "  Total time: #{results[:batch_total_ms]}ms"
    puts "  Per expense: #{results[:batch_per_expense_ms]}ms"

    results
  end

  def benchmark_bulk_operations(expenses)
    results = {}

    return results unless defined?(Services::BulkCategorization::BulkCategorizationService)

    service = Services::BulkCategorization::BulkCategorizationService.new

    # Benchmark bulk categorization
    time = Benchmark.realtime do
      service.categorize_expenses(
        expense_ids: expenses.map(&:id),
        category_id: expenses.first.category_id
      )
    end

    results[:bulk_categorization_ms] = (time * 1000).round(3)
    results[:per_expense_ms] = (time / expenses.size * 1000).round(3)

    puts "Bulk categorization:"
    puts "  Total time: #{results[:bulk_categorization_ms]}ms"
    puts "  Per expense: #{results[:per_expense_ms]}ms"

    results
  end

  def benchmark_cache_performance(pattern_cache)
    results = {}

    # Test cache warming
    time = Benchmark.realtime do
      pattern_cache.warm_cache
    end

    results[:warming_time_seconds] = time.round(3)
    puts "Cache warming time: #{results[:warming_time_seconds]}s"

    # Test cache metrics retrieval
    time = Benchmark.realtime do
      100.times { pattern_cache.metrics }
    end

    results[:metrics_retrieval_ms] = (time / 100 * 1000).round(3)
    puts "Metrics retrieval: #{results[:metrics_retrieval_ms]}ms"

    # Cache hit rate
    metrics = pattern_cache.metrics
    results[:hit_rate] = metrics[:hit_rate]
    puts "Current cache hit rate: #{results[:hit_rate]}%"

    results
  end

  def analyze_memory_usage(pattern_cache)
    results = {}

    if MEMORY_PROFILING_AVAILABLE
      report = Benchmark.memory do |x|
        x.report("Pattern lookup") do
          100.times { pattern_cache.get_pattern("test description") }
        end

        x.report("Cache warming") do
          pattern_cache.warm_cache
        end

        x.report("Metrics collection") do
          10.times { pattern_cache.metrics }
        end

        x.compare!
      end

      # Parse memory report (simplified)
      results[:total_allocated] = "See console output"
      results[:total_retained] = "See console output"
    else
      results[:memory_profiling] = "Not available (install benchmark-memory gem)"
    end

    # Get current memory stats
    metrics = pattern_cache.metrics
    results[:memory_cache_entries] = metrics[:memory_cache_entries]
    results[:estimated_memory_mb] = (metrics[:memory_cache_entries].to_i * 1024 / 1_048_576.0).round(2)

    puts "\nMemory Analysis:"
    puts "  Cache entries: #{results[:memory_cache_entries]}"
    puts "  Estimated memory: #{results[:estimated_memory_mb]}MB"

    if !MEMORY_PROFILING_AVAILABLE
      puts "  Note: Detailed memory profiling not available (install benchmark-memory gem)"
    end

    results
  end

  def generate_summary_report(results)
    puts "\n" + "="*80
    puts "PERFORMANCE SUMMARY REPORT"
    puts "="*80

    puts "\n📊 Pattern Lookup Performance:"
    puts "  • Cached lookups: #{results[:pattern_lookup][:cached_lookup_ms]}ms"
    puts "  • Uncached lookups: #{results[:pattern_lookup][:uncached_lookup_ms]}ms"
    puts "  • Composite lookups: #{results[:pattern_lookup][:composite_lookup_ms]}ms"

    puts "\n📊 Categorization Performance:"
    puts "  • Single expense: #{results[:categorization][:single_categorization_ms]}ms"
    puts "  • Batch per expense: #{results[:categorization][:batch_per_expense_ms]}ms"

    if results[:bulk_operations].any?
      puts "\n📊 Bulk Operations:"
      puts "  • Per expense: #{results[:bulk_operations][:per_expense_ms]}ms"
    end

    puts "\n📊 Cache Performance:"
    puts "  • Warming time: #{results[:cache_performance][:warming_time_seconds]}s"
    puts "  • Hit rate: #{results[:cache_performance][:hit_rate]}%"

    puts "\n📊 Memory Usage:"
    puts "  • Cache entries: #{results[:memory][:memory_cache_entries]}"
    puts "  • Estimated size: #{results[:memory][:estimated_memory_mb]}MB"

    puts "\n" + "="*80
  end

  def check_performance_targets(results)
    puts "\n" + "="*80
    puts "PERFORMANCE TARGETS VALIDATION"
    puts "="*80

    targets_met = true

    # Check pattern lookup target (< 1ms)
    if results[:pattern_lookup][:cached_lookup_ms] < 1
      puts "✅ Pattern lookups: #{results[:pattern_lookup][:cached_lookup_ms]}ms < 1ms target"
    else
      puts "❌ Pattern lookups: #{results[:pattern_lookup][:cached_lookup_ms]}ms > 1ms target"
      targets_met = false
    end

    # Check bulk categorization target (< 10ms per expense)
    batch_per_expense = results[:categorization][:batch_per_expense_ms]
    if batch_per_expense < 10
      puts "✅ Bulk categorization: #{batch_per_expense}ms < 10ms target"
    else
      puts "❌ Bulk categorization: #{batch_per_expense}ms > 10ms target"
      targets_met = false
    end

    # Check cache hit rate target (> 90%)
    hit_rate = results[:cache_performance][:hit_rate].to_f
    if hit_rate > 90
      puts "✅ Cache hit rate: #{hit_rate}% > 90% target"
    else
      puts "❌ Cache hit rate: #{hit_rate}% < 90% target"
      targets_met = false
    end

    # Check memory usage target (< 50MB)
    memory_mb = results[:memory][:estimated_memory_mb].to_f
    if memory_mb < 50
      puts "✅ Memory usage: #{memory_mb}MB < 50MB target"
    else
      puts "❌ Memory usage: #{memory_mb}MB > 50MB target"
      targets_met = false
    end

    puts "\n" + "="*80

    if targets_met
      puts "🎉 ALL PERFORMANCE TARGETS MET!"
    else
      puts "⚠️  Some performance targets not met. Consider optimization."
    end

    puts "="*80
  end
end
