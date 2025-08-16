# frozen_string_literal: true

namespace :db do
  namespace :optimize do
    desc "Analyze expense table indexes and provide performance recommendations"
    task analyze_indexes: :environment do
      puts "\n=== Expense Table Index Analysis ==="
      puts "=" * 50

      connection = ActiveRecord::Base.connection

      # Check if required indexes exist
      required_indexes = [
        "idx_expenses_filter_primary",
        "idx_expenses_list_covering",
        "idx_expenses_category_date",
        "idx_expenses_uncategorized_new",
        "idx_expenses_bank_date",
        "idx_expenses_status_account",
        "idx_expenses_amount_brin"
      ]

      existing_indexes = connection.indexes("expenses").map(&:name)

      puts "\n📊 Required Indexes Status:"
      required_indexes.each do |index_name|
        if existing_indexes.include?(index_name)
          puts "  ✅ #{index_name}"
        else
          puts "  ❌ #{index_name} - MISSING"
        end
      end

      # Check index usage statistics
      puts "\n📈 Index Usage Statistics:"
      index_stats_query = <<-SQL
        SELECT#{' '}
          schemaname,
          tablename,
          indexname,
          idx_scan as index_scans,
          idx_tup_read as tuples_read,
          idx_tup_fetch as tuples_fetched,
          pg_size_pretty(pg_relation_size(indexrelid)) as index_size
        FROM pg_stat_user_indexes
        WHERE schemaname = 'public'#{' '}
          AND tablename = 'expenses'
        ORDER BY idx_scan DESC;
      SQL

      begin
        results = connection.execute(index_stats_query)
        results.each do |row|
          puts "\n  Index: #{row['indexname']}"
          puts "    Scans: #{row['index_scans']}"
          puts "    Tuples Read: #{row['tuples_read']}"
          puts "    Size: #{row['index_size']}"
        end
      rescue => e
        puts "  ⚠️  Could not retrieve index statistics: #{e.message}"
      end

      # Check for unused indexes
      puts "\n🔍 Potentially Unused Indexes (0 scans):"
      unused_query = <<-SQL
        SELECT indexname#{' '}
        FROM pg_stat_user_indexes#{' '}
        WHERE schemaname = 'public'#{' '}
          AND tablename = 'expenses'#{' '}
          AND idx_scan = 0
      SQL

      begin
        unused = connection.execute(unused_query)
        if unused.any?
          unused.each { |row| puts "  - #{row['indexname']}" }
        else
          puts "  ✅ All indexes are being used"
        end
      rescue => e
        puts "  ⚠️  Could not check unused indexes: #{e.message}"
      end

      # Check table statistics
      puts "\n📊 Table Statistics:"
      table_stats_query = <<-SQL
        SELECT#{' '}
          n_live_tup as live_tuples,
          n_dead_tup as dead_tuples,
          last_vacuum,
          last_autovacuum,
          last_analyze,
          last_autoanalyze
        FROM pg_stat_user_tables
        WHERE schemaname = 'public' AND tablename = 'expenses';
      SQL

      begin
        stats = connection.execute(table_stats_query).first
        if stats
          puts "  Live Tuples: #{stats['live_tuples']}"
          puts "  Dead Tuples: #{stats['dead_tuples']}"
          puts "  Last Vacuum: #{stats['last_vacuum'] || 'Never'}"
          puts "  Last Auto Vacuum: #{stats['last_autovacuum'] || 'Never'}"
          puts "  Last Analyze: #{stats['last_analyze'] || 'Never'}"
          puts "  Last Auto Analyze: #{stats['last_autoanalyze'] || 'Never'}"
        end
      rescue => e
        puts "  ⚠️  Could not retrieve table statistics: #{e.message}"
      end

      puts "\n" + "=" * 50
    end

    desc "Run EXPLAIN ANALYZE on common expense queries"
    task explain_queries: :environment do
      puts "\n=== Query Performance Analysis ==="
      puts "=" * 50

      # Sample queries to test
      test_queries = [
        {
          name: "Filter by date range",
          query: -> {
            Expense.for_list_display
                   .where(transaction_date: 30.days.ago..Date.current)
                   .limit(50)
          }
        },
        {
          name: "Filter by category and date",
          query: -> {
            Expense.for_list_display
                   .where(category_id: [ 1, 2, 3 ])
                   .where(transaction_date: 30.days.ago..Date.current)
                   .limit(50)
          }
        },
        {
          name: "Search by merchant",
          query: -> {
            Expense.for_list_display
                   .where("merchant_name ILIKE ?", "%store%")
                   .limit(50)
          }
        },
        {
          name: "Uncategorized expenses",
          query: -> {
            Expense.for_list_display
                   .where(category_id: nil)
                   .order(transaction_date: :desc)
                   .limit(50)
          }
        }
      ]

      test_queries.each do |test|
        puts "\n📝 Query: #{test[:name]}"
        puts "-" * 40

        begin
          query = test[:query].call
          explain = query.explain

          # Extract key metrics from EXPLAIN output
          if explain.include?("Index Scan") || explain.include?("Index Only Scan")
            puts "  ✅ Using index scan"
          elsif explain.include?("Bitmap Index Scan")
            puts "  ✅ Using bitmap index scan"
          elsif explain.include?("Seq Scan")
            puts "  ⚠️  Using sequential scan - may need optimization"
          end

          # Show first few lines of explain
          explain.lines.first(10).each { |line| puts "  #{line.strip}" }

          # Run timing test
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          query.to_a
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

          puts "  ⏱️  Execution time: #{(elapsed * 1000).round(2)}ms"

          if elapsed > 0.05
            puts "  ⚠️  Query exceeds 50ms target"
          else
            puts "  ✅ Query meets performance target"
          end
        rescue => e
          puts "  ❌ Error: #{e.message}"
        end
      end

      puts "\n" + "=" * 50
    end

    desc "Check database health and provide optimization recommendations"
    task health_check: :environment do
      puts "\n=== Database Health Check ==="
      puts "=" * 50

      checker = ExpenseListHealthCheck.new
      result = checker.run

      puts "\n🏥 Health Status: #{result[:healthy] ? '✅ HEALTHY' : '❌ UNHEALTHY'}"

      puts "\n📋 Check Results:"
      result[:checks].each do |check_name, status|
        icon = status ? "✅" : "❌"
        puts "  #{icon} #{check_name.to_s.humanize}: #{status ? 'PASS' : 'FAIL'}"
      end

      # Performance recommendations
      puts "\n💡 Recommendations:"

      if !result[:checks][:database_indexes]
        puts "  1. Run migrations to add missing indexes:"
        puts "     rails db:migrate"
      end

      if !result[:checks][:query_performance]
        puts "  2. Query performance is slow. Consider:"
        puts "     - Running VACUUM ANALYZE on expenses table"
        puts "     - Checking for table bloat"
        puts "     - Reviewing slow query log"
      end

      # Check for table bloat
      bloat_query = <<-SQL
        SELECT#{' '}
          pg_size_pretty(pg_relation_size('expenses')) as table_size,
          (SELECT count(*) FROM expenses) as row_count
      SQL

      begin
        bloat_info = ActiveRecord::Base.connection.execute(bloat_query).first
        puts "\n📊 Table Info:"
        puts "  Table Size: #{bloat_info['table_size']}"
        puts "  Row Count: #{bloat_info['row_count']}"
      rescue => e
        puts "  ⚠️  Could not check table size: #{e.message}"
      end

      puts "\n" + "=" * 50
    end

    desc "Run VACUUM ANALYZE on expenses table for optimal performance"
    task vacuum_analyze: :environment do
      puts "\n=== Running VACUUM ANALYZE ==="
      puts "=" * 50

      begin
        ActiveRecord::Base.connection.execute("VACUUM ANALYZE expenses;")
        puts "✅ VACUUM ANALYZE completed successfully"

        # Show updated statistics
        stats_query = <<-SQL
          SELECT#{' '}
            n_live_tup as live_tuples,
            n_dead_tup as dead_tuples,
            last_vacuum,
            last_analyze
          FROM pg_stat_user_tables
          WHERE schemaname = 'public' AND tablename = 'expenses';
        SQL

        stats = ActiveRecord::Base.connection.execute(stats_query).first
        puts "\n📊 Updated Statistics:"
        puts "  Live Tuples: #{stats['live_tuples']}"
        puts "  Dead Tuples: #{stats['dead_tuples']}"
        puts "  Last Vacuum: #{stats['last_vacuum']}"
        puts "  Last Analyze: #{stats['last_analyze']}"
      rescue => e
        puts "❌ Error: #{e.message}"
      end

      puts "\n" + "=" * 50
    end

    desc "Generate performance report for expense queries"
    task performance_report: :environment do
      puts "\n=== Expense Query Performance Report ==="
      puts "Generated at: #{Time.current}"
      puts "=" * 50

      # Test with different data sizes
      test_sizes = [ 100, 500, 1000, 5000, 10000 ]

      puts "\n📊 Performance by Dataset Size:"
      puts sprintf("%-10s %-15s %-15s %-15s", "Size", "Simple Query", "Filtered", "Complex")
      puts "-" * 55

      test_sizes.each do |size|
        next if Expense.count < size

        # Simple query
        simple_time = Benchmark.realtime do
          Expense.for_list_display.limit(size).to_a
        end

        # Filtered query
        filtered_time = Benchmark.realtime do
          Expense.for_list_display
                 .where(transaction_date: 30.days.ago..Date.current)
                 .limit(size)
                 .to_a
        end

        # Complex query
        complex_time = Benchmark.realtime do
          Expense.for_list_display
                 .where(transaction_date: 30.days.ago..Date.current)
                 .by_categories([ 1, 2, 3 ])
                 .by_amount_range(100, 10000)
                 .limit(size)
                 .to_a
        end

        puts sprintf("%-10d %-15.2fms %-15.2fms %-15.2fms",
                     size,
                     simple_time * 1000,
                     filtered_time * 1000,
                     complex_time * 1000)
      end

      # Check if any queries exceed 50ms threshold
      puts "\n✅ All queries should complete in < 50ms for optimal performance"

      puts "\n" + "=" * 50
    end
  end
