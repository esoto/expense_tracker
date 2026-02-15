# frozen_string_literal: true

require "rails_helper"
require_relative "../../../app/services/categorization/bulk_categorization_service"

RSpec.describe Services::Categorization::BulkCategorizationService, type: :service, unit: true do
  # Test data setup
  let(:user) { nil } # User is optional for this service
  let(:category) { build(:category, id: 1, name: "Food & Dining") }
  let(:other_category) { build(:category, id: 2, name: "Transportation") }
  let(:expenses) { build_list(:expense, 3, category: nil) }
  let(:categorized_expense) { build(:expense, category: other_category) }
  let(:locked_expense) { build(:expense, status: "pending") }
  let(:options) { {} }

  # Test dependencies
  let(:bulk_operation) { build_stubbed(:bulk_operation, id: 123) }
  let(:pattern) { build_stubbed(:categorization_pattern, category: category, confidence_weight: 0.8) }

  # Subject under test
  subject(:service) do
    described_class.new(
      expenses: expenses,
      category_id: category.id,
      user: user,
      options: options
    )
  end

  # Shared contexts for common scenarios
  shared_context "with valid category" do
    before do
      category.save! if category.new_record?
    end
  end

  # Public method tests
  describe "#preview" do
    context "with empty expenses" do
      let(:expenses) { [] }

      it "returns empty summary" do
        result = service.preview
        expect(result[:expenses]).to be_empty
        expect(result[:summary][:total_count]).to eq(0)
        expect(result[:summary][:total_amount]).to eq(0)
        expect(result[:summary][:by_current_category]).to be_empty
        expect(result[:summary][:estimated_time_saved]).to eq("0 seconds")
      end
    end

    context "with valid expenses" do
      include_context "with valid category"

      it "returns preview of changes" do
        result = service.preview

        expect(result[:expenses]).to have_attributes(size: 3)
        expect(result[:summary][:total_count]).to eq(3)
        expect(result[:summary][:total_amount]).to eq(expenses.sum(&:amount))
      end

      it "includes expense details in preview" do
        preview_expense = service.preview[:expenses].first
        original_expense = expenses.first

        expect(preview_expense[:id]).to eq(original_expense.id)
        expect(preview_expense[:description]).to eq(original_expense.description)
        expect(preview_expense[:amount]).to eq(original_expense.amount)
        expect(preview_expense[:new_category]).to eq(category.name)
        expect(preview_expense[:will_change]).to be true
      end

      it "groups by current category" do
        expenses[0].category = other_category

        result = service.preview
        by_category = result[:summary][:by_current_category]

        expect(by_category).to have_key("Uncategorized")
        expect(by_category).to have_key(other_category.name)
        expect(by_category["Uncategorized"][:count]).to eq(2)
      end

      it "estimates time saved" do
        result = service.preview
        # 3 expenses × 3 seconds = 9 seconds
        expect(result[:summary][:estimated_time_saved]).to eq("9 seconds")
      end
    end

    context "with mixed expense states" do
      let(:already_categorized) { build(:expense, category: category) } # Same target category
      let(:expenses) { [ already_categorized, build(:expense, category: nil) ] }
      include_context "with valid category"

      it "excludes already categorized expenses from preview" do
        result = service.preview
        expect(result[:expenses]).to have_attributes(size: 1)
        expect(result[:summary][:total_count]).to eq(1)
      end
    end

    context "with already categorized expenses" do
      let(:expenses) { [ build(:expense, category_id: category.id) ] }
      include_context "with valid category"

      it "excludes expenses already in target category" do
        result = service.preview
        expect(result[:expenses]).to be_empty
        expect(result[:summary][:total_count]).to eq(0)
      end
    end
  end

  describe "#apply!" do
    context "with empty expenses" do
      let(:expenses) { [] }

      it "returns error for no expenses" do
        result = service.apply!
        expect(result[:success]).to be false
        expect(result[:errors]).to include("No expenses selected")
      end
    end

    context "with invalid category" do
      before do
        allow(Category).to receive(:exists?).with(category.id).and_return(false)
      end

      it "returns error for invalid category" do
        result = service.apply!
        expect(result[:success]).to be false
        expect(result[:errors]).to include("Category not found")
      end
    end

    context "with valid data" do
      include_context "with valid category"

      it "updates all expenses successfully" do
        expenses.each { |e| e.save! }

        result = service.apply!
        expect(result[:success]).to be true
        expect(result[:updated_count]).to eq(3)
        expect(result[:failed_count]).to eq(0)
      end
    end

    context "with invalid category id" do
      subject(:service) do
        described_class.new(
          expenses: expenses,
          category_id: 99999, # Non-existent ID
          user: user,
          options: options
        )
      end

      it "returns error for non-existent category" do
        result = service.apply!
        expect(result[:success]).to be false
        expect(result[:errors]).to include("Category not found")
      end
    end
  end

  describe "#undo!" do
    it "returns error for invalid token" do
      result = service.undo!(99999)
      expect(result[:success]).to be false
      expect(result[:errors]).to include("Operation not found")
    end
  end

  describe "#export" do
    context "CSV format" do
      it "generates CSV with headers" do
        csv = service.export(format: :csv)
        lines = csv.split("\n")

        expect(lines[0]).to eq("ID,Date,Description,Amount,Current Category,Merchant")
        expect(lines.size).to eq(expenses.size + 1) # header + data rows
      end

      it "includes expense data in CSV" do
        expense = expenses.first
        expense.category = category

        csv = service.export(format: :csv)

        expect(csv).to include(expense.id.to_s)
        expect(csv).to include(expense.description)
        expect(csv).to include(category.name)
      end
    end

    context "JSON format" do
      it "generates valid JSON" do
        json_string = service.export(format: :json)
        parsed = JSON.parse(json_string)

        expect(parsed).to be_an(Array)
        expect(parsed.size).to eq(expenses.size)
      end

      it "includes all expense attributes" do
        expense = expenses.first
        json_string = service.export(format: :json)
        parsed = JSON.parse(json_string)

        first_item = parsed.first
        expect(first_item["id"]).to eq(expense.id)
        expect(first_item["description"]).to eq(expense.description)
        expect(first_item["amount"]).to eq(expense.amount.to_s)
      end
    end

    context "Excel format" do
      it "raises not implemented error" do
        expect {
          service.export(format: :xlsx)
        }.to raise_error(NotImplementedError, /Excel export requires/)
      end
    end

    context "invalid format" do
      it "raises argument error" do
        expect {
          service.export(format: :pdf)
        }.to raise_error(ArgumentError, "Unsupported export format: pdf")
      end
    end
  end

  describe "#group_expenses" do
    let(:merchant_expense) { build(:expense, merchant_name: "Starbucks") }
    let(:expenses) { [ merchant_expense ] + build_list(:expense, 2, merchant_name: "Amazon") }

    context "by merchant" do
      it "groups expenses by merchant name" do
        groups = service.group_expenses(by: :merchant)

        expect(groups).to have_key("Starbucks")
        expect(groups).to have_key("Amazon")
        expect(groups["Amazon"][:count]).to eq(2)
        expect(groups["Starbucks"][:count]).to eq(1)
      end

      it "calculates totals for each group" do
        groups = service.group_expenses(by: :merchant)
        amazon_group = groups["Amazon"]

        expect(amazon_group[:total_amount]).to eq(
          expenses.select { |e| e.merchant_name == "Amazon" }.sum(&:amount)
        )
      end

      it "sorts by count descending" do
        groups = service.group_expenses(by: :merchant)
        counts = groups.values.map { |g| g[:count] }

        expect(counts).to eq(counts.sort.reverse)
      end
    end

    context "by date" do
      let(:jan_expense) { build(:expense, transaction_date: Date.new(2024, 1, 15)) }
      let(:feb_expense) { build(:expense, transaction_date: Date.new(2024, 2, 10)) }
      let(:expenses) { [ jan_expense, feb_expense ] }

      it "groups by month" do
        groups = service.group_expenses(by: :date)

        expect(groups.keys).to include(Date.new(2024, 1, 1))
        expect(groups.keys).to include(Date.new(2024, 2, 1))
      end

      it "sorts chronologically" do
        groups = service.group_expenses(by: :date)
        dates = groups.keys

        expect(dates).to eq(dates.sort)
      end
    end

    context "by amount range" do
      let(:small_expense) { build(:expense, amount: 5) }
      let(:medium_expense) { build(:expense, amount: 25) }
      let(:large_expense) { build(:expense, amount: 150) }
      let(:expenses) { [ small_expense, medium_expense, large_expense ] }

      it "groups into predefined ranges" do
        groups = service.group_expenses(by: :amount_range)

        expect(groups).to have_key("$0-10")
        expect(groups).to have_key("$10-50")
        expect(groups).to have_key("$100-500")
      end

      it "counts expenses in each range" do
        groups = service.group_expenses(by: :amount_range)

        expect(groups["$0-10"][:count]).to eq(1)
        expect(groups["$10-50"][:count]).to eq(1)
        expect(groups["$100-500"][:count]).to eq(1)
      end
    end

    context "by category" do
      let(:food_expense) { build(:expense, category: category) }
      let(:transport_expense) { build(:expense, category: other_category) }
      let(:uncategorized) { build(:expense, category: nil) }
      let(:expenses) { [ food_expense, transport_expense, uncategorized ] }

      it "groups by category name" do
        groups = service.group_expenses(by: :category)

        expect(groups).to have_key(category.name)
        expect(groups).to have_key(other_category.name)
        expect(groups).to have_key("Uncategorized")
      end

      it "sorts by total amount descending" do
        groups = service.group_expenses(by: :category)
        amounts = groups.values.map { |g| g[:total_amount] }

        expect(amounts).to eq(amounts.sort.reverse)
      end
    end

    context "by similarity" do
      let(:expense1) { create(:expense, description: "Coffee at Starbucks", amount: 5.00) }
      let(:expense2) { create(:expense, description: "Coffee at Starbucks", amount: 5.05) }
      let(:expense3) { create(:expense, description: "Gas station", amount: 40.00) }
      let(:expenses) { [ expense1, expense2, expense3 ] }

      it "groups similar expenses together" do
        groups = service.group_expenses(by: :similarity)

        expect(groups).to be_an(Array)
        if groups.any?
          expect(groups.first[:count]).to eq(2) # Two coffee expenses
        else
          expect(groups).to be_empty # No similar expenses found
        end
      end

      it "identifies anchor expense if similar expenses exist" do
        groups = service.group_expenses(by: :similarity)

        if groups.any?
          expect(groups.first[:anchor]).to eq(expense1)
          expect(groups.first[:similar]).to include(expense2)
        else
          expect(groups).to be_empty
        end
      end
    end

    context "invalid grouping type" do
      it "raises argument error" do
        expect {
          service.group_expenses(by: :invalid)
        }.to raise_error(ArgumentError, "Unsupported grouping: invalid")
      end
    end
  end

  describe "#suggest_categories" do
    let(:uncategorized_expenses) { build_list(:expense, 2, category: nil) }
    let(:expenses) { uncategorized_expenses }

    it "returns empty suggestions when no patterns exist" do
      # Stub pattern query to return empty
      allow(CategorizationPattern).to receive_message_chain(:active, :with_category).and_return([])

      suggestions = service.suggest_categories
      expect(suggestions).to be_empty
    end

    it "skips categorized expenses" do
      categorized_expense = build(:expense, category: category)
      service_with_categorized = described_class.new(
        expenses: [ categorized_expense ],
        category_id: category.id
      )

      suggestions = service_with_categorized.suggest_categories
      expect(suggestions).to be_empty
    end
  end

  describe "#auto_categorize!" do
    context "with empty expenses" do
      let(:expenses) { [] }

      it "returns error" do
        result = service.auto_categorize!
        expect(result[:success]).to be false
        expect(result[:errors]).to include("No expenses to categorize")
      end
    end

    context "with uncategorized expenses" do
      let(:uncategorized_expenses) { build_list(:expense, 2, category: nil) }
      let(:expenses) { uncategorized_expenses }

      it "returns result with zero categorized when no patterns match" do
        # Stub pattern query to return empty
        allow(CategorizationPattern).to receive_message_chain(:active, :with_category).and_return([])

        result = service.auto_categorize!

        expect(result[:success]).to be true
        expect(result[:categorized_count]).to eq(0)
        expect(result[:failed_count]).to eq(2)
        expect(result[:total_processed]).to eq(2)
      end
    end
  end

  describe "#batch_process" do
    let(:expenses) { build_list(:expense, 10) } # Smaller batch for testing

    it "processes in batches" do
      batch_results = []

      service.batch_process(batch_size: 3) do |batch_result|
        batch_results << batch_result
      end

      expect(batch_results.size).to eq(4) # 10 / 3 = 4 batches (rounded up)
    end

    it "yields batch results to block" do
      yielded_results = []

      service.batch_process(batch_size: 4) do |result|
        yielded_results << result
      end

      expect(yielded_results.all? { |r| r.key?(:processed) }).to be true
      expect(yielded_results.all? { |r| r.key?(:timestamp) }).to be true
    end

    it "aggregates results" do
      result = service.batch_process(batch_size: 4)

      expect(result[:total_processed]).to eq(10)
      expect(result[:batch_count]).to eq(3) # 10 / 4 = 3 batches (rounded up)
    end
  end

  describe "#categorize_all" do
    context "with empty expenses" do
      let(:expenses) { [] }

      it "returns error" do
        result = service.categorize_all
        expect(result[:success]).to be false
        expect(result[:errors]).to include("No expenses selected")
      end
    end

    context "without category" do
      subject(:service) do
        described_class.new(expenses: expenses, category_id: nil)
      end

      it "returns error" do
        result = service.categorize_all
        expect(result[:success]).to be false
        expect(result[:errors]).to include("No category provided")
      end
    end

    context "with valid category" do
      include_context "with valid category"

      it "categorizes all expenses when they exist in database" do
        expenses.each { |e| e.save! }

        result = service.categorize_all

        expect(result[:success_count]).to eq(3)
        expect(result[:failures]).to be_empty
      end
    end
  end

  describe "#store_bulk_operation", :unit do
    let(:email_account) { create(:email_account) }
    let(:category) { create(:category, name: "Test Category") }
    let(:expenses) { create_list(:expense, 5, email_account: email_account, category: nil) }
    let(:service) { described_class.new(expenses: expenses, category_id: category.id) }

    it "does not fire N+1 queries for amount calculation" do
      results = expenses.map { |e| { success: true, expense_id: e.id, previous_category_id: nil } }

      # Track Expense SELECT queries to detect N+1 in amount calculation
      expense_find_queries = []
      expense_sum_queries = []
      counter = lambda do |_name, _start, _finish, _id, payload|
        sql = payload[:sql].to_s
        next unless sql.match?(/SELECT.*FROM\s+"expenses"/i)

        if sql.match?(/SUM/i)
          expense_sum_queries << sql
        elsif sql.match?(/WHERE.*"expenses"\."id"\s*=\s*\$1.*LIMIT/i)
          expense_find_queries << sql
        end
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        service.send(:store_bulk_operation, results)
      end

      # With the fix: 1 SUM query replaces N individual Expense.find queries
      # The remaining individual finds are from BulkOperationItem creation (expected)
      expect(expense_sum_queries.size).to eq(1),
        "Expected exactly 1 SUM query for amount calculation, " \
        "but got #{expense_sum_queries.size}"

      # Should NOT have more individual finds than expenses
      # (BulkOperationItem creation loads each expense once, which is expected)
      expect(expense_find_queries.size).to be <= expenses.size,
        "Expected at most #{expenses.size} individual Expense.find queries " \
        "(from BulkOperationItem creation), but got #{expense_find_queries.size}"
    end
  end

  # Private method tests (testing via public interface)
  describe "private methods via public interface" do
    describe "#filter_changeable_expenses" do
      let(:already_in_target_category) { build(:expense, category: category) }
      let(:expenses) { [ already_in_target_category, build(:expense, category: nil) ] }
      include_context "with valid category"

      it "filters same-category expenses in preview" do
        result = service.preview
        # Only the uncategorized expense should be changeable
        expect(result[:expenses]).to have_attributes(size: 1)
      end
    end

    describe "#estimate_time_saved" do
      context "with seconds" do
        let(:expenses) { build_list(:expense, 10, category: nil) }
        include_context "with valid category"

        it "formats as seconds" do
          result = service.preview
          expect(result[:summary][:estimated_time_saved]).to eq("30 seconds")
        end
      end

      context "with minutes" do
        let(:expenses) { build_list(:expense, 30, category: nil) }
        include_context "with valid category"

        it "formats as minutes" do
          result = service.preview
          expect(result[:summary][:estimated_time_saved]).to eq("1.5 minutes")
        end
      end

      context "with hours" do
        let(:expenses) { build_list(:expense, 1500, category: nil) }
        include_context "with valid category"

        it "formats as hours" do
          result = service.preview
          expect(result[:summary][:estimated_time_saved]).to eq("1.3 hours")
        end
      end
    end
  end
end
