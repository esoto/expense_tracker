# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExpenseFilterService, type: :service do
  let(:email_account) { EmailAccount.create!(provider: "gmail", email: "test@example.com", bank_name: "BAC", active: true) }
  let(:category) { Category.create!(name: "Food", color: "#FF0000") }
  
  before do
    # Create test expenses
    Expense.create!(
      email_account: email_account,
      amount: 100.00,
      transaction_date: Date.current,
      merchant_name: "Test Store",
      category: category,
      status: "processed",
      currency: "crc"
    )
    
    Expense.create!(
      email_account: email_account,
      amount: 200.00,
      transaction_date: 1.week.ago,
      merchant_name: "Another Store",
      category: nil,
      status: "pending",
      currency: "crc"
    )
    
    Expense.create!(
      email_account: email_account,
      amount: 50.00,
      transaction_date: 1.month.ago,
      merchant_name: "Old Store",
      category: category,
      status: "processed",
      currency: "crc"
    )
  end

  describe "#call" do
    context "with no filters" do
      let(:service) { described_class.new(account_ids: [email_account.id]) }
      
      it "returns all expenses" do
        result = service.call
        expect(result).to be_success
        expect(result.expenses.count).to eq(3)
        expect(result.total_count).to eq(3)
      end
      
      it "includes performance metrics" do
        result = service.call
        expect(result.performance_metrics).to include(
          :query_time_ms,
          :cached,
          :index_used,
          :queries_executed,
          :rows_examined
        )
        expect(result.performance_metrics[:query_time_ms]).to be < 50
      end
    end
    
    context "with date range filter" do
      let(:service) do
        described_class.new(
          account_ids: [email_account.id],
          start_date: 2.weeks.ago,
          end_date: Date.current
        )
      end
      
      it "filters expenses by date" do
        result = service.call
        expect(result.expenses.count).to eq(2)
        expect(result.expenses.map(&:merchant_name)).to include("Test Store", "Another Store")
      end
    end
    
    context "with category filter" do
      let(:service) do
        described_class.new(
          account_ids: [email_account.id],
          category_ids: [category.id]
        )
      end
      
      it "filters expenses by category" do
        result = service.call
        expect(result.expenses.count).to eq(2)
        expect(result.expenses.all? { |e| e.category_id == category.id }).to be true
      end
    end
    
    context "with uncategorized filter" do
      let(:service) do
        described_class.new(
          account_ids: [email_account.id],
          category_ids: ["uncategorized"]
        )
      end
      
      it "returns only uncategorized expenses" do
        result = service.call
        expect(result.expenses.count).to eq(1)
        expect(result.expenses.first.category_id).to be_nil
      end
    end
    
    context "with amount range filter" do
      let(:service) do
        described_class.new(
          account_ids: [email_account.id],
          min_amount: 75,
          max_amount: 150
        )
      end
      
      it "filters expenses by amount range" do
        result = service.call
        expect(result.expenses.count).to eq(1)
        expect(result.expenses.first.amount).to eq(100.00)
      end
    end
    
    context "with search filter" do
      let(:service) do
        described_class.new(
          account_ids: [email_account.id],
          search_query: "Test"
        )
      end
      
      it "searches expenses by merchant name" do
        result = service.call
        expect(result.expenses.count).to eq(1)
        expect(result.expenses.first.merchant_name).to eq("Test Store")
      end
    end
    
    context "with pagination" do
      let(:service) do
        described_class.new(
          account_ids: [email_account.id],
          page: 1,
          per_page: 2
        )
      end
      
      it "paginates results" do
        result = service.call
        expect(result.expenses.count).to eq(2)
        expect(result.total_count).to eq(3)
        expect(result.metadata[:page]).to eq(1)
        expect(result.metadata[:per_page]).to eq(2)
      end
    end
    
    context "with sorting" do
      let(:service) do
        described_class.new(
          account_ids: [email_account.id],
          sort_by: "amount",
          sort_direction: "asc"
        )
      end
      
      it "sorts results" do
        result = service.call
        amounts = result.expenses.map(&:amount)
        expect(amounts).to eq(amounts.sort)
      end
    end
    
    context "performance" do
      before do
        # Create more expenses for performance testing
        50.times do |i|
          Expense.create!(
            email_account: email_account,
            amount: rand(10..1000),
            transaction_date: rand(90).days.ago,
            merchant_name: "Store #{i}",
            category: [category, nil].sample,
            status: ["pending", "processed"].sample,
            currency: "crc"
          )
        end
      end
      
      it "completes complex queries within 50ms" do
        service = described_class.new(
          account_ids: [email_account.id],
          start_date: 30.days.ago,
          end_date: Date.current,
          category_ids: [category.id],
          min_amount: 50,
          max_amount: 500,
          search_query: "Store"
        )
        
        result = nil
        time = Benchmark.realtime { result = service.call }
        
        expect(time * 1000).to be < 50 # Convert to ms
        expect(result).to be_success
      end
      
      it "uses indexes for queries" do
        service = described_class.new(
          account_ids: [email_account.id],
          start_date: 30.days.ago,
          end_date: Date.current
        )
        
        result = service.call
        expect(result.performance_metrics[:index_used]).to be true
      end
    end
  end
  
  describe "#to_json" do
    let(:service) { described_class.new(account_ids: [email_account.id]) }
    
    it "returns JSON representation" do
      result = service.call
      json = JSON.parse(result.to_json)
      
      expect(json).to have_key("data")
      expect(json).to have_key("meta")
      expect(json["meta"]).to include(
        "total",
        "page",
        "per_page",
        "filters_applied",
        "sort",
        "performance"
      )
    end
  end
end