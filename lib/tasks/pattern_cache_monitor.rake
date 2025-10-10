namespace :cache do
  desc "Live monitor for categorization pattern cache"
  task monitor: :environment do
    puts "🚀 CATEGORIZATION PATTERN CACHE - LIVE MONITOR"
    puts "=" * 60
    puts "Press Ctrl+C to stop monitoring"
    puts

    cache = Categorization::PatternCache.instance

    loop do
      begin
        # Clear screen
        system("clear") || system("cls")

        puts "🚀 CATEGORIZATION PATTERN CACHE - LIVE MONITOR"
        puts "=" * 60
        puts "Time: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
        puts

        # Get cache metrics
        metrics = cache.metrics

        # Cache Health
        puts "🏥 CACHE HEALTH"
        puts "-" * 30
        puts "Status: #{cache.healthy? ? '✅ Healthy' : '❌ Unhealthy'}"
        puts "Redis Available: #{metrics[:redis_available] ? '✅ Yes' : '❌ No'}"
        puts

        # Cache Statistics
        puts "📊 CACHE STATISTICS"
        puts "-" * 30
        puts "Memory Cache Entries: #{metrics[:memory_cache_entries]}"
        puts "Hit Rate: #{cache.hit_rate}%"
        puts "Total Hits: #{metrics.dig(:hits, :memory).to_i + metrics.dig(:hits, :redis).to_i}"
        puts "  - Memory Hits: #{metrics.dig(:hits, :memory) || 0}"
        puts "  - Redis Hits: #{metrics.dig(:hits, :redis) || 0}"
        puts "Total Misses: #{metrics[:misses] || 0}"
        puts

        # Configuration
        puts "⚙️  CONFIGURATION"
        puts "-" * 30
        config = metrics[:configuration] || {}
        puts "Memory TTL: #{config[:memory_ttl]} seconds"
        puts "Redis TTL: #{config[:redis_ttl]} seconds"
        puts "Max Memory Size: #{config[:max_memory_size]} KB"
        puts

        # Performance Operations
        operations = metrics[:operations] || {}
        if operations.any?
          puts "⚡ PERFORMANCE METRICS"
          puts "-" * 30
          operations.each do |op_name, stats|
            next if stats[:count].zero?

            puts "#{op_name}:"
            puts "  Count: #{stats[:count]}"
            puts "  Avg: #{stats[:avg_ms]}ms"
            puts "  P95: #{stats[:p95_ms]}ms"
            puts "  P99: #{stats[:p99_ms]}ms"
          end
          puts
        end

        # Cache Content Summary
        puts "📦 CACHE CONTENT"
        puts "-" * 30

        begin
          # Count patterns in database for comparison
          total_patterns = CategorizationPattern.active.count
          total_composites = CompositePattern.active.count rescue 0
          total_preferences = UserCategoryPreference.count

          puts "Active Patterns (DB): #{total_patterns}"
          puts "Active Composites (DB): #{total_composites}"
          puts "User Preferences (DB): #{total_preferences}"
        rescue => e
          puts "Database query error: #{e.message}"
        end

        puts
        puts "🔄 Refreshing in 3 seconds... (Ctrl+C to stop)"

        # Wait for 3 seconds
        sleep 3

      rescue Interrupt
        puts "\n\n👋 Monitor stopped by user"
        break
      rescue => e
        puts "\n❌ Error: #{e.message}"
        puts "Retrying in 5 seconds..."
        sleep 5
      end
    end
  end

  desc "Show current pattern cache status"
  task status: :environment do
    cache = Categorization::PatternCache.instance

    puts "🚀 CATEGORIZATION PATTERN CACHE - STATUS"
    puts "=" * 50
    puts "Time: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
    puts

    # Get cache metrics
    metrics = cache.metrics

    # Cache Health
    puts "🏥 CACHE HEALTH"
    puts "-" * 30
    puts "Status: #{cache.healthy? ? '✅ Healthy' : '❌ Unhealthy'}"
    puts "Redis Available: #{metrics[:redis_available] ? '✅ Yes' : '❌ No'}"
    puts

    # Cache Statistics
    puts "📊 CACHE STATISTICS"
    puts "-" * 30
    puts "Memory Cache Entries: #{metrics[:memory_cache_entries]}"
    puts "Hit Rate: #{cache.hit_rate}%"
    puts "Total Hits: #{metrics.dig(:hits, :memory).to_i + metrics.dig(:hits, :redis).to_i}"
    puts "  - Memory Hits: #{metrics.dig(:hits, :memory) || 0}"
    puts "  - Redis Hits: #{metrics.dig(:hits, :redis) || 0}"
    puts "Total Misses: #{metrics[:misses] || 0}"
    puts

    # Configuration
    puts "⚙️  CONFIGURATION"
    puts "-" * 30
    config = metrics[:configuration] || {}
    puts "Memory TTL: #{config[:memory_ttl]} seconds"
    puts "Redis TTL: #{config[:redis_ttl]} seconds"
    puts "Max Memory Size: #{config[:max_memory_size]} KB"
    puts

    # Performance Operations
    operations = metrics[:operations] || {}
    if operations.any?
      puts "⚡ PERFORMANCE METRICS"
      puts "-" * 30
      operations.each do |op_name, stats|
        next if stats[:count].zero?

        puts "#{op_name}:"
        puts "  Count: #{stats[:count]}"
        puts "  Avg: #{stats[:avg_ms]}ms"
        puts "  P95: #{stats[:p95_ms]}ms"
        puts "  P99: #{stats[:p99_ms]}ms"
      end
      puts
    end

    # Cache Content Summary
    puts "📦 CACHE CONTENT"
    puts "-" * 30

    begin
      # Count patterns in database for comparison
      total_patterns = CategorizationPattern.active.count
      total_composites = CompositePattern.active.count rescue 0
      total_preferences = UserCategoryPreference.count

      puts "Active Patterns (DB): #{total_patterns}"
      puts "Active Composites (DB): #{total_composites}"
      puts "User Preferences (DB): #{total_preferences}"
    rescue => e
      puts "Database query error: #{e.message}"
    end
    puts
  end

  desc "Warm up the pattern cache with sample data"
  task warm: :environment do
    puts "🔥 WARMING PATTERN CACHE"
    puts "=" * 40

    cache = Categorization::PatternCache.instance

    puts "Starting cache warmup..."
    result = cache.warm_cache

    if result.is_a?(Hash) && result[:error]
      puts "❌ Warmup failed: #{result[:error]}"
    else
      puts "✅ Cache warmup completed!"
      puts "   Patterns cached: #{result[:patterns] || 0}"
      puts "   Composites cached: #{result[:composites] || 0}"
      puts "   User preferences cached: #{result[:user_prefs] || 0}"
    end

    puts "\n📊 Final cache status:"
    metrics = cache.metrics
    puts "   Memory entries: #{metrics[:memory_cache_entries]}"
    puts "   Hit rate: #{cache.hit_rate}%"
  end

  desc "Generate sample cache activity for testing"
  task test_activity: :environment do
    puts "🧪 GENERATING SAMPLE CACHE ACTIVITY"
    puts "=" * 50

    cache = Categorization::PatternCache.instance

    # Get some patterns to test with
    patterns = CategorizationPattern.active.limit(10)

    if patterns.empty?
      puts "❌ No patterns found to test with"
      exit
    end

    puts "Testing with #{patterns.count} patterns..."

    # Generate some cache activity
    50.times do |i|
      pattern = patterns.sample

      # This will create cache misses and hits
      cached_pattern = cache.get_pattern(pattern.id)

      # Test user preferences
      if pattern.respond_to?(:merchant_name) && pattern.merchant_name.present?
        cache.get_user_preference(pattern.merchant_name)
      end

      print "." if (i + 1) % 10 == 0
    end

    puts "\n\n✅ Generated sample cache activity!"
    puts "\n📊 Updated cache status:"
    metrics = cache.metrics
    puts "   Memory entries: #{metrics[:memory_cache_entries]}"
    puts "   Hit rate: #{cache.hit_rate}%"
    puts "   Total hits: #{metrics.dig(:hits, :memory).to_i + metrics.dig(:hits, :redis).to_i}"
    puts "   Total misses: #{metrics[:misses] || 0}"
  end
end
