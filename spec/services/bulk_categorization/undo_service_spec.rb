# frozen_string_literal: true

require "rails_helper"

RSpec.describe BulkCategorization::UndoService, type: :service, unit: true do
  # Test doubles and mocks
  let(:bulk_operation) do
    instance_double(
      BulkOperation,
      id: 100,
      expense_count: 5,
      undoable?: true,
      undo!: true,
      reload: nil
    )
  end

  let(:service) { described_class.new(bulk_operation: bulk_operation) }

  describe "#initialize" do
    it "initializes with bulk_operation" do
      service = described_class.new(bulk_operation: bulk_operation)
      expect(service.bulk_operation).to eq(bulk_operation)
    end
  end

  describe "validations" do
    it "validates presence of bulk_operation" do
      service = described_class.new(bulk_operation: nil)
      expect(service).not_to be_valid
      expect(service.errors[:bulk_operation]).to include("can't be blank")
    end
  end

  describe "#call" do
    context "with successful undo" do
      before do
        allow(bulk_operation).to receive(:undoable?).and_return(true)
        allow(bulk_operation).to receive(:undo!).and_return(true)
        allow(bulk_operation).to receive(:reload).and_return(bulk_operation)
      end

      it "returns success result with proper structure" do
        result = service.call

        expect(result.success?).to be true
        expect(result.message).to eq("Successfully undone categorization for 5 expenses")
        expect(result.operation).to eq(bulk_operation)
      end

      it "reloads bulk_operation in success result" do
        expect(bulk_operation).to receive(:reload).and_return(bulk_operation)

        result = service.call
        expect(result.operation).to eq(bulk_operation)
      end
    end

    context "with non-undoable operation" do
      before do
        allow(bulk_operation).to receive(:undoable?).and_return(false)
      end

      it "returns failure result when operation is not undoable" do
        result = service.call

        expect(result.success?).to be false
        expect(result.message).to eq("Operation cannot be undone")
        expect(result.operation).to eq(bulk_operation)
      end
    end

    context "when undo! returns false" do
      before do
        allow(bulk_operation).to receive(:undoable?).and_return(true)
        allow(bulk_operation).to receive(:undo!).and_return(false)
      end

      it "returns failure result with business logic failure message" do
        result = service.call

        expect(result.success?).to be false
        expect(result.message).to eq("Failed to undo operation")
        expect(result.operation).to eq(bulk_operation)
      end
    end

    context "when undo! raises StandardError" do
      before do
        allow(bulk_operation).to receive(:undoable?).and_return(true)
        allow(bulk_operation).to receive(:undo!).and_raise(StandardError.new("Database error"))
        allow(Rails.logger).to receive(:error)
      end

      it "handles exception and returns failure result" do
        result = service.call

        expect(result.success?).to be false
        expect(result.message).to eq("An error occurred while undoing the operation")
        expect(result.operation).to eq(bulk_operation)
        expect(Rails.logger).to have_received(:error).with("BulkCategorization::UndoService error: Database error")
      end
    end

    context "result format verification" do
      it "returns OpenStruct with correct fields for success" do
        allow(bulk_operation).to receive(:undoable?).and_return(true)
        allow(bulk_operation).to receive(:undo!).and_return(true)
        allow(bulk_operation).to receive(:reload).and_return(bulk_operation)

        result = service.call

        expect(result).to be_a(OpenStruct)
        expect(result.to_h.keys).to match_array([:success?, :message, :operation])
        expect(result.success?).to be true
        expect(result.message).to be_a(String)
        expect(result.operation).to eq(bulk_operation)
      end

      it "returns OpenStruct with correct fields for failure" do
        allow(bulk_operation).to receive(:undoable?).and_return(false)

        result = service.call

        expect(result).to be_a(OpenStruct)
        expect(result.to_h.keys).to match_array([:success?, :message, :operation])
        expect(result.success?).to be false
        expect(result.message).to be_a(String)
        expect(result.operation).to eq(bulk_operation)
      end
    end
  end
end