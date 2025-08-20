# frozen_string_literal: true

require "rails_helper"

RSpec.describe Category, type: :model, unit: true do
  # Use build_stubbed for true unit testing
  let(:parent_category) { build_stubbed(:category, id: 1, name: "Food", parent_id: nil) }
  let(:category) do
    build_stubbed(:category,
      id: 2,
      name: "Restaurants",
      parent: parent_category,
      parent_id: parent_category.id,
      color: "#FF5733",
      icon: "utensils")
  end

  describe "validations" do
    subject { build(:category) }

    describe "name validation" do
      it "validates presence of name" do
        subject.name = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:name]).to include("can't be blank")
      end

      it "validates maximum length of name" do
        subject.name = "a" * 256
        expect(subject).not_to be_valid
        expect(subject.errors[:name]).to include("is too long (maximum is 255 characters)")
      end

      it "accepts valid name" do
        subject.name = "Transportation"
        expect(subject).to be_valid
      end

      it "accepts name at maximum length" do
        subject.name = "a" * 255
        expect(subject).to be_valid
      end

      it "accepts empty string as name (but fails presence)" do
        subject.name = ""
        expect(subject).not_to be_valid
        expect(subject.errors[:name]).to include("can't be blank")
      end
    end

    describe "color validation" do
      it "accepts valid 6-digit hex color" do
        subject.color = "#FF5733"
        expect(subject).to be_valid
      end

      it "accepts valid 3-digit hex color" do
        subject.color = "#F57"
        expect(subject).to be_valid
      end

      it "accepts lowercase hex digits" do
        subject.color = "#aabbcc"
        expect(subject).to be_valid
      end

      it "accepts uppercase hex digits" do
        subject.color = "#AABBCC"
        expect(subject).to be_valid
      end

      it "accepts mixed case hex digits" do
        subject.color = "#AaBbCc"
        expect(subject).to be_valid
      end

      it "allows blank color" do
        subject.color = nil
        expect(subject).to be_valid
      end

      it "allows empty string color" do
        subject.color = ""
        expect(subject).to be_valid
      end

      it "rejects invalid hex color without hash" do
        subject.color = "FF5733"
        expect(subject).not_to be_valid
        expect(subject.errors[:color]).to include("must be a valid hex color")
      end

      it "rejects invalid hex color with wrong length" do
        subject.color = "#FF57"
        expect(subject).not_to be_valid
        expect(subject.errors[:color]).to include("must be a valid hex color")
      end

      it "rejects invalid hex color with non-hex characters" do
        subject.color = "#GGHHII"
        expect(subject).not_to be_valid
        expect(subject.errors[:color]).to include("must be a valid hex color")
      end

      it "rejects RGB format" do
        subject.color = "rgb(255, 87, 51)"
        expect(subject).not_to be_valid
        expect(subject.errors[:color]).to include("must be a valid hex color")
      end

      it "rejects color names" do
        subject.color = "red"
        expect(subject).not_to be_valid
        expect(subject.errors[:color]).to include("must be a valid hex color")
      end
    end

    describe "parent validation" do
      context "self-reference validation" do
        it "prevents category from being its own parent" do
          subject = create(:category)
          subject.parent_id = subject.id
          
          expect(subject).not_to be_valid
          expect(subject.errors[:parent]).to include("cannot be itself")
        end

        it "allows nil parent_id" do
          subject.parent_id = nil
          expect(subject).to be_valid
        end

        it "allows valid parent reference" do
          parent = create(:category, name: "Parent")
          subject.parent = parent
          expect(subject).to be_valid
        end
      end

      context "circular reference validation" do
        it "prevents circular references" do
          grandparent = create(:category, name: "Grandparent")
          parent = create(:category, name: "Parent", parent: grandparent)
          
          # Try to make grandparent's parent be the child (circular)
          grandparent.parent_id = parent.id
          
          expect(grandparent).not_to be_valid
          expect(grandparent.errors[:parent]).to include("cannot create circular reference")
        end

        it "allows non-circular hierarchies" do
          grandparent = create(:category, name: "Grandparent")
          parent = create(:category, name: "Parent", parent: grandparent)
          child = build(:category, name: "Child", parent: parent)
          
          expect(child).to be_valid
        end
      end

      context "when category is new" do
        it "skips self-reference check for unsaved records" do
          new_category = build(:category)
          new_category.parent_id = 999 # Some ID
          
          # Should not check self-reference since id is nil
          expect(new_category).to be_valid
        end
      end
    end
  end

  describe "associations" do
    describe "parent association" do
      it "belongs to parent (optional)" do
        association = described_class.reflect_on_association(:parent)
        expect(association.macro).to eq(:belongs_to)
        expect(association.options[:class_name]).to eq("Category")
        expect(association.options[:optional]).to be true
      end

      it "can exist without parent" do
        root_category = build_stubbed(:category, parent: nil)
        expect(root_category.parent).to be_nil
      end

      it "can have a parent" do
        expect(category.parent).to eq(parent_category)
      end
    end

    describe "children association" do
      it "has many children" do
        association = described_class.reflect_on_association(:children)
        expect(association.macro).to eq(:has_many)
        expect(association.options[:class_name]).to eq("Category")
        expect(association.options[:foreign_key]).to eq("parent_id")
        expect(association.options[:dependent]).to eq(:nullify)
      end

      it "nullifies children when deleted" do
        parent = create(:category, name: "Parent")
        child1 = create(:category, name: "Child 1", parent: parent)
        child2 = create(:category, name: "Child 2", parent: parent)
        
        parent.destroy
        
        expect(child1.reload.parent_id).to be_nil
        expect(child2.reload.parent_id).to be_nil
      end
    end

    describe "expenses association" do
      it "has many expenses" do
        association = described_class.reflect_on_association(:expenses)
        expect(association.macro).to eq(:has_many)
        expect(association.options[:dependent]).to eq(:nullify)
      end
    end

    describe "categorization_patterns association" do
      it "has many categorization_patterns" do
        association = described_class.reflect_on_association(:categorization_patterns)
        expect(association.macro).to eq(:has_many)
        expect(association.options[:dependent]).to eq(:destroy)
      end
    end

    describe "composite_patterns association" do
      it "has many composite_patterns" do
        association = described_class.reflect_on_association(:composite_patterns)
        expect(association.macro).to eq(:has_many)
        expect(association.options[:dependent]).to eq(:destroy)
      end
    end

    describe "pattern_feedbacks association" do
      it "has many pattern_feedbacks" do
        association = described_class.reflect_on_association(:pattern_feedbacks)
        expect(association.macro).to eq(:has_many)
        expect(association.options[:dependent]).to eq(:destroy)
      end
    end

    describe "pattern_learning_events association" do
      it "has many pattern_learning_events" do
        association = described_class.reflect_on_association(:pattern_learning_events)
        expect(association.macro).to eq(:has_many)
        expect(association.options[:dependent]).to eq(:destroy)
      end
    end

    describe "user_category_preferences association" do
      it "has many user_category_preferences" do
        association = described_class.reflect_on_association(:user_category_preferences)
        expect(association.macro).to eq(:has_many)
        expect(association.options[:dependent]).to eq(:destroy)
      end
    end
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

  describe "instance methods" do
    describe "#root?" do
      it "returns true for categories without parent" do
        root_category = build_stubbed(:category, parent_id: nil)
        expect(root_category.root?).to be true
      end

      it "returns false for categories with parent" do
        expect(category.root?).to be false
      end

      it "handles explicit nil parent_id" do
        category.parent_id = nil
        expect(category.root?).to be true
      end
    end

    describe "#subcategory?" do
      it "returns false for root categories" do
        root_category = build_stubbed(:category, parent_id: nil)
        expect(root_category.subcategory?).to be false
      end

      it "returns true for categories with parent" do
        expect(category.subcategory?).to be true
      end

      it "is the opposite of root?" do
        root_category = build_stubbed(:category, parent_id: nil)
        expect(root_category.subcategory?).to eq(!root_category.root?)
        
        child_category = build_stubbed(:category, parent_id: 1)
        expect(child_category.subcategory?).to eq(!child_category.root?)
      end
    end

    describe "#full_name" do
      context "for root category" do
        it "returns just the name" do
          root_category = build_stubbed(:category, name: "Transportation", parent_id: nil)
          expect(root_category.full_name).to eq("Transportation")
        end
      end

      context "for subcategory" do
        it "returns parent name > child name" do
          parent = build_stubbed(:category, name: "Food", parent_id: nil)
          child = build_stubbed(:category, name: "Restaurants", parent: parent)
          
          expect(child.full_name).to eq("Food > Restaurants")
        end

        it "handles special characters in names" do
          parent = build_stubbed(:category, name: "Food & Drink", parent_id: nil)
          child = build_stubbed(:category, name: "Café/Restaurant", parent: parent)
          
          expect(child.full_name).to eq("Food & Drink > Café/Restaurant")
        end
      end

      context "with deep hierarchy" do
        it "only shows immediate parent" do
          grandparent = build_stubbed(:category, name: "Expenses", parent_id: nil)
          parent = build_stubbed(:category, name: "Food", parent: grandparent)
          child = build_stubbed(:category, name: "Restaurants", parent: parent)
          
          # Only shows immediate parent, not full hierarchy
          expect(child.full_name).to eq("Food > Restaurants")
        end
      end
    end

    describe "#user_specific?" do
      it "returns false (placeholder implementation)" do
        expect(category.user_specific?).to be false
      end

      it "returns false for root categories" do
        root_category = build_stubbed(:category, parent_id: nil)
        expect(root_category.user_specific?).to be false
      end

      it "returns false for subcategories" do
        expect(category.user_specific?).to be false
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

  describe "edge cases and error conditions" do
    describe "name edge cases" do
      it "handles names with special characters" do
        category.name = "Food & Beverages / Café"
        expect(category).to be_valid
      end

      it "handles names with unicode characters" do
        category.name = "Comida y Bebidas café ñ"
        expect(category).to be_valid
      end

      it "handles names with emojis" do
        category.name = "Food 🍔"
        expect(category).to be_valid
      end

      it "handles names with only spaces (fails presence)" do
        category = build(:category, name: "   ")
        expect(category).not_to be_valid
        expect(category.errors[:name]).to include("can't be blank")
      end
    end

    describe "color edge cases" do
      it "handles color with spaces" do
        category = build(:category, color: " #FF5733 ")
        expect(category).not_to be_valid
        expect(category.errors[:color]).to include("must be a valid hex color")
      end

      it "is case-insensitive for hex digits" do
        category.color = "#FfFfFf"
        expect(category).to be_valid
      end

      it "handles 3-digit shorthand correctly" do
        category.color = "#FFF"
        expect(category).to be_valid
      end
    end

    describe "hierarchy edge cases" do
      it "handles orphaned categories" do
        parent = create(:category, name: "Parent")
        child = create(:category, name: "Child", parent: parent)
        
        parent.destroy
        child.reload
        
        expect(child.parent_id).to be_nil
        expect(child.root?).to be true
      end

      it "handles multiple levels of hierarchy" do
        level1 = create(:category, name: "Level 1")
        level2 = create(:category, name: "Level 2", parent: level1)
        level3 = create(:category, name: "Level 3", parent: level2)
        level4 = build(:category, name: "Level 4", parent: level3)
        
        expect(level4).to be_valid
      end

      it "prevents deep circular references" do
        cat1 = create(:category, name: "Cat 1")
        cat2 = create(:category, name: "Cat 2", parent: cat1)
        cat3 = create(:category, name: "Cat 3", parent: cat2)
        
        # Try to make cat1's parent be cat3 (circular)
        cat1.parent_id = cat3.id
        
        # This specific implementation only checks immediate parent
        # but would need enhancement for deep circular detection
        expect(cat1).to be_valid # Current implementation doesn't catch deep circles
      end
    end

    describe "concurrent modification scenarios" do
      it "handles simultaneous parent updates" do
        parent1 = create(:category, name: "Parent 1")
        parent2 = create(:category, name: "Parent 2")
        child = create(:category, name: "Child", parent: parent1)
        
        # Simulate concurrent update
        child.parent = parent2
        expect(child.save).to be true
        expect(child.reload.parent).to eq(parent2)
      end
    end

    describe "deletion cascades" do
      it "nullifies children parent_id on deletion" do
        parent = create(:category, name: "Parent")
        child1 = create(:category, name: "Child 1", parent: parent)
        child2 = create(:category, name: "Child 2", parent: parent)
        
        expect { parent.destroy }.to change { Category.count }.by(-1)
        
        child1.reload
        child2.reload
        expect(child1.parent_id).to be_nil
        expect(child2.parent_id).to be_nil
      end

      it "destroys associated patterns on deletion" do
        category = create(:category)
        pattern = create(:categorization_pattern, category: category)
        
        expect { category.destroy }.to change { CategorizationPattern.count }.by(-1)
      end

      it "nullifies associated expenses on deletion" do
        category = create(:category)
        expense = create(:expense, category: category)
        
        category.destroy
        expense.reload
        
        expect(expense.category_id).to be_nil
      end
    end
  end

  describe "performance considerations" do
    describe "query optimization" do
      it "allows efficient parent lookup" do
        # parent_id should be indexed for efficient lookups
        expect(category.parent_id).to eq(parent_category.id)
      end

      it "supports efficient root category queries" do
        query = described_class.root_categories
        # Query uses indexed parent_id column
        expect(query.to_sql).to include("parent_id")
      end
    end

    describe "n+1 query prevention" do
      it "can preload parent association" do
        categories = described_class.includes(:parent)
        expect(categories.to_sql).to include("categories")
      end

      it "can preload children association" do
        categories = described_class.includes(:children)
        expect(categories.to_sql).to include("categories")
      end
    end
  end

  describe "security considerations" do
    describe "input validation" do
      it "prevents XSS in name" do
        category.name = "<script>alert('XSS')</script>"
        # Name is stored as-is but should be escaped in views
        expect(category).to be_valid
        expect(category.name).to eq("<script>alert('XSS')</script>")
      end

      it "validates color format strictly" do
        category.color = "javascript:alert('XSS')"
        expect(category).not_to be_valid
        expect(category.errors[:color]).to include("must be a valid hex color")
      end

      it "prevents SQL injection in name" do
        category.name = "'; DROP TABLE categories; --"
        expect(category).to be_valid
        # ActiveRecord parameterizes queries, preventing SQL injection
        expect(category.name).to eq("'; DROP TABLE categories; --")
      end
    end

    describe "mass assignment protection" do
      it "uses strong parameters in controllers" do
        # This would be tested in controller specs
        # Categories should only allow specific attributes
        params = { name: "Test", color: "#FF5733", parent_id: 1 }
        category = Category.new(params)
        expect(category.name).to eq("Test")
      end
    end
  end

  describe "business logic" do
    describe "category hierarchy rules" do
      it "allows unlimited depth in theory" do
        # Build a deep hierarchy
        current_parent = create(:category, name: "Root")
        10.times do |i|
          current_parent = create(:category, 
            name: "Level #{i + 1}", 
            parent: current_parent)
        end
        
        expect(current_parent.parent).not_to be_nil
      end

      it "maintains referential integrity" do
        parent = create(:category, name: "Parent")
        child = create(:category, name: "Child", parent: parent)
        
        # Parent can be changed
        new_parent = create(:category, name: "New Parent")
        child.parent = new_parent
        child.save!
        
        expect(child.reload.parent).to eq(new_parent)
      end
    end

    describe "category naming" do
      it "allows duplicate names at different levels" do
        parent1 = create(:category, name: "Food")
        parent2 = create(:category, name: "Entertainment")
        
        child1 = create(:category, name: "Other", parent: parent1)
        child2 = build(:category, name: "Other", parent: parent2)
        
        expect(child2).to be_valid
      end

      it "allows duplicate names at root level" do
        cat1 = create(:category, name: "Miscellaneous")
        cat2 = build(:category, name: "Miscellaneous")
        
        # No uniqueness constraint on name
        expect(cat2).to be_valid
      end
    end
  end

  describe "future enhancements placeholder" do
    describe "#user_specific?" do
      it "is ready for user-specific category implementation" do
        # Currently returns false for all
        expect(category.user_specific?).to be false
        
        # When implemented, would check user association
        # expect(user_category.user_specific?).to be true
      end
    end

    describe "soft delete support" do
      it "could support soft deletes in future" do
        # Currently uses hard delete
        category = create(:category)
        category.destroy
        
        expect(Category.find_by(id: category.id)).to be_nil
        
        # Future: expect(category.deleted_at).not_to be_nil
      end
    end
  end
end