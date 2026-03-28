# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::ExpenseCollectionAdapter, type: :service do
  let(:expense1) { build_stubbed(:expense) }
  let(:expense2) { build_stubbed(:expense) }
  let(:expense3) { build_stubbed(:expense) }
  let(:array_collection) { [ expense1, expense2, expense3 ] }

  subject(:adapter) { described_class.new(array_collection) }

  describe "#initialize" do
    it "wraps an array collection", unit: true do
      expect(adapter).to be_a(described_class)
    end

    it "wraps an ActiveRecord::Relation", unit: true do
      relation = Expense.none
      ar_adapter = described_class.new(relation)

      expect(ar_adapter).to be_a(described_class)
    end
  end

  describe "#find_each" do
    context "with an array collection" do
      it "yields each element", unit: true do
        collected = []
        adapter.find_each { |e| collected << e }

        expect(collected).to eq(array_collection)
      end
    end

    context "with an ActiveRecord::Relation", unit: true do
      it "delegates to AR find_each", unit: true do
        relation = instance_double(ActiveRecord::Relation)
        allow(relation).to receive(:is_a?).with(ActiveRecord::Relation).and_return(true)
        allow(relation).to receive(:find_each).and_yield(expense1)

        ar_adapter = described_class.new(relation)
        collected = []
        ar_adapter.find_each { |e| collected << e }

        expect(collected).to eq([ expense1 ])
      end
    end
  end

  describe "#in_batches" do
    context "with an array collection" do
      it "yields slices of the given size", unit: true do
        batches = []
        adapter.in_batches(batch_size: 2) { |batch| batches << batch }

        expect(batches.size).to eq(2)
        expect(batches.first.size).to eq(2)
        expect(batches.last.size).to eq(1)
      end

      it "uses default batch_size of 100", unit: true do
        items = Array.new(150) { build_stubbed(:expense) }
        large_adapter = described_class.new(items)

        batches = []
        large_adapter.in_batches { |batch| batches << batch }

        expect(batches.size).to eq(2)
        expect(batches.first.size).to eq(100)
        expect(batches.last.size).to eq(50)
      end
    end

    context "with an ActiveRecord::Relation" do
      it "delegates to AR in_batches", unit: true do
        relation = instance_double(ActiveRecord::Relation)
        allow(relation).to receive(:is_a?).with(ActiveRecord::Relation).and_return(true)
        allow(relation).to receive(:in_batches).with(of: 50).and_yield([ expense1 ])

        ar_adapter = described_class.new(relation)
        collected = []
        ar_adapter.in_batches(batch_size: 50) { |batch| collected << batch }

        expect(collected).to eq([ [ expense1 ] ])
      end
    end
  end

  describe "#each" do
    it "delegates to the collection", unit: true do
      collected = []
      adapter.each { |e| collected << e }

      expect(collected).to eq(array_collection)
    end
  end

  describe "#empty?" do
    it "returns false for a non-empty collection", unit: true do
      expect(adapter.empty?).to be false
    end

    it "returns true for an empty collection", unit: true do
      empty_adapter = described_class.new([])

      expect(empty_adapter.empty?).to be true
    end
  end

  describe "#size" do
    it "returns the number of elements", unit: true do
      expect(adapter.size).to eq(3)
    end

    it "returns 0 for empty collection", unit: true do
      expect(described_class.new([]).size).to eq(0)
    end
  end

  describe "#count" do
    it "returns the count of elements", unit: true do
      expect(adapter.count).to eq(3)
    end
  end

  describe "#select" do
    it "filters elements using the block", unit: true do
      result = adapter.select { |e| e == expense1 }

      expect(result).to eq([ expense1 ])
    end
  end

  describe "#map" do
    it "transforms each element", unit: true do
      result = adapter.map { |e| e.id }

      expect(result).to eq(array_collection.map(&:id))
    end
  end

  describe "#sum" do
    it "sums values returned by the block", unit: true do
      allow(expense1).to receive(:amount).and_return(10.0)
      allow(expense2).to receive(:amount).and_return(20.0)
      allow(expense3).to receive(:amount).and_return(30.0)

      result = adapter.sum(&:amount)

      expect(result).to eq(60.0)
    end
  end

  describe "#group_by" do
    it "groups elements by block result", unit: true do
      allow(expense1).to receive(:category_id).and_return(1)
      allow(expense2).to receive(:category_id).and_return(2)
      allow(expense3).to receive(:category_id).and_return(1)

      result = adapter.group_by(&:category_id)

      expect(result[1]).to contain_exactly(expense1, expense3)
      expect(result[2]).to contain_exactly(expense2)
    end
  end

  describe "#min_by" do
    it "returns the element with the minimum value", unit: true do
      allow(expense1).to receive(:amount).and_return(5.0)
      allow(expense2).to receive(:amount).and_return(2.0)
      allow(expense3).to receive(:amount).and_return(8.0)

      result = adapter.min_by(&:amount)

      expect(result).to eq(expense2)
    end
  end

  describe "#max_by" do
    it "returns the element with the maximum value", unit: true do
      allow(expense1).to receive(:amount).and_return(5.0)
      allow(expense2).to receive(:amount).and_return(2.0)
      allow(expense3).to receive(:amount).and_return(8.0)

      result = adapter.max_by(&:amount)

      expect(result).to eq(expense3)
    end
  end

  describe "method_missing / respond_to_missing?" do
    it "delegates unknown methods to the collection", unit: true do
      # Use a simple struct so respond_to? works naturally
      custom_class = Struct.new(:some_custom_method)
      custom_collection = custom_class.new("delegated")

      custom_adapter = described_class.new(custom_collection)
      result = custom_adapter.some_custom_method

      expect(result).to eq("delegated")
    end

    it "responds to methods the collection responds to", unit: true do
      expect(adapter.respond_to?(:first)).to be true
    end

    it "does not respond to methods the collection does not respond to", unit: true do
      expect(adapter.respond_to?(:nonexistent_xyz_method)).to be false
    end

    it "raises NoMethodError for truly missing methods", unit: true do
      expect { adapter.nonexistent_xyz_method }.to raise_error(NoMethodError)
    end
  end
end
