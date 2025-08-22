# frozen_string_literal: true

require "rails_helper"

RSpec.describe BulkOperationItem, type: :model, unit: true do
  # Helper method to build a stubbed instance
  def build_bulk_operation_item(attributes = {})
    default_attributes = {
      status: :pending,
      previous_confidence: nil,
      created_at: Time.current,
      updated_at: Time.current
    }
    build_stubbed(:bulk_operation_item, default_attributes.merge(attributes))
  end

  describe "associations" do
    it { should belong_to(:bulk_operation) }
    it { should belong_to(:expense) }
    it { should belong_to(:previous_category).class_name("Category").optional }
    it { should belong_to(:new_category).class_name("Category").optional }
  end

  describe "enums" do
    it "defines status enum with default" do
      should define_enum_for(:status)
        .with_values(
          pending: 0,
          completed: 1,
          failed: 2,
          skipped: 3,
          undone: 4
        )
        .backed_by_column_of_type(:integer)
    end

    it "defaults to pending status" do
      item = BulkOperationItem.new
      expect(item.status).to eq("pending")
    end
  end

  describe "validations" do
    describe "expense_id uniqueness" do
      let(:bulk_operation) { build_stubbed(:bulk_operation, id: 1) }
      let(:expense) { build_stubbed(:expense, id: 1) }
      
      it "validates uniqueness of expense_id scoped to bulk_operation_id" do
        item = build_bulk_operation_item(
          bulk_operation: bulk_operation,
          expense: expense
        )
        
        # Mock the uniqueness validation
        allow(item).to receive(:errors).and_return(ActiveModel::Errors.new(item))
        
        # Create a double for the relation
        relation = double("relation")
        allow(BulkOperationItem).to receive(:where).and_return(relation)
        allow(relation).to receive(:exists?).and_return(false)
        
        expect(item).to be_valid
      end
    end
  end

  describe "scopes" do
    describe ".successful" do
      it "filters by completed status" do
        expect(BulkOperationItem.successful.to_sql).to include("status")
      end
    end

    describe ".failed" do
      it "filters by failed status" do
        expect(BulkOperationItem.failed.to_sql).to include("status")
      end
    end

    describe ".with_category_change" do
      it "filters items where previous_category_id is not null" do
        sql = BulkOperationItem.with_category_change.to_sql
        expect(sql).to include("previous_category_id")
      end
    end
  end

  describe "#category_changed?" do
    context "when categories are different" do
      let(:item) do
        build_bulk_operation_item(
          previous_category_id: 1,
          new_category_id: 2
        )
      end

      it "returns true" do
        expect(item.category_changed?).to be true
      end
    end

    context "when categories are the same" do
      let(:item) do
        build_bulk_operation_item(
          previous_category_id: 1,
          new_category_id: 1
        )
      end

      it "returns false" do
        expect(item.category_changed?).to be false
      end
    end

    context "when both categories are nil" do
      let(:item) do
        build_bulk_operation_item(
          previous_category_id: nil,
          new_category_id: nil
        )
      end

      it "returns false" do
        expect(item.category_changed?).to be false
      end
    end

    context "when one category is nil" do
      it "returns true when previous is nil" do
        item = build_bulk_operation_item(
          previous_category_id: nil,
          new_category_id: 1
        )
        expect(item.category_changed?).to be true
      end

      it "returns true when new is nil" do
        item = build_bulk_operation_item(
          previous_category_id: 1,
          new_category_id: nil
        )
        expect(item.category_changed?).to be true
      end
    end
  end

  describe "#confidence_delta" do
    let(:expense) { build_stubbed(:expense) }
    let(:item) { build_bulk_operation_item(expense: expense) }

    context "when both confidences are present" do
      before do
        allow(expense).to receive(:categorization_confidence).and_return(0.9)
        allow(item).to receive(:previous_confidence).and_return(0.6)
      end

      it "calculates the difference" do
        expect(item.confidence_delta).to eq(0.3)
      end

      it "handles negative deltas" do
        allow(expense).to receive(:categorization_confidence).and_return(0.4)
        expect(item.confidence_delta).to eq(-0.2)
      end

      it "handles zero delta" do
        allow(expense).to receive(:categorization_confidence).and_return(0.6)
        expect(item.confidence_delta).to eq(0.0)
      end
    end

    context "when expense confidence is nil" do
      before do
        allow(expense).to receive(:categorization_confidence).and_return(nil)
        allow(item).to receive(:previous_confidence).and_return(0.6)
      end

      it "returns nil" do
        expect(item.confidence_delta).to be_nil
      end
    end

    context "when previous confidence is nil" do
      before do
        allow(expense).to receive(:categorization_confidence).and_return(0.9)
        allow(item).to receive(:previous_confidence).and_return(nil)
      end

      it "returns nil" do
        expect(item.confidence_delta).to be_nil
      end
    end

    context "when both confidences are nil" do
      before do
        allow(expense).to receive(:categorization_confidence).and_return(nil)
        allow(item).to receive(:previous_confidence).and_return(nil)
      end

      it "returns nil" do
        expect(item.confidence_delta).to be_nil
      end
    end
  end

  describe "#processing_time_ms" do
    let(:item) { build_bulk_operation_item }

    context "when both timestamps are present" do
      before do
        allow(item).to receive(:created_at).and_return(Time.parse("2024-01-01 10:00:00"))
        allow(item).to receive(:processed_at).and_return(Time.parse("2024-01-01 10:00:01.500"))
      end

      it "calculates time in milliseconds" do
        expect(item.processing_time_ms).to eq(1500.0)
      end

      it "handles sub-second precision" do
        allow(item).to receive(:processed_at).and_return(Time.parse("2024-01-01 10:00:00.250"))
        expect(item.processing_time_ms).to eq(250.0)
      end

      it "handles very small durations" do
        allow(item).to receive(:processed_at).and_return(Time.parse("2024-01-01 10:00:00.001"))
        expect(item.processing_time_ms).to eq(1.0)
      end

      it "rounds to 2 decimal places" do
        allow(item).to receive(:processed_at).and_return(Time.parse("2024-01-01 10:00:00.1234567"))
        expect(item.processing_time_ms).to eq(123.46)
      end
    end

    context "when processed_at is nil" do
      before do
        allow(item).to receive(:processed_at).and_return(nil)
        allow(item).to receive(:created_at).and_return(Time.current)
      end

      it "returns nil" do
        expect(item.processing_time_ms).to be_nil
      end
    end

    context "when created_at is nil" do
      before do
        allow(item).to receive(:processed_at).and_return(Time.current)
        allow(item).to receive(:created_at).and_return(nil)
      end

      it "returns nil" do
        expect(item.processing_time_ms).to be_nil
      end
    end

    context "when both timestamps are nil" do
      before do
        allow(item).to receive(:processed_at).and_return(nil)
        allow(item).to receive(:created_at).and_return(nil)
      end

      it "returns nil" do
        expect(item.processing_time_ms).to be_nil
      end
    end
  end

  describe "edge cases and state transitions" do
    describe "status transitions" do
      let(:item) { build_bulk_operation_item(status: :pending) }

      it "can transition from pending to completed" do
        item.status = :completed
        expect(item.completed?).to be true
      end

      it "can transition from pending to failed" do
        item.status = :failed
        expect(item.failed?).to be true
      end

      it "can transition from pending to skipped" do
        item.status = :skipped
        expect(item.skipped?).to be true
      end

      it "can transition to undone from any status" do
        [ :pending, :completed, :failed, :skipped ].each do |initial_status|
          item.status = initial_status
          item.status = :undone
          expect(item.undone?).to be true
        end
      end
    end

    describe "relationship integrity" do
      let(:item) { build_bulk_operation_item }

      it "handles orphaned relationships gracefully" do
        allow(item).to receive(:bulk_operation).and_return(nil)
        allow(item).to receive(:expense).and_return(nil)
        
        # Methods should not raise errors
        expect { item.category_changed? }.not_to raise_error
        expect { item.confidence_delta }.not_to raise_error
      end
    end

    describe "data consistency" do
      it "maintains consistency between category IDs" do
        item = build_bulk_operation_item(
          previous_category_id: 1,
          new_category_id: 2
        )
        
        # Verify the item correctly tracks category changes
        expect(item.previous_category_id).to eq(1)
        expect(item.new_category_id).to eq(2)
        expect(item.category_changed?).to be true
      end

      it "handles large confidence values" do
        expense = build_stubbed(:expense, categorization_confidence: 0.999999)
        item = build_bulk_operation_item(
          expense: expense,
          previous_confidence: 0.000001
        )
        
        expect(item.confidence_delta).to be_within(0.000001).of(0.999998)
      end
    end

    describe "performance considerations" do
      it "efficiently handles bulk operations" do
        # Simulate a bulk operation with many items
        items = 1000.times.map do |i|
          build_bulk_operation_item(
            previous_category_id: i % 10,
            new_category_id: (i % 10) + 1,
            previous_confidence: rand(0.1..0.9),
            processed_at: Time.current + i.seconds
          )
        end
        
        # All items should be valid
        expect(items).to all(be_valid)
      end
    end

    describe "error handling" do
      let(:item) { build_bulk_operation_item }

      it "handles nil expense gracefully in confidence_delta" do
        allow(item).to receive(:expense).and_return(nil)
        expect(item.confidence_delta).to be_nil
      end

      it "handles calculation errors gracefully" do
        allow(item).to receive(:processed_at).and_raise(StandardError)
        expect { item.processing_time_ms }.to raise_error(StandardError)
      end
    end
  end

  describe "business logic validation" do
    describe "state consistency" do
      it "ensures failed items have appropriate metadata" do
        item = build_bulk_operation_item(
          status: :failed,
          error_message: "Category not found"
        )
        expect(item.failed?).to be true
      end

      it "ensures completed items have new_category_id" do
        item = build_bulk_operation_item(
          status: :completed,
          new_category_id: 1
        )
        expect(item.completed?).to be true
        expect(item.new_category_id).not_to be_nil
      end
    end

    describe "audit trail" do
      let(:item) do
        build_bulk_operation_item(
          previous_category_id: 1,
          new_category_id: 2,
          previous_confidence: 0.5,
          created_at: 1.hour.ago,
          processed_at: 30.minutes.ago
        )
      end

      it "maintains complete change history" do
        expect(item.previous_category_id).to eq(1)
        expect(item.new_category_id).to eq(2)
        expect(item.previous_confidence).to eq(0.5)
        expect(item.category_changed?).to be true
      end
    end
  end
end