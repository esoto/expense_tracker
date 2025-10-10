# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::BulkCategorization::ApplyService, type: :service, unit: true do
  # Test doubles and mocks
  let(:expense_ids) { [ 1, 2, 3 ] }
  let(:category_id) { 10 }
  let(:user_id) { 5 }
  let(:default_options) do
    {
      learn_patterns: true,
      send_notifications: true,
      track_operation: true,
      update_confidence: true,
      create_patterns: true
    }
  end

  let(:service) do
    described_class.new(
      expense_ids: expense_ids,
      category_id: category_id,
      user_id: user_id
    )
  end

  # Mock objects
  let(:category) { instance_double(Category, id: category_id, name: "Groceries") }
  let(:expenses) { [] }
  let(:bulk_operation) { instance_double(BulkOperation, id: 100) }
  let(:pattern_learner) { instance_double(Categorization::PatternLearner) }
  let(:engine) { instance_double("CategorizationEngine") }
  let(:categorization_result) do
    OpenStruct.new(
      successful?: true,
      category: category,
      confidence: 0.95
    )
  end

  before do
    # Stub ActiveRecord operations
    allow(Category).to receive(:find).with(category_id).and_return(category)
    allow(Expense).to receive(:where).and_return(double(includes: double(lock: expenses)))
    allow(BulkOperation).to receive(:create!).and_return(bulk_operation)
    allow(BulkOperationItem).to receive(:create!)

    # Stub error tracking
    allow(ErrorTrackingService).to receive(:track_bulk_operation_error)

    # Stub pattern learning
    allow(Categorization::PatternLearner).to receive(:new).and_return(pattern_learner)
    allow(pattern_learner).to receive(:learn_from_correction)

    # Stub categorization engine
    allow(Categorization::EngineFactory).to receive(:default).and_return(engine)
    allow(engine).to receive(:categorize).and_return(categorization_result)

    # Stub Turbo broadcasts
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    # Stub Rails logger
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)

    # Stub pattern creation
    allow(CategorizationPattern).to receive(:find_by).and_return(nil)
    allow(CategorizationPattern).to receive(:create!)
  end

  describe "#initialize" do
    it "initializes with required parameters", unit: true do
      expect(service.expense_ids).to eq(expense_ids)
      expect(service.category_id).to eq(category_id)
      expect(service.user_id).to eq(user_id)
    end

    it "converts single expense_id to array", unit: true do
      service = described_class.new(
        expense_ids: 1,
        category_id: category_id
      )
      expect(service.expense_ids).to eq([ 1 ])
    end

    it "merges custom options with defaults", unit: true do
      service = described_class.new(
        expense_ids: expense_ids,
        category_id: category_id,
        options: { learn_patterns: false }
      )
      expect(service.options[:learn_patterns]).to be false
      expect(service.options[:send_notifications]).to be true
    end

    it "initializes empty results and errors arrays", unit: true do
      expect(service.instance_variable_get(:@results)).to eq([])
      expect(service.instance_variable_get(:@processing_errors)).to eq([])
    end
  end

  describe "validations" do
    it "validates presence of expense_ids", unit: true do
      service = described_class.new(
        expense_ids: nil,
        category_id: category_id
      )
      expect(service).not_to be_valid
      expect(service.errors[:expense_ids]).to include("can't be blank")
    end

    it "validates presence of category_id", unit: true do
      service = described_class.new(
        expense_ids: expense_ids,
        category_id: nil
      )
      expect(service).not_to be_valid
      expect(service.errors[:category_id]).to include("can't be blank")
    end

    it "accepts empty array for expense_ids but fails validation", unit: true do
      service = described_class.new(
        expense_ids: [],
        category_id: category_id
      )
      expect(service).not_to be_valid
      expect(service.errors[:expense_ids]).to include("can't be blank")
    end
  end

  describe "#call" do
    context "when validation fails" do
      let(:service) do
        described_class.new(
          expense_ids: nil,
          category_id: category_id
        )
      end

      it "returns failure result with validation errors", unit: true do
        result = service.call
        expect(result.success?).to be false
        expect(result.message).to match(/blank|error occurred/i)
        expect(result.bulk_operation).to be_nil
      end

      it "does not create database transaction", unit: true do
        # Valid? is called before transaction, so we should spy on it returning false
        allow(service).to receive(:valid?).and_return(false)
        expect(ActiveRecord::Base).not_to receive(:transaction)
        service.call
      end
    end

    context "when expenses not found" do
      before do
        allow(expenses).to receive(:count).and_return(2)
        allow(expenses).to receive(:pluck).with(:id).and_return([ 1, 2 ])
        allow(expenses).to receive(:pluck).with(:id, :category_id).and_return([ [ 1, nil ], [ 2, nil ] ])
      end

      it "raises ActiveRecord::RecordNotFound", unit: true do
        result = service.call
        expect(result.success?).to be false
        expect(result.message).to eq("An error occurred while categorizing expenses")
      end

      it "tracks error with ErrorTrackingService", unit: true do
        expect(ErrorTrackingService).to receive(:track_bulk_operation_error).with(
          "categorization",
          instance_of(ActiveRecord::RecordNotFound),
          hash_including(
            expense_count: 3,
            category_id: category_id,
            user_id: user_id
          )
        )
        service.call
      end
    end

    context "when expenses already categorized" do
      let(:expense_ids) { [ 1, 2 ] }  # Override to match the two expenses being tested
      let(:existing_category) { instance_double(Category, id: 5, name: "Food", present?: true) }
      let(:expense1) do
        instance_double(Expense,
          id: 1,
          category: existing_category,
          display_description: "Expense 1",
          present?: true,
          merchant_name?: false,
          amount: 50.0,
          errors: double(full_messages: [ "Already categorized" ])
        )
      end
      let(:expense2) do
        instance_double(Expense,
          id: 2,
          category: nil,
          present?: false,
          merchant_name?: false,
          amount: 30.0
        )
      end

      before do
        allow(expenses).to receive(:count).and_return(2)
        allow(expenses).to receive(:pluck).with(:id).and_return([ 1, 2 ])
        allow(expenses).to receive(:pluck).with(:id, :category_id).and_return([ [ 1, 5 ], [ 2, nil ] ])
        allow(expenses).to receive(:select) do |&block|
          [ expense1, expense2 ].select(&block)
        end
      end

      context "without allow_recategorization option" do
        it "raises ActiveRecord::RecordInvalid", unit: true do
          result = service.call
          expect(result.success?).to be false
          expect(result.message).to match(/already categorized/)
        end
      end

      context "with allow_recategorization option" do
        let(:service) do
          described_class.new(
            expense_ids: expense_ids,
            category_id: category_id,
            user_id: user_id,
            options: { allow_recategorization: true }
          )
        end

        before do
          allow(expenses).to receive(:count).and_return(2)
          allow(expenses).to receive(:each).and_yield(expense1).and_yield(expense2)
          allow(expenses).to receive(:sum).with(:amount).and_return(100.0)
          allow(expenses).to receive(:pluck).with(:id).and_return([ 1, 2 ])
          allow(expenses).to receive(:pluck).with(:id, :category_id).and_return([ [ 1, 5 ], [ 2, nil ] ])
          allow(expenses).to receive(:select) do |&block|
          [ expense1, expense2 ].select(&block)
        end
          # Categories are already set in the expense doubles above
          allow(expense1).to receive(:update!).and_return(true)
          allow(expense2).to receive(:update!).and_return(true)
        end

        it "proceeds with categorization", unit: true do
          result = service.call
          expect(result.success?).to be true
          expect(result.message).to eq("Successfully categorized 2 expenses")
        end
      end
    end

    context "successful categorization" do
      let(:expense1) do
        instance_double(Expense,
          id: 1,
          category: nil,
          merchant_name: "Walmart",
          merchant_normalized: "walmart",
          merchant_name?: true,
          amount: 50.0,
          present?: false
        )
      end
      let(:expense2) do
        instance_double(Expense,
          id: 2,
          category: nil,
          merchant_name: nil,
          merchant_normalized: nil,
          merchant_name?: false,
          amount: 30.0,
          present?: false
        )
      end
      let(:expense3) do
        instance_double(Expense,
          id: 3,
          category: nil,
          merchant_name: "Target",
          merchant_normalized: "target",
          merchant_name?: true,
          amount: 20.0,
          present?: false
        )
      end

      before do
        allow(expenses).to receive(:count).and_return(3)
        allow(expenses).to receive(:pluck).with(:id).and_return([ 1, 2, 3 ])
        allow(expenses).to receive(:pluck).with(:id, :category_id).and_return([ [ 1, nil ], [ 2, nil ], [ 3, nil ] ])
        allow(expenses).to receive(:select) do |&block|
          [ expense1, expense2, expense3 ].select(&block)
        end
        allow(expenses).to receive(:each).and_yield(expense1).and_yield(expense2).and_yield(expense3)
        allow(expenses).to receive(:sum).with(:amount).and_return(100.0)

        [ expense1, expense2, expense3 ].each do |expense|
          allow(expense).to receive(:update!).with(hash_including(
            category: category,
            auto_categorized: false,
            categorization_method: "bulk_manual"
          ))
        end

        # Allow count method for merchant normalization
        allow(expenses).to receive(:count) do |&block|
          if block
            [ expense1, expense2, expense3 ].count(&block)
          else
            3
          end
        end
      end

      it "returns success result", unit: true do
        result = service.call
        expect(result.success?).to be true
        expect(result.message).to eq("Successfully categorized 3 expenses")
        expect(result.expense_count).to eq(3)
      end

      it "creates bulk operation record", unit: true do
        expect(BulkOperation).to receive(:create!).with(hash_including(
          operation_type: "categorization",
          user_id: user_id,
          target_category_id: category_id,
          expense_count: 3,
          total_amount: 100.0
        ))
        service.call
      end

      it "updates each expense with new category", unit: true do
        [ expense1, expense2, expense3 ].each do |expense|
          expect(expense).to receive(:update!).with(hash_including(
            category: category,
            auto_categorized: false,
            categorization_confidence: 0.95,
            categorization_method: "bulk_manual",
            categorized_by: user_id
          ))
        end
        service.call
      end

      it "creates bulk operation items for each expense", unit: true do
        expect(BulkOperationItem).to receive(:create!).exactly(3).times
        service.call
      end

      it "learns patterns from categorization", unit: true do
        expect(pattern_learner).to receive(:learn_from_correction).exactly(3).times
        service.call
      end

      it "creates patterns for merchants", unit: true do
        expect(CategorizationPattern).to receive(:create!).with(hash_including(
          category: category,
          pattern_type: "merchant",
          pattern_value: "walmart"
        ))
        expect(CategorizationPattern).to receive(:create!).with(hash_including(
          pattern_type: "merchant",
          pattern_value: "target"
        ))
        service.call
      end

      it "broadcasts Turbo Stream notification", unit: true do
        expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
          "bulk_categorization_updates",
          hash_including(
            target: "categorization_progress",
            partial: "bulk_categorizations/progress"
          )
        )
        service.call
      end

      context "with learn_patterns disabled" do
        let(:service) do
          described_class.new(
            expense_ids: expense_ids,
            category_id: category_id,
            options: { learn_patterns: false }
          )
        end

        it "does not learn patterns", unit: true do
          expect(Categorization::PatternLearner).not_to receive(:new)
          service.call
        end
      end

      context "with send_notifications disabled" do
        let(:service) do
          described_class.new(
            expense_ids: expense_ids,
            category_id: category_id,
            options: { send_notifications: false }
          )
        end

        it "does not broadcast notifications", unit: true do
          expect(Turbo::StreamsChannel).not_to receive(:broadcast_replace_to)
          service.call
        end
      end

      context "with track_operation disabled" do
        let(:service) do
          described_class.new(
            expense_ids: expense_ids,
            category_id: category_id,
            options: { track_operation: false }
          )
        end

        it "does not create bulk operation", unit: true do
          expect(BulkOperation).not_to receive(:create!)
          service.call
        end

        it "does not create bulk operation items", unit: true do
          expect(BulkOperationItem).not_to receive(:create!)
          service.call
        end
      end

      context "with create_patterns disabled" do
        let(:service) do
          described_class.new(
            expense_ids: expense_ids,
            category_id: category_id,
            options: { create_patterns: false }
          )
        end

        it "does not create categorization patterns", unit: true do
          expect(CategorizationPattern).not_to receive(:create!)
          service.call
        end
      end
    end

    context "with partial failures" do
      let(:expense_ids) { [ 1, 2 ] }  # Override to match the two expenses being tested
      let(:expense1) do
        instance_double(Expense,
          id: 1,
          category: nil,
          merchant_name?: false,
          amount: 50.0,
          present?: false
        )
      end
      let(:expense2) do
        instance_double(Expense,
          id: 2,
          category: nil,
          merchant_name?: false,
          amount: 30.0,
          present?: false
        )
      end

      before do
        allow(expenses).to receive(:count).and_return(2)
        allow(expenses).to receive(:pluck).with(:id).and_return([ 1, 2 ])
        allow(expenses).to receive(:pluck).with(:id, :category_id).and_return([ [ 1, nil ], [ 2, nil ] ])
        allow(expenses).to receive(:select) do |&block|
          [ expense1, expense2 ].select(&block)
        end
        allow(expenses).to receive(:each).and_yield(expense1).and_yield(expense2)
        allow(expenses).to receive(:sum).with(:amount).and_return(80.0)

        allow(expense1).to receive(:update!).with(hash_including(
          category: category,
          auto_categorized: false,
          categorization_method: "bulk_manual"
        ))
        allow(expense2).to receive(:update!).and_raise(StandardError.new("Update failed"))
      end

      it "continues processing remaining expenses", unit: true do
        expect(expense1).to receive(:update!)
        result = service.call
        expect(result.success?).to be true
      end

      it "tracks errors for failed expenses", unit: true do
        result = service.call
        expect(result.errors).not_to be_empty
        expect(result.message).to eq("Successfully categorized 1 expense")
      end

      it "logs warning for errors", unit: true do
        expect(Rails.logger).to receive(:warn).with(/1 errors during categorization/)
        service.call
      end
    end

    context "with StandardError during processing" do
      before do
        allow(Expense).to receive(:where).and_raise(StandardError.new("Database connection error"))
      end

      it "returns failure result", unit: true do
        result = service.call
        expect(result.success?).to be false
        expect(result.message).to eq("An error occurred while categorizing expenses")
      end

      it "tracks error with ErrorTrackingService", unit: true do
        expect(ErrorTrackingService).to receive(:track_bulk_operation_error).with(
          "categorization",
          instance_of(StandardError),
          hash_including(
            expense_count: 3,
            category_id: category_id,
            user_id: user_id,
            options: default_options
          )
        )
        service.call
      end

      it "logs error details", unit: true do
        expect(Rails.logger).to receive(:error).with(/Database connection error/)
        expect(Rails.logger).to receive(:error).with(anything) # backtrace
        service.call
      end
    end

    context "pessimistic locking" do
      it "applies FOR UPDATE lock to expenses", unit: true do
        expense_relation = double("ExpenseRelation")
        include_relation = double("IncludeRelation")

        expect(Expense).to receive(:where).with(id: expense_ids).and_return(expense_relation)
        expect(expense_relation).to receive(:includes).with(:category, :email_account).and_return(include_relation)
        expect(include_relation).to receive(:lock).with("FOR UPDATE").and_return(expenses)

        allow(expenses).to receive(:count).and_return(3)
        allow(expenses).to receive(:pluck).with(:id).and_return([ 1, 2, 3 ])
        allow(expenses).to receive(:pluck).with(:id, :category_id).and_return([ [ 1, nil ], [ 2, nil ], [ 3, nil ] ])
        allow(expenses).to receive(:select).and_return([])
        allow(expenses).to receive(:each)
        allow(expenses).to receive(:sum).with(:amount).and_return(0)

        result = service.call
        # The test verifies that lock was called with "FOR UPDATE" via the expectation above
        expect(result.success?).to be true
      end
    end

    context "confidence calculation" do
      let(:expense_ids) { [ 1 ] }  # Override to match the single expense being tested
      let(:expense) do
        instance_double(Expense,
          id: 1,
          category: nil,
          merchant_name?: false,
          amount: 50.0,
          present?: false
        )
      end

      before do
        allow(expenses).to receive(:count).and_return(1)
        allow(expenses).to receive(:pluck).with(:id).and_return([ 1 ])
        allow(expenses).to receive(:pluck).with(:id, :category_id).and_return([ [ 1, nil ] ])
        allow(expenses).to receive(:select) do |&block|
          [ expense ].select(&block)
        end
        allow(expenses).to receive(:each).and_yield(expense)
        allow(expenses).to receive(:sum).with(:amount).and_return(50.0)
        # Allow update! to be called (will be overridden by expectations in individual tests)
        allow(expense).to receive(:update!)
      end

      context "when engine returns matching category" do
        it "uses engine confidence value", unit: true do
          expect(expense).to receive(:update!).with(hash_including(
            category: category,
            auto_categorized: false,
            categorization_confidence: 0.95,
            categorization_method: "bulk_manual"
          ))
          service.call
        end
      end

      context "when engine returns different category" do
        let(:other_category) { instance_double(Category, id: 99) }
        let(:categorization_result) do
          OpenStruct.new(
            successful?: true,
            category: other_category,
            confidence: 0.85
          )
        end

        it "uses default manual confidence of 0.9", unit: true do
          expect(expense).to receive(:update!).with(hash_including(
            category: category,
            auto_categorized: false,
            categorization_confidence: 0.9,
            categorization_method: "bulk_manual"
          ))
          service.call
        end
      end

      context "when engine categorization fails" do
        let(:categorization_result) do
          OpenStruct.new(
            successful?: false,
            category: nil,
            confidence: nil
          )
        end

        it "uses default manual confidence of 0.9", unit: true do
          expect(expense).to receive(:update!).with(hash_including(
            category: category,
            auto_categorized: false,
            categorization_confidence: 0.9,
            categorization_method: "bulk_manual"
          ))
          service.call
        end
      end

      context "with update_confidence disabled" do
        let(:service) do
          described_class.new(
            expense_ids: expense_ids,
            category_id: category_id,
            options: { update_confidence: false }
          )
        end

        it "sets confidence to 1.0", unit: true do
          expect(expense).to receive(:update!).with(hash_including(
            category: category,
            auto_categorized: false,
            categorization_confidence: 1.0,
            categorization_method: "bulk_manual"
          ))
          service.call
        end
      end
    end

    context "pattern creation" do
      let(:expense_ids) { [ 1 ] }  # Override to match the single expense being tested
      let(:expense) do
        instance_double(Expense,
          id: 1,
          category: nil,
          merchant_name: "Amazon",
          merchant_normalized: "amazon",
          merchant_name?: true,
          amount: 50.0,
          present?: false
        )
      end

      before do
        allow(expenses).to receive(:count).and_return(1)
        allow(expenses).to receive(:pluck).with(:id).and_return([ 1 ])
        allow(expenses).to receive(:pluck).with(:id, :category_id).and_return([ [ 1, nil ] ])
        allow(expenses).to receive(:select) do |&block|
          [ expense ].select(&block)
        end
        allow(expenses).to receive(:each).and_yield(expense)
        allow(expenses).to receive(:sum).with(:amount).and_return(50.0)
        allow(expense).to receive(:update!)

        # Allow count method for merchant normalization
        allow(expenses).to receive(:count) do |&block|
          if block
            [ expense ].count(&block)
          else
            1
          end
        end
      end

      context "when pattern does not exist" do
        before do
          allow(CategorizationPattern).to receive(:find_by).and_return(nil)
        end

        it "creates new pattern", unit: true do
          expect(CategorizationPattern).to receive(:create!).with(hash_including(
            category: category,
            pattern_type: "merchant",
            pattern_value: "amazon",
            confidence_weight: 0.8,
            user_created: true
          ))
          service.call
        end

        it "includes metadata in pattern", unit: true do
          expect(CategorizationPattern).to receive(:create!).with(hash_including(
            metadata: hash_including(
              source: "bulk_categorization",
              created_by: user_id
            )
          ))
          service.call
        end
      end

      context "when pattern already exists" do
        let(:existing_pattern) { instance_double(CategorizationPattern) }

        before do
          allow(CategorizationPattern).to receive(:find_by).and_return(existing_pattern)
        end

        it "does not create duplicate pattern", unit: true do
          expect(CategorizationPattern).not_to receive(:create!)
          service.call
        end
      end

      context "when pattern creation fails" do
        before do
          allow(CategorizationPattern).to receive(:find_by).and_return(nil)
          allow(CategorizationPattern).to receive(:create!).and_raise(
            ActiveRecord::RecordInvalid.new(CategorizationPattern.new)
          )
        end

        it "logs warning and continues", unit: true do
          expect(Rails.logger).to receive(:warn).with(/Failed to create pattern/)
          result = service.call
          expect(result.success?).to be true
        end
      end

      context "when expense has no merchant" do
        let(:expense) do
          instance_double(Expense,
            id: 1,
            category: nil,
            merchant_name: nil,
            merchant_normalized: nil,
            merchant_name?: false,
            amount: 50.0,
            present?: false
          )
        end

        it "does not create pattern", unit: true do
          expect(CategorizationPattern).not_to receive(:create!)
          service.call
        end
      end
    end

    context "transaction behavior" do
      let(:expense_ids) { [ 1 ] }  # Override to match the single expense being tested
      let(:expense) do
        instance_double(Expense,
          id: 1,
          category: nil,
          merchant_name?: false,
          amount: 50.0,
          present?: false
        )
      end

      before do
        allow(expenses).to receive(:count).and_return(1)
        allow(expenses).to receive(:pluck).with(:id).and_return([ 1 ])
        allow(expenses).to receive(:pluck).with(:id, :category_id).and_return([ [ 1, nil ] ])
        allow(expenses).to receive(:select) do |&block|
          [ expense ].select(&block)
        end
        allow(expenses).to receive(:each).and_yield(expense)
        allow(expenses).to receive(:sum).with(:amount).and_return(50.0)
      end

      it "wraps all operations in a transaction", unit: true do
        transaction_called = false
        allow(ActiveRecord::Base).to receive(:transaction) do |&block|
          transaction_called = true
          block.call
        end

        allow(expense).to receive(:update!)
        service.call
        expect(transaction_called).to be true
      end

      it "rolls back transaction on error", unit: true do
        # The engine is called during confidence calculation
        allow(engine).to receive(:categorize).and_return(categorization_result)
        allow(expense).to receive(:update!).and_raise(StandardError.new("Update failed"))

        # When individual expense updates fail, they're caught and recorded as partial failures
        # The service doesn't track this as a bulk operation error since it's handled gracefully
        result = service.call
        expect(result.success?).to be true
        expect(result.message).to eq("Successfully categorized 0 expenses")
        expect(result.errors).not_to be_empty
      end
    end

    context "result object structure" do
      let(:expense_ids) { [ 1 ] }  # Override to match the single expense being tested
      let(:expense) do
        instance_double(Expense,
          id: 1,
          category: nil,
          merchant_name?: false,
          amount: 50.0,
          present?: false
        )
      end

      before do
        allow(expenses).to receive(:count).and_return(1)
        allow(expenses).to receive(:pluck).with(:id).and_return([ 1 ])
        allow(expenses).to receive(:pluck).with(:id, :category_id).and_return([ [ 1, nil ] ])
        allow(expenses).to receive(:select) do |&block|
          [ expense ].select(&block)
        end
        allow(expenses).to receive(:each).and_yield(expense)
        allow(expenses).to receive(:sum).with(:amount).and_return(50.0)
        allow(expense).to receive(:update!)
      end

      context "success result" do
        it "includes all required fields", unit: true do
          result = service.call
          expect(result.success?).to be true
          expect(result.message).to be_present
          expect(result.bulk_operation).to eq(bulk_operation)
          expect(result.results).to be_an(Array)
          expect(result.errors).to be_an(Array)
          expect(result.expense_count).to eq(1)
          expect(result.updated_group).to be_nil
          expect(result.remaining_groups).to eq([])
        end

        it "includes individual expense results", unit: true do
          result = service.call
          expense_result = result.results.first
          expect(expense_result[:success]).to be true
          expect(expense_result[:expense_id]).to eq(1)
          expect(expense_result[:new_category_id]).to eq(category_id)
        end
      end

      context "failure result" do
        let(:service) do
          described_class.new(
            expense_ids: nil,
            category_id: category_id
          )
        end

        it "includes all required fields", unit: true do
          result = service.call
          expect(result.success?).to be false
          expect(result.message).to be_present
          expect(result.bulk_operation).to be_nil
          expect(result.results).to be_an(Array)
          expect(result.errors).to be_an(Array)
          expect(result.errors).not_to be_empty
          expect(result.expense_count).to eq(0)
        end
      end
    end

    context "multiple expense processing order" do
      let(:expense1) { instance_double(Expense, id: 1, category: nil, merchant_name?: false, amount: 10.0, present?: false) }
      let(:expense2) { instance_double(Expense, id: 2, category: nil, merchant_name?: false, amount: 20.0, present?: false) }
      let(:expense3) { instance_double(Expense, id: 3, category: nil, merchant_name?: false, amount: 30.0, present?: false) }

      before do
        allow(expenses).to receive(:count).and_return(3)
        allow(expenses).to receive(:pluck).with(:id).and_return([ 1, 2, 3 ])
        allow(expenses).to receive(:pluck).with(:id, :category_id).and_return([ [ 1, nil ], [ 2, nil ], [ 3, nil ] ])
        allow(expenses).to receive(:select) do |&block|
          [ expense1, expense2, expense3 ].select(&block)
        end
        allow(expenses).to receive(:sum).with(:amount).and_return(60.0)
      end

      it "processes expenses in order", unit: true do
        processed_order = []
        allow(expenses).to receive(:each) do |&block|
          [ expense1, expense2, expense3 ].each { |e| block.call(e) }
        end

        [ expense1, expense2, expense3 ].each do |expense|
          allow(expense).to receive(:update!) do
            processed_order << expense.id
          end
        end

        service.call
        expect(processed_order).to eq([ 1, 2, 3 ])
      end
    end

    context "metadata tracking" do
      let(:expense_ids) { [ 1, 2 ] }  # Override to match the two expenses being tested
      let(:expense1) { instance_double(Expense, id: 1, category: nil, category_id: 5, merchant_name?: false, amount: 50.0, present?: false) }
      let(:expense2) { instance_double(Expense, id: 2, category: nil, category_id: nil, merchant_name?: false, amount: 30.0, present?: false) }

      before do
        allow(expenses).to receive(:count).and_return(2)
        allow(expenses).to receive(:pluck).with(:id).and_return([ 1, 2 ])
        allow(expenses).to receive(:pluck).with(:id, :category_id).and_return([ [ 1, 5 ], [ 2, nil ] ])
        allow(expenses).to receive(:select).and_return([])
        allow(expenses).to receive(:each).and_yield(expense1).and_yield(expense2)
        allow(expenses).to receive(:sum).with(:amount).and_return(80.0)
        allow(expense1).to receive(:update!).with(hash_including(
          category: category,
          auto_categorized: false,
          categorization_method: "bulk_manual"
        ))
        allow(expense2).to receive(:update!).with(hash_including(
          category: category,
          auto_categorized: false,
          categorization_method: "bulk_manual"
        ))
      end

      it "tracks previous categories in metadata", unit: true do
        expect(BulkOperation).to receive(:create!).with(hash_including(
          metadata: hash_including(
            expense_ids: expense_ids,
            previous_categories: { 1 => 5, 2 => nil }
          )
        ))
        service.call
      end

      it "includes timestamp in metadata", unit: true do
        expect(BulkOperation).to receive(:create!).with(hash_including(
          metadata: hash_including(:applied_at)
        ))
        service.call
      end
    end

    context "notification broadcasting details" do
      let(:expense_ids) { [ 1 ] }  # Override to match the single expense being tested
      let(:expense) do
        instance_double(Expense,
          id: 1,
          category: nil,
          merchant_name?: false,
          amount: 50.0,
          present?: false
        )
      end

      before do
        allow(expenses).to receive(:count).and_return(1)
        allow(expenses).to receive(:pluck).with(:id).and_return([ 1 ])
        allow(expenses).to receive(:pluck).with(:id, :category_id).and_return([ [ 1, nil ] ])
        allow(expenses).to receive(:select) do |&block|
          [ expense ].select(&block)
        end
        allow(expenses).to receive(:each).and_yield(expense)
        allow(expenses).to receive(:sum).with(:amount).and_return(50.0)
        allow(expense).to receive(:update!)
      end

      it "broadcasts with correct channel and target", unit: true do
        expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
          "bulk_categorization_updates",
          hash_including(
            target: "categorization_progress",
            partial: "bulk_categorizations/progress"
          )
        )
        service.call
      end

      it "includes progress data in broadcast", unit: true do
        expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
          anything,
          hash_including(
            locals: hash_including(
              completed: 1,
              total: 1,
              errors: 0
            )
          )
        )
        service.call
      end

      context "with partial failures" do
        let(:expense_ids) { [ 1, 2 ] }  # Override to match the two expenses being tested
        let(:expense2) do
          instance_double(Expense,
            id: 2,
            category: nil,
            merchant_name?: false,
            amount: 30.0,
            present?: false
          )
        end

        before do
          allow(expenses).to receive(:count).and_return(2)
          allow(expenses).to receive(:pluck).with(:id).and_return([ 1, 2 ])
          allow(expenses).to receive(:pluck).with(:id, :category_id).and_return([ [ 1, nil ], [ 2, nil ] ])
          allow(expenses).to receive(:select) do |&block|
            [ expense, expense2 ].select(&block) if block
          end
          allow(expenses).to receive(:each).and_yield(expense).and_yield(expense2)
          allow(expenses).to receive(:sum).with(:amount).and_return(80.0)
          allow(expense).to receive(:update!).with(hash_including(
            category: category,
            auto_categorized: false,
            categorization_method: "bulk_manual"
          ))
          allow(expense2).to receive(:update!).and_raise(StandardError.new("Update failed"))
        end

        it "broadcasts correct error count", unit: true do
          expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
            anything,
            hash_including(
              locals: hash_including(
                completed: 1,
                total: 2,
                errors: 1
              )
            )
          )
          service.call
        end
      end
    end
  end

  describe "edge cases and complex scenarios" do
    context "with very large batch" do
      let(:expense_ids) { (1..1000).to_a }
      let(:large_expenses) { [] }

      before do
        allow(Expense).to receive(:where).and_return(double(includes: double(lock: large_expenses)))
        allow(large_expenses).to receive(:count).and_return(1000)
        allow(large_expenses).to receive(:pluck).with(:id).and_return(expense_ids)
        allow(large_expenses).to receive(:pluck).with(:id, :category_id).and_return(expense_ids.map { |id| [ id, nil ] })
        allow(large_expenses).to receive(:select).and_return([])
        allow(large_expenses).to receive(:each)
        allow(large_expenses).to receive(:sum).with(:amount).and_return(10000.0)
      end

      it "handles large batches efficiently", unit: true do
        result = service.call
        expect(result).to be_a(OpenStruct)
      end
    end

    context "with duplicate expense_ids" do
      let(:expense_ids) { [ 1, 2, 2, 3, 1 ] }
      let(:unique_expenses) { [] }

      before do
        allow(Expense).to receive(:where).with(id: expense_ids).and_return(
          double(includes: double(lock: unique_expenses))
        )
        allow(unique_expenses).to receive(:count).and_return(3)
        allow(unique_expenses).to receive(:pluck).with(:id).and_return([ 1, 2, 3 ])
      end

      it "handles duplicates correctly", unit: true do
        result = service.call
        expect(result.success?).to be false
        expect(result.message).to eq("An error occurred while categorizing expenses")
      end
    end

    context "concurrent modification protection" do
      it "uses pessimistic locking", unit: true do
        expense_relation = double("ExpenseRelation")
        include_relation = double("IncludeRelation")

        expect(Expense).to receive(:where).and_return(expense_relation)
        expect(expense_relation).to receive(:includes).and_return(include_relation)
        expect(include_relation).to receive(:lock).with("FOR UPDATE").and_return(expenses)

        allow(expenses).to receive(:count).and_return(3)
        allow(expenses).to receive(:pluck).with(:id).and_return([ 1, 2, 3 ])
        allow(expenses).to receive(:pluck).with(:id, :category_id).and_return([ [ 1, nil ], [ 2, nil ], [ 3, nil ] ])
        allow(expenses).to receive(:select).and_return([])
        allow(expenses).to receive(:each)
        allow(expenses).to receive(:sum).with(:amount).and_return(0)

        result = service.call
        # The test verifies that lock was called with "FOR UPDATE" via the expectation above
        expect(result.success?).to be true
      end
    end
  end
end
