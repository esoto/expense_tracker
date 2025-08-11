# frozen_string_literal: true

namespace :categorization do
  namespace :cache do
    desc "Run performance benchmarks for pattern cache"
    task benchmark: :environment do
      require "benchmark"
      
      puts "\n" + "=" * 80
      puts "CATEGORIZATION PATTERN CACHE PERFORMANCE BENCHMARK"
      puts "=" * 80
      
      # Setup test data
      categories = 5.times.map { |i| Category.create!(name: "Test Category #{i}") }
      
      patterns = []
      100.times do |i|
        patterns << CategorizationPattern.create!(
          category: categories.sample,
          pattern_type: %w[merchant keyword description].sample,
          pattern_value: "test_pattern_#{i}",
          confidence_weight: rand(1.0..5.0),
          success_rate: rand(0.5..1.0),
          usage_count: rand(10..1000)
        )
      end
      
      composites = 20.times.map do |i|
        CompositePattern.create!(
          category: categories.sample,
          name: "Composite #{i}",
          operator: %w[AND OR].sample,
          pattern_ids: patterns.sample(3).map(&:id),
          confidence_weight: rand(1.0..5.0)
        )
      end
      
      cache = Categorization::PatternCache.instance
      cache.invalidate_all
      
      puts "\nTest Data:"
      puts "  - Categories: #{categories.size}"
      puts "  - Patterns: #{patterns.size}"
      puts "  - Composite Patterns: #{composites.size}"
      
      # Benchmark different operations
      puts "\n" + "-" * 60
      puts "OPERATION BENCHMARKS"
      puts "-" * 60
      
      Benchmark.bm(35) do |x|
        # Cold cache operations
        x.report("Cold cache - single pattern:") do
          cache.invalidate_all
          patterns.sample(10).each { |p| cache.get_pattern(p.id) }
        end
        
        x.report("Cold cache - batch patterns:") do
          cache.invalidate_all
          cache.get_patterns(patterns.sample(20).map(&:id))
        end
        
        x.report("Cold cache - patterns by type:") do
          cache.invalidate_all
          %w[merchant keyword description].each do |type|
            cache.get_patterns_by_type(type)
          end
        end
        
        # Warm cache operations
        cache.warm_cache
        
        x.report("Warm cache - single pattern:") do
          1000.times { cache.get_pattern(patterns.sample.id) }
        end
        
        x.report("Warm cache - batch patterns:") do
          100.times { cache.get_patterns(patterns.sample(10).map(&:id)) }
        end
        
        x.report("Warm cache - mixed operations:") do
          500.times do
            case rand(3)
            when 0
              cache.get_pattern(patterns.sample.id)
            when 1
              cache.get_composite_pattern(composites.sample.id)
            when 2
              cache.get_patterns_by_type(%w[merchant keyword].sample)
            end
          end
        end
        
        # Cache invalidation
        x.report("Pattern invalidation:") do
          100.times do
            pattern = patterns.sample
            cache.get_pattern(pattern.id)
            cache.invalidate(pattern)
          end
        end
        
        x.report("Full cache warmup:") do
          cache.invalidate_all
          cache.warm_cache
        end
      end
      
      # Response time analysis
      puts "\n" + "-" * 60
      puts "RESPONSE TIME ANALYSIS (1000 operations each)"
      puts "-" * 60
      
      # Warm up cache
      cache.warm_cache
      
      operations = {
        "Single pattern lookup" => -> { cache.get_pattern(patterns.sample.id) },
        "Batch pattern lookup (5)" => -> { cache.get_patterns(patterns.sample(5).map(&:id)) },
        "Composite pattern lookup" => -> { cache.get_composite_pattern(composites.sample.id) },
        "Pattern by type lookup" => -> { cache.get_patterns_by_type("merchant") }
      }
      
      operations.each do |name, operation|
        timings = []
        
        1000.times do
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          operation.call
          duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
          timings << duration_ms
        end
        
        timings.sort!
        
        puts "\n#{name}:"
        puts "  Min:    #{timings.first.round(3)}ms"
        puts "  Median: #{timings[500].round(3)}ms"
        puts "  Avg:    #{(timings.sum / timings.size).round(3)}ms"
        puts "  P95:    #{timings[950].round(3)}ms"
        puts "  P99:    #{timings[990].round(3)}ms"
        puts "  Max:    #{timings.last.round(3)}ms"
        
        under_1ms = timings.count { |t| t < 1.0 }
        puts "  < 1ms:  #{(under_1ms / 10.0).round(1)}%"
      end
      
      # Cache metrics
      puts "\n" + "-" * 60
      puts "CACHE METRICS"
      puts "-" * 60
      
      metrics = cache.metrics
      
      puts "\nCache Performance:"
      puts "  Total Hits (Memory): #{metrics[:hits][:memory]}"
      puts "  Total Hits (Redis):  #{metrics[:hits][:redis]}"
      puts "  Total Misses:        #{metrics[:misses]}"
      puts "  Hit Rate:            #{metrics[:hit_rate]}%"
      puts "  Redis Available:     #{metrics[:redis_available]}"
      
      puts "\nOperation Statistics:"
      metrics[:operations].each do |op_name, stats|
        next if stats[:count] == 0
        puts "\n  #{op_name}:"
        puts "    Count:  #{stats[:count]}"
        puts "    Avg:    #{stats[:avg_ms]}ms"
        puts "    Min:    #{stats[:min_ms]}ms"
        puts "    Max:    #{stats[:max_ms]}ms"
        puts "    P95:    #{stats[:p95_ms]}ms" if stats[:p95_ms]
        puts "    P99:    #{stats[:p99_ms]}ms" if stats[:p99_ms]
      end
      
      # Memory usage
      puts "\n" + "-" * 60
      puts "MEMORY ANALYSIS"
      puts "-" * 60
      
      if defined?(ObjectSpace)
        before_gc = GC.stat[:total_allocated_objects]
        cache.get_patterns(patterns.sample(50).map(&:id))
        after_gc = GC.stat[:total_allocated_objects]
        
        puts "  Objects allocated for 50 lookups: #{after_gc - before_gc}"
      end
      
      puts "  Memory cache size: #{metrics[:memory_cache_size]} entries"
      
      # Cleanup
      puts "\n" + "-" * 60
      puts "CLEANUP"
      puts "-" * 60
      
      CompositePattern.where(id: composites.map(&:id)).destroy_all
      CategorizationPattern.where(id: patterns.map(&:id)).destroy_all
      Category.where(id: categories.map(&:id)).destroy_all
      
      cache.invalidate_all
      
      puts "  Test data cleaned up successfully"
      puts "\n" + "=" * 80
      puts "BENCHMARK COMPLETE"
      puts "=" * 80 + "\n"
    end
    
    desc "Monitor cache performance in real-time"
    task monitor: :environment do
      cache = Categorization::PatternCache.instance
      
      puts "\n" + "=" * 80
      puts "PATTERN CACHE MONITOR (Press Ctrl+C to exit)"
      puts "=" * 80
      
      loop do
        system("clear") || system("cls")
        
        metrics = cache.metrics
        
        puts "CATEGORIZATION PATTERN CACHE - LIVE MONITOR"
        puts "Updated: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
        puts "-" * 60
        
        puts "\n📊 CACHE STATISTICS:"
        puts "  Hit Rate:        #{metrics[:hit_rate]}%"
        puts "  Memory Hits:     #{metrics[:hits][:memory]}"
        puts "  Redis Hits:      #{metrics[:hits][:redis]}"
        puts "  Cache Misses:    #{metrics[:misses]}"
        puts "  Redis Available: #{metrics[:redis_available] ? '✅' : '❌'}"
        
        puts "\n⚡ OPERATION PERFORMANCE:"
        if metrics[:operations].any?
          metrics[:operations].each do |op_name, stats|
            next if stats[:count] == 0
            
            # Color code based on performance
            avg_ms = stats[:avg_ms]
            indicator = if avg_ms < 1.0
                         "🟢"
                       elsif avg_ms < 5.0
                         "🟡"
                       else
                         "🔴"
                       end
            
            puts "  #{indicator} #{op_name}:"
            puts "      Calls: #{stats[:count]} | Avg: #{avg_ms}ms | Max: #{stats[:max_ms]}ms"
          end
        else
          puts "  No operations recorded yet"
        end
        
        puts "\n⚙️  CONFIGURATION:"
        puts "  Memory TTL: #{metrics[:configuration][:memory_ttl]}s"
        puts "  Redis TTL:  #{metrics[:configuration][:redis_ttl]}s"
        puts "  Max Memory: #{metrics[:configuration][:max_memory_size]} entries"
        
        puts "\n" + "-" * 60
        puts "Refreshing in 5 seconds..."
        
        sleep 5
      rescue Interrupt
        puts "\n\nMonitoring stopped."
        break
      end
    end
    
    desc "Test cache warming on startup"
    task test_warmup: :environment do
      cache = Categorization::PatternCache.instance
      
      puts "\n" + "=" * 80
      puts "TESTING CACHE WARMUP"
      puts "=" * 80
      
      # Clear cache
      cache.invalidate_all
      initial_metrics = cache.metrics
      
      puts "\nInitial state:"
      puts "  Memory hits: #{initial_metrics[:hits][:memory]}"
      puts "  Redis hits:  #{initial_metrics[:hits][:redis]}"
      puts "  Misses:      #{initial_metrics[:misses]}"
      
      # Perform warmup
      puts "\nWarming cache..."
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = cache.warm_cache
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      
      puts "\nWarmup completed in #{(duration * 1000).round(2)}ms"
      puts "  Patterns loaded:     #{result[:patterns]}"
      puts "  Composites loaded:   #{result[:composites]}"
      puts "  User prefs loaded:   #{result[:user_prefs]}"
      
      # Test cache hits
      puts "\nTesting cache hits after warmup..."
      
      if result[:patterns] > 0
        pattern = CategorizationPattern.active.frequently_used.first
        if pattern
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          cache.get_pattern(pattern.id)
          lookup_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
          
          puts "  Sample pattern lookup: #{lookup_time.round(3)}ms"
        end
      end
      
      final_metrics = cache.metrics
      puts "\nFinal metrics:"
      puts "  Memory hits: #{final_metrics[:hits][:memory]}"
      puts "  Redis hits:  #{final_metrics[:hits][:redis]}"
      puts "  Misses:      #{final_metrics[:misses]}"
      puts "  Hit rate:    #{final_metrics[:hit_rate]}%"
      
      puts "\n" + "=" * 80
      puts "WARMUP TEST COMPLETE"
      puts "=" * 80 + "\n"
    end
  end
end