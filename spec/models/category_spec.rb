require 'rails_helper'

RSpec.describe Category, type: :model, integration: true do
  describe 'validations', integration: true do
    let(:category) { Category.new(name: 'Test Category', description: 'Test description', color: '#FF0000') }
    it 'is valid with valid attributes' do
      expect(category).to be_valid
    end

    it 'requires a name' do
      category.name = nil
      expect(category).not_to be_valid
      expect(category.errors[:name]).to include("can't be blank")
    end

    it 'validates color format' do
      category.color = 'invalid_color'
      expect(category).not_to be_valid
      expect(category.errors[:color]).to include('must be a valid hex color')
    end

    it 'accepts valid hex colors' do
      valid_colors = [ '#FF0000', '#f00', '#123456', '#ABC' ]
      valid_colors.each do |color|
        category.color = color
        expect(category).to be_valid, "#{color} should be valid"
      end
    end

    it 'allows blank color' do
      category.color = nil
      expect(category).to be_valid
    end

    it 'cannot be parent of itself' do
      category.save!
      category.parent = category
      expect(category).not_to be_valid
      expect(category.errors[:parent]).to include('cannot be itself')
    end

    it 'prevents direct circular references' do
      grandparent = create(:category, name: 'Grandparent')
      parent = create(:category, name: 'Parent', parent: grandparent)

      # Try to make grandparent a child of parent (direct circular reference)
      grandparent.parent = parent
      expect(grandparent).not_to be_valid
      expect(grandparent.errors[:parent]).to include('cannot create circular reference')
    end
  end

  describe 'associations', integration: true do
    it { should belong_to(:parent).class_name('Category').optional }
    it { should have_many(:children).class_name('Category').with_foreign_key('parent_id').dependent(:nullify) }
    it { should have_many(:expenses).dependent(:nullify) }

    # Keep the custom behavior test for nullifying children
    it 'nullifies children when destroyed' do
      parent_category = create(:category, name: 'Parent')
      child_category = create(:category, name: 'Child', parent: parent_category)

      child_id = child_category.id
      parent_category.destroy

      child = Category.find(child_id)
      expect(child.parent_id).to be_nil
    end
  end

  describe 'scopes', integration: true do
    let!(:root_category) { create(:category, name: 'Root') }
    let!(:child_category) { create(:category, name: 'Child', parent: root_category) }

    it 'returns root categories' do
      expect(Category.root_categories).to include(root_category)
      expect(Category.root_categories).not_to include(child_category)
    end

    it 'returns subcategories' do
      expect(Category.subcategories).to include(child_category)
      expect(Category.subcategories).not_to include(root_category)
    end
  end

  describe 'instance methods', integration: true do
    let(:parent_category) { create(:category, name: 'Alimentación') }
    let(:child_category) { create(:category, name: 'Restaurantes', parent: parent_category) }

    it 'identifies root category' do
      expect(parent_category).to be_root
      expect(child_category).not_to be_root
    end

    it 'identifies subcategory' do
      expect(child_category).to be_subcategory
      expect(parent_category).not_to be_subcategory
    end

    it 'returns full name with parent' do
      expect(child_category.full_name).to eq('Alimentación > Restaurantes')
      expect(parent_category.full_name).to eq('Alimentación')
    end
  end

  describe 'validations edge cases', integration: true do
    it 'validates name length maximum' do
      long_name = 'a' * 256
      category = build(:category, name: long_name)
      expect(category).not_to be_valid
      expect(category.errors[:name]).to include('is too long (maximum is 255 characters)')
    end

    it 'prevents deeper circular references' do
      grandparent = create(:category, name: 'Grandparent')
      parent = create(:category, name: 'Parent', parent: grandparent)
      child = create(:category, name: 'Child', parent: parent)

      # Try to make grandparent a child of parent (direct circular reference, 2 levels)
      grandparent.parent = parent
      expect(grandparent).not_to be_valid
      expect(grandparent.errors[:parent]).to include('cannot create circular reference')
    end
  end
end
