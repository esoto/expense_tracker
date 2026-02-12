# frozen_string_literal: true

require "rails_helper"

RSpec.describe Category, type: :model, unit: true do
  # Use build for true unit testing
  let(:parent_category) { build(:category, id: 1, name: "Food", parent_id: nil) }
  let(:category) do
    build(:category,
      id: 2,
      name: "Restaurants",
      parent: parent_category,
      parent_id: parent_category.id,
      color: "#FF5733")
  end

  describe "validations" do
    subject { build(:category) }
    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(255) }

    describe "color validation" do
      it "accepts valid hex colors" do
        valid_colors = [ "#FF5733", "#F57", "#aabbcc", nil, "" ]
        valid_colors.each do |color|
          subject.color = color
          expect(subject).to be_valid
        end
      end

      it "rejects invalid hex colors" do
        invalid_colors = [ "FF5733", "#FF57", "#GGHHII", "red" ]
        invalid_colors.each do |color|
          subject.color = color
          expect(subject).not_to be_valid
          expect(subject.errors[:color]).to include("must be a valid hex color")
        end
      end
    end

    describe "parent validation" do
      it "prevents category from being its own parent" do
        subject = create(:category)
        subject.parent_id = subject.id

        expect(subject).not_to be_valid
        expect(subject.errors[:parent]).to include("cannot be itself")
      end

      it "prevents circular references" do
        grandparent = create(:category, name: "Grandparent")
        parent = create(:category, name: "Parent", parent: grandparent)

        # Try to make grandparent's parent be the child (circular)
        grandparent.parent_id = parent.id

        expect(grandparent).not_to be_valid
        expect(grandparent.errors[:parent]).to include("cannot create circular reference")
      end
    end
  end

  describe "associations" do
    it { should belong_to(:parent).class_name("Category").optional }
    it { should have_many(:children).class_name("Category").with_foreign_key("parent_id").dependent(:nullify) }
    it { should have_many(:expenses).dependent(:nullify) }
    it { should have_many(:categorization_patterns).dependent(:destroy) }
    it { should have_many(:composite_patterns).dependent(:destroy) }
    it { should have_many(:pattern_feedbacks).dependent(:destroy) }
    it { should have_many(:pattern_learning_events).dependent(:destroy) }
    it { should have_many(:user_category_preferences).dependent(:destroy) }
  end

  describe "scopes" do
    describe ".root_categories" do
      it "returns categories without parent" do
        query = described_class.root_categories
        expect(query.to_sql).to include('"categories"."parent_id" IS NULL')
      end
    end

    describe ".subcategories" do
      it "returns categories with parent" do
        query = described_class.subcategories
        expect(query.to_sql).to include('"categories"."parent_id" IS NOT NULL')
      end
    end

    describe ".active" do
      it "returns all categories" do
        query = described_class.active
        # Should not add any WHERE clause
        expect(query.to_sql).not_to include("WHERE")
      end
    end
  end

  describe "#root?" do
    context "when category has no parent" do
      it "returns true" do
        root_category = build(:category, parent_id: nil)
        expect(root_category.root?).to be true
      end
    end

    context "when category has a parent" do
      it "returns false" do
        child_category = build(:category, parent_id: 1)
        expect(child_category.root?).to be false
      end
    end
  end

  describe "#subcategory?" do
    context "when category has no parent" do
      it "returns false" do
        root_category = build(:category, parent_id: nil)
        expect(root_category.subcategory?).to be false
      end
    end

    context "when category has a parent" do
      it "returns true" do
        subcategory = build(:category, parent_id: 1)
        expect(subcategory.subcategory?).to be true
      end
    end
  end

  describe "#full_name" do
    let(:root_category) { create(:category, name: "Transportation", parent_id: nil) }
    let!(:child_category) { create(:category, name: "Food", parent_id: root_category.id) }

    context "for root category" do
      it "returns just the name" do
        expect(root_category.full_name).to eq("Transportation")
      end
    end

    context "for subcategory" do
      it "returns parent name > child name" do
        expect(child_category.full_name).to eq("Transportation > Food")
      end
    end
  end

  describe "private methods" do
    describe "#cannot_be_parent_of_itself" do
      context "when both id and parent_id are present" do
        it "adds error when parent_id equals id" do
          category = create(:category)
          category.parent_id = category.id

          category.send(:cannot_be_parent_of_itself)
          expect(category.errors[:parent]).to include("cannot be itself")
        end

        it "adds error for circular reference" do
          parent = create(:category, name: "Parent")
          child = create(:category, name: "Child", parent: parent)

          parent.parent_id = child.id
          parent.send(:cannot_be_parent_of_itself)
          expect(parent.errors[:parent]).to include("cannot create circular reference")
        end

        it "does not add error for valid parent" do
          parent = create(:category, name: "Parent")
          child = create(:category, name: "Child")

          child.parent_id = parent.id
          child.send(:cannot_be_parent_of_itself)
          expect(child.errors[:parent]).to be_empty
        end
      end

      context "when id is nil (new record)" do
        it "skips validation" do
          category = build(:category)
          category.parent_id = 999

          category.send(:cannot_be_parent_of_itself)
          expect(category.errors[:parent]).to be_empty
        end
      end

      context "when parent_id is nil" do
        it "skips validation" do
          category = create(:category)
          category.parent_id = nil

          category.send(:cannot_be_parent_of_itself)
          expect(category.errors[:parent]).to be_empty
        end
      end
    end
  end
end