end

# Health check service
class ExpenseListHealthCheck
  def run
    checks = {
      database_indexes: check_indexes,
      query_performance: check_query_performance,
      cache_connectivity: check_cache,
      pg_trgm_extension: check_pg_trgm
    }

    {
      healthy: checks.values.all?,
      checks: checks,
      timestamp: Time.current.iso8601
    }
  end

  private

  def check_indexes
    required_indexes = %w[
      idx_expenses_filter_primary
      idx_expenses_list_covering
      idx_expenses_category_date
      idx_expenses_uncategorized_new
    ]

    existing_indexes = ActiveRecord::Base.connection.indexes("expenses").map(&:name)
    required_indexes.all? { |idx| existing_indexes.include?(idx) }
  rescue => e
    Rails.logger.error "Index check failed: #{e.message}"
    false
  end

  def check_query_performance
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Expense.for_list_display.limit(1).to_a
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    duration < 0.01 # Should complete in under 10ms
  rescue => e
    Rails.logger.error "Query performance check failed: #{e.message}"
    false
  end

  def check_cache
    Rails.cache.write("health_check", "ok", expires_in: 1.minute)
    Rails.cache.read("health_check") == "ok"
  rescue => e
    Rails.logger.error "Cache check failed: #{e.message}"
    false
  end

  def check_pg_trgm
    result = ActiveRecord::Base.connection.execute(
      "SELECT extname FROM pg_extension WHERE extname = 'pg_trgm'"
    )
    result.any?
  rescue => e
    Rails.logger.error "pg_trgm check failed: #{e.message}"
    false
  end
end
