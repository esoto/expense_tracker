# frozen_string_literal: true

namespace :categorization do
  desc "Analyze database query performance"
  task analyze_queries: :environment do
    puts "🔍 Analyzing categorization query performance..."

    # Test pattern lookup queries
    test_pattern_queries
    test_cache_queries
    test_learning_queries
    test_index_effectiveness

    puts "\n✅ Query analysis completed"
  end

  desc "Run comprehensive performance benchmarks"
  task benchmark: :environment do
    puts "🚀 Running categorization performance benchmarks..."

    benchmark_categorization_engine
    benchmark_fuzzy_matching
    benchmark_pattern_cache

    puts "\n✅ Performance benchmarks completed"
  end

  desc "Profile memory usage during categorization"
  task profile_memory: :environment do
    require "memory_profiler"

    puts "🧠 Profiling memory usage..."

    # Create test data
    categories = create_test_categories
    create_test_patterns(categories)
    expenses = create_test_expenses(1000)

    engine = Categorization::Engine.new

    report = MemoryProfiler.report do
      expenses.each { |expense| engine.categorize(expense) }
    end

    puts "\n=== Memory Profile Results ==="
    puts "Total allocated: #{(report.total_allocated_memsize / 1024.0 / 1024.0).round(2)} MB"
    puts "Total retained: #{(report.total_retained_memsize / 1024.0 / 1024.0).round(2)} MB"
    puts "Objects allocated: #{report.total_allocated}"
    puts "Objects retained: #{report.total_retained}"

    # Show top memory consumers
    puts "\n=== Top Memory Allocations by Class ==="
    report.allocated_memory_by_class.first(10).each do |allocation|
      puts "#{allocation[:data]}: #{(allocation[:count] / 1024.0).round(2)} KB"
    end

    puts "\n✅ Memory profiling completed"
  end

  private

  def test_pattern_queries
    puts "\n--- Pattern Lookup Queries ---"

    queries = [
      {
        name: "Active merchant patterns",
        query: -> { CategorizationPattern.active.where(pattern_type: "merchant").limit(100) }
      },
      {
        name: "Patterns by category join",
        query: -> { CategorizationPattern.joins(:category).where(categories: { name: "Food & Dining" }).limit(100) }
      },
      {
        name: "Pattern value ILIKE search",
        query: -> { CategorizationPattern.where("pattern_value ILIKE ?", "%starbucks%").limit(100) }
      },
      {
        name: "High confidence patterns",
        query: -> { CategorizationPattern.where("confidence_weight > ?", 2.0).order(:confidence_weight).limit(100) }
      },
      {
        name: "Recently used patterns",
        query: -> { CategorizationPattern.where("updated_at > ?", 7.days.ago).limit(100) }
      },
      {
        name: "Pattern usage statistics",
        query: -> { CategorizationPattern.where("usage_count > ?", 10).order(success_rate: :desc).limit(100) }
      }
    ]

    queries.each_with_index do |query_info, index|
      result = nil
      time = Benchmark.realtime do
        result = query_info[:query].call.to_a
      end

      time_ms = (time * 1000).round(2)
      puts "#{index + 1}. #{query_info[:name]}: #{time_ms}ms (#{result.size} results)"

      # Log slow queries
      if time_ms > 10.0
        puts "   ⚠️  SLOW QUERY: #{time_ms}ms > 10ms target"
      elsif time_ms > 5.0
        puts "   ⚠️  Warning: #{time_ms}ms approaching 5ms target"
      else
        puts "   ✅ Performance OK: #{time_ms}ms"
      end
    end
  end

  def test_cache_queries
    puts "\n--- Cache-Related Queries ---"

    cache_queries = [
      {
        name: "User preferences by merchant",
        query: -> { UserCategoryPreference.where(context_type: "merchant").limit(100) }
      },
      {
        name: "Canonical merchant lookup",
        query: -> { CanonicalMerchant.where("name ILIKE ?", "%starbucks%").limit(10) }
      },
      {
        name: "Merchant aliases search",
        query: -> { MerchantAlias.joins(:canonical_merchant).where("raw_name ILIKE ?", "%coffee%").limit(50) }
      },
      {
        name: "Pattern learning events",
        query: -> { PatternLearningEvent.includes(:expense, :category).where("created_at > ?", 7.days.ago).limit(100) }
      }
    ]

    cache_queries.each_with_index do |query_info, index|
      result = nil
      time = Benchmark.realtime do
        result = query_info[:query].call.to_a
      end

      time_ms = (time * 1000).round(2)
      puts "#{index + 1}. #{query_info[:name]}: #{time_ms}ms (#{result.size} results)"

      if time_ms > 5.0
        puts "   ⚠️  SLOW QUERY: #{time_ms}ms > 5ms target"
      else
        puts "   ✅ Performance OK: #{time_ms}ms"
      end
    end
  end

  def test_learning_queries
    puts "\n--- Learning & Feedback Queries ---"

    learning_queries = [
      {
        name: "Pattern feedback analysis",
        query: -> { PatternFeedback.includes(:expense, :category).where("created_at > ?", 30.days.ago).limit(200) }
      },
      {
        name: "Low-performing patterns",
        query: -> { CategorizationPattern.where("success_rate < ? AND usage_count > ?", 0.5, 10).limit(50) }
      },
      {
        name: "Unused patterns cleanup",
        query: -> { CategorizationPattern.where("usage_count = 0 AND created_at < ?", 30.days.ago).limit(100) }
      }
    ]

    learning_queries.each_with_index do |query_info, index|
      result = nil
      time = Benchmark.realtime do
        result = query_info[:query].call.to_a
      end

      time_ms = (time * 1000).round(2)
      puts "#{index + 1}. #{query_info[:name]}: #{time_ms}ms (#{result.size} results)"

      if time_ms > 10.0
        puts "   ⚠️  SLOW QUERY: #{time_ms}ms > 10ms target"
      else
        puts "   ✅ Performance OK: #{time_ms}ms"
      end
    end
  end

  def test_index_effectiveness
    puts "\n--- Index Effectiveness Analysis ---"

    # Check for missing indexes that might improve performance
    index_tests = [
      {
        name: "Pattern type + active index usage",
        query: "SELECT * FROM categorization_patterns WHERE pattern_type = 'merchant' AND active = true LIMIT 100"
      },
      {
        name: "Pattern confidence weight index usage",
        query: "SELECT * FROM categorization_patterns WHERE confidence_weight > 2.0 ORDER BY confidence_weight DESC LIMIT 100"
      },
      {
        name: "Pattern updated_at index usage",
        query: "SELECT * FROM categorization_patterns WHERE updated_at > NOW() - INTERVAL '7 days' LIMIT 100"
      }
    ]

    index_tests.each_with_index do |test, index|
      time = Benchmark.realtime do
        ActiveRecord::Base.connection.execute(test[:query])
      end

      time_ms = (time * 1000).round(2)
      puts "#{index + 1}. #{test[:name]}: #{time_ms}ms"

      if time_ms > 5.0
        puts "   ⚠️  Consider adding index to improve performance"
      else
        puts "   ✅ Index effectiveness good"
      end
    end
  end

  def benchmark_categorization_engine
    puts "\n--- Categorization Engine Benchmarks ---"

    # Create test data
    categories = create_test_categories
    create_test_patterns(categories)
    expenses = create_test_expenses(100)

    engine = Categorization::Engine.new

    require "benchmark"

    # Warm up
    expenses.first(10).each { |expense| engine.categorize(expense) }

    # Benchmark different expense types
    Benchmark.bmbm(30) do |x|
      x.report("Simple merchant match:") do
        starbucks_expenses = expenses.select { |e| e.merchant_name&.include?("STARBUCKS") }
        starbucks_expenses.each { |expense| engine.categorize(expense) }
      end

      x.report("Complex fuzzy matching:") do
        # Create expenses with typos for fuzzy matching
        complex_expenses = expenses.select { |e| e.merchant_name.present? }.map do |expense|
          # Introduce typos for fuzzy matching test
          typo_merchant = expense.merchant_name.gsub(/[aeiou]/, "x")[0...-1] + "Z"
          expense.dup.tap { |e| e.merchant_name = typo_merchant }
        end

        complex_expenses.first(20).each { |expense| engine.categorize(expense) }
      end

      x.report("Pattern learning:") do
        expenses.first(20).each do |expense|
          result = engine.categorize(expense)
          # Simulate learning feedback - skip if method not available
          if result && engine.respond_to?(:learn_from_feedback)
            engine.learn_from_feedback(expense, result, true)
          end
        end
      end
    end
  end

  def benchmark_fuzzy_matching
    puts "\n--- Fuzzy Matching Benchmarks ---"

    matcher = Categorization::Matchers::FuzzyMatcher.new

    # Test data
    candidates = [
      "Starbucks Coffee",
      "McDonald's Restaurant",
      "Subway Sandwiches",
      "Whole Foods Market",
      "Amazon.com",
      "Target Store",
      "Walmart Supercenter",
      "Home Depot",
      "CVS Pharmacy",
      "Shell Gas Station"
    ]

    test_queries = [
      "Starbucks",
      "McDonalds", # Missing apostrophe
      "Subwy", # Typo
      "Whole Food", # Partial
      "Amazn", # Missing letters
      "Targt Store", # Typo
      "Wall-Mart", # Different format
      "HomeDepot", # No space
      "CVS", # Abbreviation
      "Shell Oil" # Related term
    ]

    require "benchmark"

    Benchmark.bmbm(20) do |x|
      x.report("Fuzzy matching:") do
        test_queries.each do |query|
          matcher.match(query, candidates)
        end
      end

      x.report("Exact matching:") do
        candidates.each do |candidate|
          matcher.match(candidate, candidates)
        end
      end
    end
  end

  def benchmark_pattern_cache
    puts "\n--- Pattern Cache Benchmarks ---"

    cache = Categorization::PatternCache.instance

    # Create test patterns
    categories = create_test_categories
    patterns = create_test_patterns(categories)

    require "benchmark"

    Benchmark.bmbm(25) do |x|
      x.report("Cache loading:") do
        cache.invalidate_all
        cache.get_all_active_patterns
      end

      x.report("Pattern lookup:") do
        100.times do
          pattern_id = patterns.sample.id
          cache.get_pattern(pattern_id)
        end
      end

      x.report("User preferences:") do
        50.times do
          cache.get_user_preference("starbucks coffee")
        end
      end
    end
  end

  # Helper methods
  def create_test_categories
    [
      Category.find_or_create_by(name: "Food & Dining"),
      Category.find_or_create_by(name: "Transportation"),
      Category.find_or_create_by(name: "Shopping"),
      Category.find_or_create_by(name: "Utilities")
    ]
  end

  def create_test_patterns(categories)
    return CategorizationPattern.limit(20) if CategorizationPattern.count > 20

    patterns = []

    # Create patterns for each category
    categories.each do |category|
      5.times do |i|
        pattern = CategorizationPattern.find_or_create_by(
          pattern_type: "merchant",
          pattern_value: "test_pattern_#{category.name.downcase.gsub(/[^a-z]/, '_')}_#{i}",
          category: category
        ) do |p|
          p.confidence_weight = 2.0 + rand
          p.success_rate = 0.7 + (rand * 0.3)
          p.usage_count = rand(10..50)
          p.success_count = (p.usage_count * p.success_rate).to_i
          p.active = true
        end
        patterns << pattern
      end
    end

    patterns
  end

  def create_test_expenses(count)
    return Expense.limit(count) if Expense.count >= count

    test_data = [
      { merchant: "STARBUCKS COFFEE", description: "Coffee purchase" },
      { merchant: "MCDONALD'S", description: "Fast food" },
      { merchant: "UBER TRIP", description: "Rideshare" },
      { merchant: "AMAZON.COM", description: "Online shopping" },
      { merchant: "SHELL GAS", description: "Gasoline" }
    ]

    count.times.map do |i|
      data = test_data[i % test_data.size]
      Expense.create!(
        merchant_name: "#{data[:merchant]} #{i}",
        description: data[:description],
        amount: rand(5.0..100.0).round(2),
        transaction_date: rand(30.days.ago..Time.current),
        email_account: EmailAccount.first || create_email_account
      )
    end
  end

  def create_email_account
    EmailAccount.find_or_create_by(email: "performance_test@example.com") do |ea|
      ea.provider = "gmail"
      ea.bank_name = "Performance Test Bank"
      ea.active = true
    end
  end
end
