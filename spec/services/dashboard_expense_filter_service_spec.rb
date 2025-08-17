# frozen_string_literal: true

require "rails_helper"

RSpec.describe DashboardExpenseFilterService, type: :service do
  let(:email_account) { create(:email_account) }
  let(:category1) { create(:category, name: "Food", color: "#FF6B6B") }
  let(:category2) { create(:category, name: "Transport", color: "#4ECDC4") }
  
  let!(:expense1) do
    create(:expense,
           email_account: email_account,
           category: category1,
           amount: 1000,
           transaction_date: Date.current,
           merchant_name: "Restaurant ABC",
           status: "processed")
  end
  
  let!(:expense2) do
    create(:expense,
           email_account: email_account,
           category: category2,
           amount: 500,
           transaction_date: 1.day.ago,
           merchant_name: "Uber",
           status: "processed")
  end
  
  let!(:expense3) do
    create(:expense,
           email_account: email_account,
           category: nil,
           amount: 750,
           transaction_date: 2.days.ago,
           merchant_name: "Store XYZ",
           status: "pending")
  end
  
  let(:base_params) do
    {
      account_ids: [email_account.id]
    }
  end
  
  describe "#initialize" do
    it "sets dashboard-specific defaults" do
      service = described_class.new(base_params)
      
      expect(service.per_page).to eq(10)
      expect(service.page).to eq(1)
    end
    
    it "respects dashboard limit constraints" do
      service = described_class.new(base_params.merge(per_page: 100))
      
      expect(service.per_page).to eq(50) # MAX_DASHBOARD_LIMIT
    end
    
    it "handles period-based filtering" do
      service = described_class.new(base_params.merge(period: "week"))
      
      expect(service.start_date).to eq(Date.current.beginning_of_week)
      expect(service.end_date).to eq(Date.current.end_of_week)
    end
  end
  
  describe "#call" do
    subject(:result) { described_class.new(params).call }
    
    context "with basic filtering" do
      let(:params) { base_params }
      
      it "returns a DashboardResult" do
        expect(result).to be_a(DashboardExpenseFilterService::DashboardResult)
      end
      
      it "returns all expenses" do
        expect(result.expenses.count).to eq(3)
      end
      
      it "includes performance metrics" do
        expect(result.performance_metrics).to include(
          :query_time_ms,
          :queries_executed,
          :rows_examined,
          :dashboard_optimized
        )
      end
      
      it "tracks that it's dashboard optimized" do
        expect(result.performance_metrics[:dashboard_optimized]).to be true
      end
      
      it "executes efficiently" do
        expect(result.performance_metrics[:query_time_ms]).to be < 50
      end
    end
    
    context "with category filtering" do
      let(:params) { base_params.merge(category_ids: [category1.id]) }
      
      it "filters by category" do
        expect(result.expenses.count).to eq(1)
        expect(result.expenses.first).to eq(expense1)
      end
      
      it "counts active filters" do
        expect(result.metadata[:filters_applied]).to eq(1)
      end
    end
    
    context "with status filtering" do
      let(:params) { base_params.merge(status: "pending") }
      
      it "filters by status" do
        expect(result.expenses.count).to eq(1)
        expect(result.expenses.first).to eq(expense3)
      end
    end
    
    context "with uncategorized filter" do
      let(:params) { base_params.merge(status: "uncategorized") }
      
      it "returns uncategorized expenses" do
        expect(result.expenses.count).to eq(1)
        expect(result.expenses.first.category).to be_nil
      end
    end
    
    context "with amount range filtering" do
      let(:params) { base_params.merge(min_amount: 600, max_amount: 900) }
      
      it "filters by amount range" do
        expect(result.expenses.count).to eq(1)
        expect(result.expenses.first.amount).to eq(750)
      end
    end
    
    context "with search query" do
      let(:params) { base_params.merge(search_query: "uber") }
      
      it "searches by merchant name" do
        expect(result.expenses.count).to eq(1)
        expect(result.expenses.first.merchant_name).to eq("Uber")
      end
    end
    
    context "with pagination" do
      let(:params) { base_params.merge(per_page: 2, page: 1) }
      
      it "paginates results" do
        expect(result.expenses.count).to eq(2)
      end
      
      it "indicates more pages available" do
        expect(result.metadata[:has_more]).to be true
      end
      
      it "includes total count" do
        expect(result.total_count).to eq(3)
      end
    end
    
    context "with sorting" do
      let(:params) { base_params.merge(sort_by: "amount", sort_direction: "asc") }
      
      it "sorts by specified column" do
        amounts = result.expenses.map(&:amount)
        expect(amounts).to eq([500, 750, 1000])
      end
    end
    
    context "with summary stats" do
      let(:params) { base_params.merge(include_summary: true) }
      
      it "includes summary statistics" do
        expect(result.summary_stats).to include(
          :total_count,
          :total_amount,
          :average_amount,
          :min_amount,
          :max_amount,
          :unique_merchants,
          :unique_categories
        )
      end
      
      it "calculates correct summary values" do
        stats = result.summary_stats
        expect(stats[:total_count]).to eq(3)
        expect(stats[:total_amount]).to eq(2250.0)
        expect(stats[:average_amount]).to be_within(0.01).of(750.0)
        expect(stats[:unique_merchants]).to eq(3)
        expect(stats[:unique_categories]).to eq(2) # includes nil
      end
    end
    
    context "with quick filters" do
      let(:params) { base_params.merge(include_quick_filters: true) }
      
      it "includes quick filter options" do
        expect(result.quick_filters).to include(
          :categories,
          :statuses,
          :recent_periods
        )
      end
      
      it "generates category quick filters" do
        categories = result.quick_filters[:categories]
        expect(categories).to be_an(Array)
        expect(categories.first).to include(:id, :name, :color, :count)
      end
      
      it "generates status quick filters" do
        statuses = result.quick_filters[:statuses]
        expect(statuses).to be_an(Array)
        expect(statuses.map { |s| s[:status] }).to include("processed", "pending")
      end
      
      it "generates period quick filters" do
        periods = result.quick_filters[:recent_periods]
        expect(periods).to be_an(Array)
        expect(periods.first).to include(:period, :label, :count)
      end
    end
    
    context "with view mode" do
      let(:params) { base_params.merge(view_mode: "expanded") }
      
      it "preserves view mode in result" do
        expect(result.view_mode).to eq("expanded")
      end
    end
    
    context "with combined filters" do
      let(:params) do
        base_params.merge(
          category_ids: [category1.id],
          start_date: Date.current,
          end_date: Date.current,
          min_amount: 900
        )
      end
      
      it "applies all filters correctly" do
        expect(result.expenses.count).to eq(1)
        expect(result.expenses.first).to eq(expense1)
      end
      
      it "counts all active filters" do
        expect(result.metadata[:filters_applied]).to eq(3)
      end
    end
    
    context "with period shortcuts" do
      let!(:today_expense) do
        create(:expense,
               email_account: email_account,
               transaction_date: Date.current,
               amount: 100)
      end
      
      let!(:old_expense) do
        create(:expense,
               email_account: email_account,
               transaction_date: 2.months.ago,
               amount: 200)
      end
      
      context "today filter" do
        let(:params) { base_params.merge(period: "today") }
        
        it "returns only today's expenses" do
          expect(result.expenses.map(&:transaction_date).uniq).to eq([Date.current])
        end
      end
      
      context "week filter" do
        let(:params) { base_params.merge(period: "week") }
        
        it "returns current week's expenses" do
          dates = result.expenses.map(&:transaction_date)
          expect(dates.min).to be >= Date.current.beginning_of_week
          expect(dates.max).to be <= Date.current.end_of_week
        end
      end
      
      context "month filter" do
        let(:params) { base_params.merge(period: "month") }
        
        it "returns current month's expenses" do
          dates = result.expenses.map(&:transaction_date)
          expect(dates.min).to be >= Date.current.beginning_of_month
          expect(dates.max).to be <= Date.current.end_of_month
        end
      end
    end
    
    context "error handling" do
      before do
        allow_any_instance_of(described_class).to receive(:build_dashboard_scope).and_raise(StandardError, "Test error")
      end
      
      let(:params) { base_params }
      
      it "returns error result on failure" do
        expect(result).to be_a(DashboardExpenseFilterService::DashboardResult)
        expect(result.expenses).to be_empty
        expect(result.metadata[:error]).to eq("Test error")
      end
      
      it "marks performance metrics with error flag" do
        expect(result.performance_metrics[:error]).to be true
      end
    end
  end
  
  describe "DashboardResult" do
    let(:expenses) { [expense1, expense2] }
    let(:metadata) { { filters_applied: 2, page: 1 } }
    let(:summary_stats) { { total_count: 2, total_amount: 1500 } }
    let(:quick_filters) { { categories: [] } }
    
    subject(:result) do
      DashboardExpenseFilterService::DashboardResult.new(
        expenses: expenses,
        total_count: 2,
        metadata: metadata,
        summary_stats: summary_stats,
        quick_filters: quick_filters,
        view_mode: "expanded"
      )
    end
    
    describe "#dashboard_cache_key" do
      it "generates dashboard-specific cache key" do
        expect(result.dashboard_cache_key).to include("dashboard_expense_filter")
        expect(result.dashboard_cache_key).to include("expanded")
      end
    end
    
    describe "#has_filters?" do
      it "returns true when filters are applied" do
        expect(result.has_filters?).to be true
      end
      
      context "without filters" do
        let(:metadata) { { filters_applied: 0, page: 1 } }
        
        it "returns false" do
          expect(result.has_filters?).to be false
        end
      end
    end
    
    describe "#to_json" do
      it "includes dashboard-specific fields" do
        json = JSON.parse(result.to_json)
        
        expect(json["meta"]).to include("summary_stats")
        expect(json["meta"]).to include("quick_filters")
        expect(json["meta"]).to include("view_mode")
      end
    end
  end
  
  describe "performance optimizations" do
    before do
      # Create more test data for performance testing
      create_list(:expense, 20, email_account: email_account)
    end
    
    it "uses includes to prevent N+1 queries" do
      service = described_class.new(base_params)
      
      # Warm up
      service.call
      
      # Measure queries
      query_count = 0
      ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
        query_count += 1 unless payload[:cached]
      end
      
      result = service.call
      
      ActiveSupport::Notifications.unsubscribe("sql.active_record")
      
      # Should have minimal queries even with associations
      expect(query_count).to be < 10
      
      # Access associations shouldn't trigger additional queries
      result.expenses.each do |expense|
        expense.category
        expense.email_account
      end
    end
    
    it "uses efficient aggregation queries" do
      service = described_class.new(base_params.merge(include_summary: true))
      result = service.call
      
      # Should calculate all stats in minimal queries
      expect(result.performance_metrics[:queries_executed]).to be < 10
    end
  end
end