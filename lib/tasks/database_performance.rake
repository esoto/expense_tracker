# frozen_string_literal: true

namespace :db do
  namespace :performance do
    desc "Analyze and report on database index usage and query performance"
    task analyze: :environment do
      puts "\n=== Database Performance Analysis ==="
      puts "Target: All dashboard queries < 50ms"
      puts "=" * 50
      
      # Check index usage statistics
      puts "\n📊 Index Usage Statistics:"
      index_stats = ActiveRecord::Base.connection.execute(<<-SQL)
        SELECT 
          schemaname,
          tablename,
          indexname,
          idx_scan as index_scans,
          idx_tup_read as tuples_read,
          idx_tup_fetch as tuples_fetched,
          pg_size_pretty(pg_relation_size(indexrelid)) as index_size
        FROM pg_stat_user_indexes
        WHERE tablename = 'expenses'
        ORDER BY idx_scan DESC;
      SQL
      
      index_stats.each do |row|
        puts "  • #{row['indexname']}: #{row['index_scans']} scans, #{row['index_size']} size"
      end
      
      # Check for unused indexes
      puts "\n⚠️  Potentially Unused Indexes (0 scans):"
      unused = index_stats.select { |r| r['index_scans'].to_i == 0 }
      if unused.any?
        unused.each { |r| puts "  • #{r['indexname']}" }
      else
        puts "  None found - all indexes are being used"
      end
      
      # Check table bloat
      puts "\n📈 Table Statistics:"
      table_stats = ActiveRecord::Base.connection.execute(<<-SQL)
        SELECT 
          n_live_tup as live_tuples,
          n_dead_tup as dead_tuples,
          n_tup_ins as inserts,
          n_tup_upd as updates,
          n_tup_del as deletes,
          last_vacuum,
          last_autovacuum,
          last_analyze,
          last_autoanalyze,
          pg_size_pretty(pg_relation_size('expenses')) as table_size
        FROM pg_stat_user_tables
        WHERE tablename = 'expenses';
      SQL
      
      stats = table_stats.first
      puts "  • Table size: #{stats['table_size']}"
      puts "  • Live tuples: #{stats['live_tuples']}"
      puts "  • Dead tuples: #{stats['dead_tuples']}"
      puts "  • Last vacuum: #{stats['last_vacuum'] || 'Never'}"
      puts "  • Last analyze: #{stats['last_analyze'] || 'Never'}"
      
      # Check for missing indexes
      puts "\n🔍 Checking for Missing Indexes:"
      missing_indexes = check_missing_indexes
      if missing_indexes.any?
        missing_indexes.each { |idx| puts "  • #{idx}" }
      else
        puts "  All required indexes are present"
      end
      
      # Performance test with sample queries
      puts "\n⏱️  Query Performance Test:"
      run_performance_tests
      
      puts "\n=== Analysis Complete ==="
    end
    
    desc "Verify all Epic 3 required indexes exist"
    task verify_indexes: :environment do
      puts "\n=== Verifying Epic 3 Database Indexes ==="
      
      required_indexes = [
        "idx_expenses_list_covering",
        "idx_expenses_amount_brin",
        "idx_expenses_batch_operations",
        "idx_expenses_dashboard_filters",
        "idx_expenses_uncategorized_optimized",
        "idx_expenses_pending_status",
        "idx_expenses_merchant_search",
        "idx_expenses_primary_filter"
      ]
      
      existing_indexes = ActiveRecord::Base.connection.indexes(:expenses).map(&:name)
      
      missing = required_indexes - existing_indexes
      extra = existing_indexes - required_indexes
      
      if missing.empty?
        puts "✅ All required indexes are present"
      else
        puts "❌ Missing indexes:"
        missing.each { |idx| puts "  • #{idx}" }
      end
      
      if extra.any?
        puts "\n📝 Additional indexes found (may be redundant):"
        extra.each { |idx| puts "  • #{idx}" }
      end
      
      # Check for INCLUDE clause support
      covering_index = ActiveRecord::Base.connection.execute(<<-SQL)
        SELECT 
          indexdef 
        FROM pg_indexes 
        WHERE indexname = 'idx_expenses_list_covering';
      SQL
      
      if covering_index.any? && covering_index.first['indexdef'].include?('INCLUDE')
        puts "\n✅ Covering index properly uses INCLUDE clause"
      else
        puts "\n⚠️  Covering index may not be using INCLUDE clause for optimal performance"
      end
    end
    
    desc "Run VACUUM and ANALYZE on expenses table"
    task maintain: :environment do
      puts "\n=== Running Database Maintenance ==="
      
      puts "Running VACUUM on expenses table..."
      ActiveRecord::Base.connection.execute("VACUUM ANALYZE expenses;")
      puts "✅ VACUUM complete"
      
      puts "\nReindexing expenses table indexes..."
      ActiveRecord::Base.connection.execute("REINDEX TABLE expenses;")
      puts "✅ REINDEX complete"
      
      puts "\nUpdating table statistics..."
      ActiveRecord::Base.connection.execute("ANALYZE expenses;")
      puts "✅ ANALYZE complete"
      
      puts "\n=== Maintenance Complete ==="
    end
    
    desc "Generate EXPLAIN plans for common queries"
    task explain: :environment do
      puts "\n=== Query Execution Plans ==="
      
      sample_account_id = EmailAccount.first&.id || 1
      
      queries = {
        "Dashboard listing" => Expense.where(
          email_account_id: sample_account_id,
          deleted_at: nil
        ).order(transaction_date: :desc).limit(50),
        
        "Date range filter" => Expense.where(
          email_account_id: sample_account_id,
          transaction_date: 30.days.ago..Time.current,
          deleted_at: nil
        ).limit(50),
        
        "Uncategorized" => Expense.where(
          email_account_id: sample_account_id,
          category_id: nil,
          deleted_at: nil
        ).limit(50),
        
        "Amount range" => Expense.where(
          amount: 1000..5000,
          deleted_at: nil
        ).limit(50)
      }
      
      queries.each do |name, query|
        puts "\n📋 #{name}:"
        puts query.explain
      end
    end
    
    private
    
    def check_missing_indexes
      missing = []
      
      # Check for covering index with INCLUDE
      result = ActiveRecord::Base.connection.execute(<<-SQL)
        SELECT COUNT(*) as count
        FROM pg_indexes
        WHERE indexname = 'idx_expenses_list_covering'
        AND indexdef LIKE '%INCLUDE%';
      SQL
      
      if result.first['count'].to_i == 0
        missing << "Covering index missing INCLUDE clause"
      end
      
      # Check for BRIN index
      result = ActiveRecord::Base.connection.execute(<<-SQL)
        SELECT COUNT(*) as count
        FROM pg_indexes
        WHERE tablename = 'expenses'
        AND indexdef LIKE '%USING brin%';
      SQL
      
      if result.first['count'].to_i == 0
        missing << "BRIN index for amount ranges"
      end
      
      missing
    end
    
    def run_performance_tests
      return puts "  No test data available" if Expense.count == 0
      
      account_id = EmailAccount.first&.id
      return puts "  No email account available for testing" unless account_id
      
      tests = {
        "Date range (30 days)" => -> {
          Expense.where(
            email_account_id: account_id,
            transaction_date: 30.days.ago..Time.current,
            deleted_at: nil
          ).limit(50).to_a
        },
        "Uncategorized" => -> {
          Expense.where(
            email_account_id: account_id,
            category_id: nil,
            deleted_at: nil
          ).limit(50).to_a
        },
        "Amount range" => -> {
          Expense.where(
            amount: 1000..5000,
            deleted_at: nil
          ).limit(50).to_a
        }
      }
      
      tests.each do |name, query|
        time = Benchmark.realtime(&query) * 1000
        status = time < 50 ? "✅" : "❌"
        puts "  #{status} #{name}: #{time.round(2)}ms"
      end
    end
  end
end