# frozen_string_literal: true

require "rails_helper"

RSpec.describe BulkOperation, type: :model, unit: true do
  # Helper method to build a stubbed instance
  def build_bulk_operation(attributes = {})
    default_attributes = {
      operation_type: :categorization,
      status: :pending,
      expense_count: 5,
      total_amount: 500.00,
      metadata: {},
      created_at: Time.current,
      updated_at: Time.current
    }
    build_stubbed(:bulk_operation, default_attributes.merge(attributes))
  end

  describe "associations" do
    it { should have_many(:bulk_operation_items).dependent(:destroy) }
    it { should have_many(:expenses).through(:bulk_operation_items) }
    it { should belong_to(:target_category).class_name("Category").optional }
  end

  describe "enums" do
    it "defines operation_type enum" do
      should define_enum_for(:operation_type).with_values(
        categorization: 0,
        recategorization: 1,
        auto_categorization: 2,
        pattern_application: 3,
        undo: 4
      )
    end

    it "defines status enum with default" do
      should define_enum_for(:status)
        .with_values(
          pending: 0,
          in_progress: 1,
          completed: 2,
          failed: 3,
          partially_completed: 4,
          undone: 5
        )
        .backed_by_column_of_type(:integer)
    end

    it "defaults to pending status" do
      operation = BulkOperation.new
      expect(operation.status).to eq("pending")
    end
  end

  describe "validations" do
    describe "operation_type" do
      it "requires operation_type" do
        operation = build_bulk_operation(operation_type: nil)
        expect(operation).not_to be_valid
        expect(operation.errors[:operation_type]).to include("can't be blank")
      end
    end

    describe "expense_count" do
      it "requires expense_count" do
        operation = build_bulk_operation(expense_count: nil)
        expect(operation).not_to be_valid
        expect(operation.errors[:expense_count]).to include("must be greater than 0")
      end

      it "requires expense_count to be greater than 0" do
        operation = build_bulk_operation(expense_count: 0)
        expect(operation).not_to be_valid
        expect(operation.errors[:expense_count]).to include("must be greater than 0")
      end

      it "accepts positive expense_count" do
        operation = build_bulk_operation(expense_count: 10)
        expect(operation).to be_valid
      end
    end

    describe "total_amount" do
      it "requires total_amount to be a number" do
        operation = BulkOperation.new(
          operation_type: :categorization,
          expense_count: 5,
          total_amount: "not_a_number"
        )
        expect(operation).not_to be_valid
        expect(operation.errors[:total_amount]).to include("is not a number")
      end

      it "accepts zero total_amount" do
        operation = build_bulk_operation(total_amount: 0)
        expect(operation).to be_valid
      end

      it "accepts positive total_amount" do
        operation = build_bulk_operation(total_amount: 1000.50)
        expect(operation).to be_valid
      end

      it "rejects negative total_amount" do
        operation = build_bulk_operation(total_amount: -100)
        expect(operation).not_to be_valid
        expect(operation.errors[:total_amount]).to include("must be greater than or equal to 0")
      end
    end
  end

  describe "scopes" do
    describe ".recent" do
      it "orders by created_at descending" do
        sql = BulkOperation.recent.to_sql
        expect(sql).to include("ORDER BY")
        expect(sql).to include("\"bulk_operations\".\"created_at\" DESC")
      end
    end

    describe ".successful" do
      it "includes completed and partially_completed statuses" do
        expect(BulkOperation.successful.to_sql).to include("status")
        expect(BulkOperation.successful.where_values_hash["status"]).to eq([ :completed, :partially_completed ])
      end
    end

    describe ".undoable" do
      it "includes correct conditions" do
        sql = BulkOperation.undoable.to_sql
        expect(sql).to include("status")
        expect(sql).to include("\"bulk_operations\".\"undone_at\" IS NULL")
        expect(sql).to include("created_at >")
      end
    end

    describe ".by_user" do
      it "filters by user_id" do
        result = BulkOperation.by_user(123)
        expect(result.where_values_hash["user_id"]).to eq(123)
      end
    end

    describe ".today" do
      it "filters by today's date" do
        expect(BulkOperation.today.to_sql).to include("created_at")
      end
    end

    describe ".this_week" do
      it "filters by this week" do
        expect(BulkOperation.this_week.to_sql).to include("created_at")
      end
    end

    describe ".this_month" do
      it "filters by this month" do
        expect(BulkOperation.this_month.to_sql).to include("created_at")
      end
    end
  end

  describe "callbacks" do
    describe "before_validation" do
      it "sets default metadata to empty hash" do
        operation = BulkOperation.new
        operation.valid?
        expect(operation.metadata).to eq({})
      end

      it "sets default expense_count to 0" do
        operation = BulkOperation.new
        operation.valid?
        expect(operation.expense_count).to eq(0)
      end

      it "sets default total_amount to 0.0" do
        operation = BulkOperation.new
        operation.valid?
        expect(operation.total_amount).to eq(0.0)
      end

      it "preserves existing values" do
        operation = BulkOperation.new(
          metadata: { "key" => "value" },
          expense_count: 10,
          total_amount: 500.00
        )
        operation.valid?
        expect(operation.metadata).to eq({ "key" => "value" })
        expect(operation.expense_count).to eq(10)
        expect(operation.total_amount).to eq(500.00)
      end
    end
  end

  describe "#undoable?" do
    context "when operation is completed" do
      let(:operation) { build_bulk_operation(status: :completed, undone_at: nil) }

      it "returns true if created within 24 hours" do
        allow(operation).to receive(:created_at).and_return(23.hours.ago)
        expect(operation.undoable?).to be true
      end

      it "returns false if created more than 24 hours ago" do
        allow(operation).to receive(:created_at).and_return(25.hours.ago)
        expect(operation.undoable?).to be false
      end

      it "returns false if already undone" do
        allow(operation).to receive(:undone_at).and_return(Time.current)
        allow(operation).to receive(:created_at).and_return(1.hour.ago)
        expect(operation.undoable?).to be false
      end
    end

    context "when operation is not completed" do
      it "returns false for pending status" do
        operation = build_bulk_operation(status: :pending, created_at: 1.hour.ago)
        expect(operation.undoable?).to be false
      end

      it "returns false for in_progress status" do
        operation = build_bulk_operation(status: :in_progress, created_at: 1.hour.ago)
        expect(operation.undoable?).to be false
      end

      it "returns false for failed status" do
        operation = build_bulk_operation(status: :failed, created_at: 1.hour.ago)
        expect(operation.undoable?).to be false
      end
    end
  end

  describe "#undo!" do
    let(:operation) { build_bulk_operation(status: :completed, id: 1, user_id: 100) }
    let(:item1) { instance_double(BulkOperationItem) }
    let(:item2) { instance_double(BulkOperationItem) }
    let(:expense1) { instance_double(Expense) }
    let(:expense2) { instance_double(Expense) }

    before do
      allow(operation).to receive(:undoable?).and_return(true)
      allow(operation).to receive(:bulk_operation_items).and_return([ item1, item2 ])
      allow(operation).to receive(:transaction).and_yield
      allow(operation).to receive(:update!).and_return(true)
      allow(BulkOperation).to receive(:create!).and_return(true)

      # Mock Current.user_id
      current_class = Class.new do
        def self.user_id
          200
        end
      end
      stub_const("Current", current_class)

      # Setup items
      allow(item1).to receive(:expense).and_return(expense1)
      allow(item1).to receive(:previous_category_id).and_return(1)
      allow(item1).to receive(:update!).and_return(true)

      allow(item2).to receive(:expense).and_return(expense2)
      allow(item2).to receive(:previous_category_id).and_return(2)
      allow(item2).to receive(:update!).and_return(true)

      # Setup expenses
      allow(expense1).to receive(:update!).and_return(true)
      allow(expense2).to receive(:update!).and_return(true)
    end

    context "when undoable" do
      it "reverts expenses to previous categories" do
        expect(expense1).to receive(:update!).with(
          category_id: 1,
          auto_categorized: false,
          categorization_confidence: nil,
          categorization_method: nil
        )
        expect(expense2).to receive(:update!).with(
          category_id: 2,
          auto_categorized: false,
          categorization_confidence: nil,
          categorization_method: nil
        )

        operation.undo!
      end

      it "marks items as undone" do
        expect(item1).to receive(:update!).with(status: "undone")
        expect(item2).to receive(:update!).with(status: "undone")

        operation.undo!
      end

      it "updates operation status and undone_at" do
        expect(operation).to receive(:update!) do |args|
          expect(args[:status]).to eq(:undone)
          expect(args[:undone_at]).to be_a(Time)
          expect(args[:metadata]).to eq({ "undone_by" => 200 })
        end

        operation.undo!
      end

      it "creates undo operation record" do
        expect(BulkOperation).to receive(:create!) do |args|
          expect(args[:operation_type]).to eq(:undo)
          expect(args[:user_id]).to eq("100")
          expect(args[:expense_count]).to eq(5)
          expect(args[:total_amount]).to eq(500.00)
          expect(args[:metadata]).to include(original_operation_id: 1)
          expect(args[:metadata]).to have_key(:undone_at)
        end

        operation.undo!
      end

      it "returns true on success" do
        expect(operation.undo!).to be true
      end
    end

    context "when not undoable" do
      before do
        allow(operation).to receive(:undoable?).and_return(false)
      end

      it "returns false without making changes" do
        expect(expense1).not_to receive(:update!)
        expect(operation).not_to receive(:update!)
        expect(BulkOperation).not_to receive(:create!)

        expect(operation.undo!).to be false
      end
    end

    context "when error occurs" do
      before do
        allow(expense1).to receive(:update!).and_raise(StandardError, "Database error")
        allow(Rails.logger).to receive(:error)
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/Failed to undo bulk operation 1: Database error/)
        operation.undo!
      end

      it "returns false" do
        expect(operation.undo!).to be false
      end
    end
  end

  describe "#success_rate" do
    let(:operation) { build_bulk_operation(expense_count: 10) }

    before do
      items = double("items")
      allow(operation).to receive(:bulk_operation_items).and_return(items)
      allow(items).to receive(:where).with(status: "completed").and_return(items)
      allow(items).to receive(:count).and_return(7)
    end

    it "calculates percentage of successful items" do
      expect(operation.success_rate).to eq(70.0)
    end

    context "with zero expense_count" do
      let(:operation) { build_bulk_operation(expense_count: 0) }

      it "returns 0.0" do
        expect(operation.success_rate).to eq(0.0)
      end
    end

    context "with all items successful" do
      before do
        items = double("items")
        allow(operation).to receive(:bulk_operation_items).and_return(items)
        allow(items).to receive(:where).with(status: "completed").and_return(items)
        allow(items).to receive(:count).and_return(10)
      end

      it "returns 100.0" do
        expect(operation.success_rate).to eq(100.0)
      end
    end
  end

  describe "#duration_seconds" do
    let(:operation) { build_bulk_operation }

    context "when completed_at is present" do
      it "calculates duration in seconds" do
        allow(operation).to receive(:created_at).and_return(Time.parse("2024-01-01 10:00:00"))
        allow(operation).to receive(:completed_at).and_return(Time.parse("2024-01-01 10:05:30"))

        expect(operation.duration_seconds).to eq(330)
      end
    end

    context "when completed_at is nil" do
      it "returns nil" do
        allow(operation).to receive(:completed_at).and_return(nil)
        expect(operation.duration_seconds).to be_nil
      end
    end
  end

  describe "#average_confidence" do
    let(:operation) { build_bulk_operation }

    context "with confidence values" do
      before do
        items = double("items")
        joined_items = double("joined_items")
        where_chain = double("where_chain")
        final_chain = double("final_chain")

        allow(operation).to receive(:bulk_operation_items).and_return(items)
        allow(items).to receive(:joins).with(:expense).and_return(joined_items)
        allow(joined_items).to receive(:where).and_return(where_chain)
        allow(where_chain).to receive(:not).with(expenses: { categorization_confidence: nil }).and_return(final_chain)
        allow(final_chain).to receive(:pluck).with("expenses.categorization_confidence").and_return([ 0.8, 0.9, 0.7 ])
      end

      it "calculates average confidence" do
        expect(operation.average_confidence).to eq(0.8)
      end
    end

    context "with no confidence values" do
      before do
        items = double("items")
        joined_items = double("joined_items")
        where_chain = double("where_chain")
        final_chain = double("final_chain")

        allow(operation).to receive(:bulk_operation_items).and_return(items)
        allow(items).to receive(:joins).with(:expense).and_return(joined_items)
        allow(joined_items).to receive(:where).and_return(where_chain)
        allow(where_chain).to receive(:not).with(expenses: { categorization_confidence: nil }).and_return(final_chain)
        allow(final_chain).to receive(:pluck).with("expenses.categorization_confidence").and_return([])
      end

      it "returns nil" do
        expect(operation.average_confidence).to be_nil
      end
    end
  end

  describe "#affected_categories" do
    let(:operation) { build_bulk_operation }

    before do
      allow(operation).to receive(:expense_ids).and_return([ 1, 2, 3 ])
      categories = double("categories")
      allow(Category).to receive(:joins).with(:expenses).and_return(categories)
      allow(categories).to receive(:where).with(expenses: { id: [ 1, 2, 3 ] }).and_return(categories)
      allow(categories).to receive(:distinct).and_return("distinct_categories")
    end

    it "returns distinct categories for affected expenses" do
      expect(operation.affected_categories).to eq("distinct_categories")
    end
  end

  describe "#expense_ids" do
    let(:operation) { build_bulk_operation }

    context "when metadata contains expense_ids" do
      before do
        allow(operation).to receive(:metadata).and_return({ "expense_ids" => [ 1, 2, 3 ] })
      end

      it "returns expense_ids from metadata" do
        expect(operation.expense_ids).to eq([ 1, 2, 3 ])
      end
    end

    context "when metadata does not contain expense_ids" do
      before do
        allow(operation).to receive(:metadata).and_return({})
        items = double("items")
        allow(operation).to receive(:bulk_operation_items).and_return(items)
        allow(items).to receive(:pluck).with(:expense_id).and_return([ 4, 5, 6 ])
      end

      it "returns expense_ids from bulk_operation_items" do
        expect(operation.expense_ids).to eq([ 4, 5, 6 ])
      end
    end
  end

  describe "#summary" do
    let(:operation) do
      build_bulk_operation(
        operation_type: :categorization,
        status: :completed,
        expense_count: 10,
        total_amount: 1000.00,
        created_at: Time.parse("2024-01-01 10:00:00")
      )
    end
    let(:category) { build_stubbed(:category, name: "Travel") }

    before do
      allow(operation).to receive(:target_category).and_return(category)
      allow(operation).to receive(:success_rate).and_return(90.0)
      allow(operation).to receive(:duration_seconds).and_return(120)
      allow(operation).to receive(:average_confidence).and_return(0.85)
      allow(operation).to receive(:undoable?).and_return(true)
    end

    it "returns comprehensive summary hash" do
      summary = operation.summary

      expect(summary).to include(
        operation: "Categorization",
        status: "Completed",
        expenses_affected: 10,
        total_amount: 1000.00,
        target_category: "Travel",
        success_rate: 90.0,
        duration: 120,
        average_confidence: 0.85,
        created_at: Time.parse("2024-01-01 10:00:00"),
        undoable: true
      )
    end

    context "without target category" do
      before do
        allow(operation).to receive(:target_category).and_return(nil)
      end

      it "includes nil for target_category" do
        expect(operation.summary[:target_category]).to be_nil
      end
    end
  end

  describe "edge cases and security" do
    describe "metadata handling" do
      it "handles complex metadata structures" do
        metadata = {
          "user_id" => 123,
          "source" => "api",
          "filters" => { "date_range" => "2024-01", "merchant" => "Amazon" },
          "expense_ids" => [ 1, 2, 3 ]
        }
        operation = build_bulk_operation(metadata: metadata)
        expect(operation.metadata).to eq(metadata)
      end
    end

    describe "concurrent operations" do
      it "handles concurrent undo attempts" do
        operation = build_bulk_operation(status: :completed, id: 1)
        allow(operation).to receive(:undoable?).and_return(true, false)
        allow(operation).to receive(:transaction).and_yield

        # First call succeeds
        expect(operation.undo!).to be false # Second check returns false
      end
    end

    describe "large-scale operations" do
      it "handles operations with many expenses" do
        operation = build_bulk_operation(expense_count: 10000, total_amount: 1_000_000.00)
        expect(operation).to be_valid
      end
    end
  end
end
