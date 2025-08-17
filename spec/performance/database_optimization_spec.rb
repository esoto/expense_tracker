# frozen_string_literal: true

require "rails_helper"
require "benchmark"

RSpec.describe "Database Optimization Performance", type: :performance do
  # Create a realistic dataset for performance testing
  before(:all) do
    Rails.logger.info "Creating performance test dataset..."
    
    @email_account = EmailAccount.create!(
      provider: "gmail",
      email: "perf_test@example.com",
      bank_name: "Performance Test Bank",
      encrypted_password: "encrypted_test"
    )
    
    @categories = 10.times.map do |i|
      Category.create!(name: "Test Category #{i}")
    end
    
    # Create 10,000 expenses for performance testing
    expenses_data = []
    10_000.times do |i|
      expenses_data << {
        amount: rand(100..10000),
        description: "Test expense #{i}",
        transaction_date: rand(365).days.ago,
        merchant_name: ["Amazon", "Walmart", "Target", "Costco", "Home Depot"].sample,
        email_account_id: @email_account.id,
        category_id: (i % 3 == 0) ? nil : @categories.sample.id, # 33% uncategorized
        status: ["pending", "processed", "failed"].sample,
        bank_name: ["BAC", "BCR", "BN"].sample,
        currency: [0, 1].sample, # CRC or USD
        created_at: Time.current,
        updated_at: Time.current
      }
      
      # Batch insert every 1000 records
      if expenses_data.size >= 1000
        Expense.insert_all!(expenses_data)
        expenses_data = []
      end
    end
    
    # Insert remaining records
    Expense.insert_all!(expenses_data) if expenses_data.any?
    
    # Analyze table to update statistics
    ActiveRecord::Base.connection.execute("ANALYZE expenses;")
    
    Rails.logger.info "Performance test dataset created: #{Expense.count} expenses"
  end
  
  after(:all) do
    # Clean up test data
    if @email_account
      Expense.where(email_account_id: @email_account.id).delete_all
      @categories&.each(&:destroy)
      @email_account.destroy
    end
  end
  
  describe "Query Performance Targets" do
    it "meets <50ms target for date range filtering" do
      time = Benchmark.realtime do
        Expense.where(
          email_account_id: @email_account.id,
          transaction_date: 30.days.ago..Time.current,
          deleted_at: nil
        ).limit(50).to_a
      end
      
      expect(time * 1000).to be < 50, "Date range query took #{(time * 1000).round(2)}ms (target: <50ms)"
    end
    
    it "meets <50ms target for category filtering" do
      time = Benchmark.realtime do
        Expense.where(
          email_account_id: @email_account.id,
          category_id: @categories.first(3).map(&:id),
          deleted_at: nil
        ).limit(50).to_a
      end
      
      expect(time * 1000).to be < 50, "Category filter query took #{(time * 1000).round(2)}ms (target: <50ms)"
    end
    
    it "meets <50ms target for uncategorized expenses" do
      time = Benchmark.realtime do
        Expense.where(
          email_account_id: @email_account.id,
          category_id: nil,
          deleted_at: nil
        ).order(transaction_date: :desc).limit(50).to_a
      end
      
      expect(time * 1000).to be < 50, "Uncategorized query took #{(time * 1000).round(2)}ms (target: <50ms)"
    end
    
    it "meets <50ms target for merchant search" do
      time = Benchmark.realtime do
        Expense.where(
          email_account_id: @email_account.id,
          deleted_at: nil
        ).where("merchant_name ILIKE ?", "%amazon%").limit(50).to_a
      end
      
      expect(time * 1000).to be < 50, "Merchant search took #{(time * 1000).round(2)}ms (target: <50ms)"
    end
    
    it "meets <50ms target for amount range filtering" do
      time = Benchmark.realtime do
        Expense.where(
          email_account_id: @email_account.id,
          amount: 1000..5000,
          deleted_at: nil
        ).limit(50).to_a
      end
      
      expect(time * 1000).to be < 50, "Amount range query took #{(time * 1000).round(2)}ms (target: <50ms)"
    end
    
    it "meets <50ms target for complex multi-filter queries" do
      time = Benchmark.realtime do
        Expense.where(
          email_account_id: @email_account.id,
          transaction_date: 30.days.ago..Time.current,
          category_id: @categories.first(3).map(&:id),
          status: "processed",
          deleted_at: nil
        ).where("amount > ?", 1000).limit(50).to_a
      end
      
      expect(time * 1000).to be < 50, "Complex query took #{(time * 1000).round(2)}ms (target: <50ms)"
    end
    
    it "meets <50ms target for dashboard display with covering index" do
      time = Benchmark.realtime do
        Expense
          .select(:id, :amount, :description, :transaction_date, :merchant_name,
                  :category_id, :status, :bank_name, :currency, :auto_categorized,
                  :categorization_confidence, :created_at, :updated_at)
          .where(email_account_id: @email_account.id, deleted_at: nil)
          .order(transaction_date: :desc)
          .limit(50)
          .to_a
      end
      
      expect(time * 1000).to be < 50, "Dashboard display query took #{(time * 1000).round(2)}ms (target: <50ms)"
    end
    
    it "meets <50ms target for batch selection queries" do
      time = Benchmark.realtime do
        Expense.where(
          email_account_id: @email_account.id,
          status: "pending",
          deleted_at: nil
        ).order(created_at: :desc).limit(100).pluck(:id)
      end
      
      expect(time * 1000).to be < 50, "Batch selection query took #{(time * 1000).round(2)}ms (target: <50ms)"
    end
  end
  
  describe "Index Usage Verification" do
    it "uses idx_expenses_list_covering for dashboard queries" do
      plan = explain_query(
        Expense
          .select(:id, :amount, :description, :transaction_date, :merchant_name, :category_id, :status)
          .where(email_account_id: @email_account.id, deleted_at: nil)
          .order(transaction_date: :desc)
          .limit(50)
      )
      
      expect(plan).to include("idx_expenses_list_covering")
    end
    
    it "uses idx_expenses_amount_brin for amount range queries" do
      plan = explain_query(
        Expense.where(amount: 1000..5000, deleted_at: nil).limit(50)
      )
      
      expect(plan).to include("idx_expenses_amount_brin")
    end
    
    it "uses idx_expenses_uncategorized_optimized for uncategorized queries" do
      plan = explain_query(
        Expense.where(category_id: nil, deleted_at: nil, email_account_id: @email_account.id)
          .order(transaction_date: :desc)
          .limit(50)
      )
      
      expect(plan).to include("idx_expenses_uncategorized_optimized")
    end
    
    it "uses idx_expenses_pending_status for status filtering" do
      plan = explain_query(
        Expense.where(status: "pending", deleted_at: nil, email_account_id: @email_account.id)
          .order(created_at: :desc)
          .limit(50)
      )
      
      expect(plan).to include("idx_expenses_pending_status")
    end
    
    it "avoids sequential scans for dashboard queries" do
      plan = explain_query(
        Expense.where(
          email_account_id: @email_account.id,
          deleted_at: nil,
          transaction_date: 30.days.ago..Time.current
        ).limit(50)
      )
      
      expect(plan).not_to include("Seq Scan")
    end
  end
  
  describe "N+1 Query Prevention" do
    it "avoids N+1 queries when loading categories" do
      expect do
        expenses = Expense
          .includes(:category)
          .where(email_account_id: @email_account.id, deleted_at: nil)
          .limit(50)
        
        # Access category for each expense
        expenses.each { |e| e.category&.name }
      end.to perform_queries(2) # One for expenses, one for categories
    end
  end
  
  private
  
  def explain_query(relation)
    sql = relation.to_sql
    result = ActiveRecord::Base.connection.execute("EXPLAIN #{sql}")
    result.values.flatten.join("\n")
  end
  
  # Custom RSpec matcher for query count
  RSpec::Matchers.define :perform_queries do |expected|
    match do |block|
      query_count = 0
      
      counter = ->(*) { query_count += 1 }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        block.call
      end
      
      query_count == expected
    end
    
    failure_message do |actual|
      "expected #{expected} queries, but got #{@actual_count}"
    end
    
    supports_block_expectations
  end
end