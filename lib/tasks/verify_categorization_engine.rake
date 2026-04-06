# frozen_string_literal: true

namespace :categorization do
  desc "Verify categorization engine works end-to-end with shared thread pool"
  task verify: :environment do
    puts "=" * 60
    puts "Categorization Engine Verification"
    puts "=" * 60
    puts ""

    errors = []

    # 1. Shared thread pool singleton
    print "1. Shared thread pool singleton... "
    begin
      pool1 = Services::Categorization::Engine.shared_thread_pool
      pool2 = Services::Categorization::Engine.shared_thread_pool
      raise "Not a singleton!" unless pool1.equal?(pool2)
      raise "Pool not running!" unless pool1.running?
      puts "PASS (#{pool1.class}, running, #{pool1.min_length}-#{pool1.max_length} threads)"
    rescue => e
      errors << "Thread pool: #{e.message}"
      puts "FAIL: #{e.message}"
    end

    # 2. Engine creation via factory
    print "2. EngineFactory.default... "
    begin
      engine = Services::Categorization::EngineFactory.default
      raise "Engine is nil!" if engine.nil?
      raise "Engine is shutdown!" if engine.shutdown?
      pool = engine.instance_variable_get(:@thread_pool)
      raise "Engine pool is nil!" if pool.nil?
      raise "Engine pool not shared!" unless pool.equal?(Services::Categorization::Engine.shared_thread_pool)
      puts "PASS (engine created, pool shared)"
    rescue => e
      errors << "EngineFactory: #{e.message}"
      puts "FAIL: #{e.message}"
    end

    # 3. Multiple engine instances share pool
    print "3. Multiple engines share pool... "
    begin
      Services::Categorization::EngineFactory.reset!
      e1 = Services::Categorization::EngineFactory.default
      e2 = Services::Categorization::EngineFactory.create("test_engine")
      p1 = e1.instance_variable_get(:@thread_pool)
      p2 = e2.instance_variable_get(:@thread_pool)
      raise "Pools not shared!" unless p1.equal?(p2)
      puts "PASS (2 engines, same pool object)"
    rescue => e
      errors << "Multi-engine: #{e.message}"
      puts "FAIL: #{e.message}"
    end

    # 4. Engine shutdown doesn't kill shared pool
    print "4. Engine shutdown preserves pool... "
    begin
      test_engine = Services::Categorization::Engine.create
      pool_before = Services::Categorization::Engine.shared_thread_pool
      test_engine.shutdown!
      raise "Pool stopped running!" unless pool_before.running?
      # Create new engine after shutdown — should work
      new_engine = Services::Categorization::Engine.create
      new_pool = new_engine.instance_variable_get(:@thread_pool)
      raise "New engine got dead pool!" unless new_pool.running?
      puts "PASS (pool survives engine shutdown)"
    rescue => e
      errors << "Shutdown: #{e.message}"
      puts "FAIL: #{e.message}"
    end

    # 5. Thread pool can execute work
    print "5. Thread pool executes work... "
    begin
      pool = Services::Categorization::Engine.shared_thread_pool
      result = Concurrent::Future.execute(executor: pool) { 42 }
      value = result.value(5) # 5 second timeout
      raise "Got nil!" if value.nil?
      raise "Wrong result: #{value}" unless value == 42
      puts "PASS (async execution returned #{value})"
    rescue => e
      errors << "Execution: #{e.message}"
      puts "FAIL: #{e.message}"
    end

    # 6. Categorize an expense (if data exists)
    print "6. Categorize expense... "
    begin
      expense = Expense.order(:id).first
      if expense
        engine = Services::Categorization::EngineFactory.default
        result = engine.categorize(expense)
        cat_name = result.respond_to?(:category) ? result.category&.name : result[:category]&.name
        conf = result.respond_to?(:confidence) ? result.confidence : result[:confidence]
        puts "PASS (expense ##{expense.id}: #{cat_name || 'no match'}, confidence: #{conf&.round(2) || 'N/A'})"
      else
        puts "SKIP (no expenses in database)"
      end
    rescue => e
      errors << "Categorize: #{e.message}"
      puts "FAIL: #{e.message}"
    end

    # 7. Batch categorize (if data exists)
    print "7. Batch categorize... "
    begin
      expenses = Expense.limit(5).to_a
      if expenses.any?
        engine = Services::Categorization::EngineFactory.default
        results = engine.batch_categorize(expenses)
        successful = results.count { |r| r.respond_to?(:successful?) ? r.successful? : r[:category].present? }
        puts "PASS (#{successful}/#{expenses.size} categorized)"
      else
        puts "SKIP (no expenses in database)"
      end
    rescue => e
      errors << "Batch: #{e.message}"
      puts "FAIL: #{e.message}"
    end

    # 8. Pool metrics
    print "8. Pool metrics... "
    begin
      pool = Services::Categorization::Engine.shared_thread_pool
      metrics = {
        active: pool.active_count,
        completed: pool.completed_task_count,
        queue: pool.queue_length,
        pool_size: pool.length
      }
      puts "PASS (active: #{metrics[:active]}, completed: #{metrics[:completed]}, queue: #{metrics[:queue]}, size: #{metrics[:pool_size]})"
    rescue => e
      errors << "Metrics: #{e.message}"
      puts "FAIL: #{e.message}"
    end

    # Summary
    puts ""
    puts "=" * 60
    if errors.empty?
      puts "ALL CHECKS PASSED"
    else
      puts "#{errors.size} FAILURES:"
      errors.each { |e| puts "  - #{e}" }
    end
    puts "=" * 60
  end
end
