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
      expect(category.errors[:name]).to include("no puede estar en blanco")
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

  describe '#display_name', :unit do
    it 'returns name when i18n_key is nil' do
      category = Category.new(name: 'Custom Category', i18n_key: nil)
      expect(category.display_name).to eq('Custom Category')
    end

    it 'returns translated name when i18n_key is present' do
      category = Category.new(name: 'Alimentación', i18n_key: 'food')
      I18n.with_locale(:en) do
        expect(category.display_name).to eq('Food')
      end
    end

    it 'returns Spanish translation with es locale' do
      category = Category.new(name: 'Food', i18n_key: 'food')
      I18n.with_locale(:es) do
        expect(category.display_name).to eq('Alimentación')
      end
    end

    it 'falls back to name when translation key is missing' do
      category = Category.new(name: 'Fallback Name', i18n_key: 'nonexistent_key')
      expect(category.display_name).to eq('Fallback Name')
    end

    it 'returns name when i18n_key is blank string' do
      category = Category.new(name: 'Blank Key', i18n_key: '')
      expect(category.display_name).to eq('Blank Key')
    end
  end

  describe '#full_name with i18n', :unit do
    it 'uses display_name for root category' do
      category = Category.new(name: 'Alimentación', i18n_key: 'food')
      I18n.with_locale(:en) do
        expect(category.full_name).to eq('Food')
      end
    end

    it 'uses display_name for parent and child' do
      parent = create(:category, name: 'Alimentación', i18n_key: 'food')
      child = Category.new(name: 'Restaurantes', i18n_key: 'restaurants', parent: parent)
      I18n.with_locale(:en) do
        expect(child.full_name).to eq('Food > Restaurants')
      end
    end
  end

  describe 'validations edge cases', integration: true do
    it 'validates name length maximum' do
      long_name = 'a' * 256
      category = build(:category, name: long_name)
      expect(category).not_to be_valid
      expect(category.errors[:name]).to include('es demasiado largo (255 caracteres máximo)')
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

  describe 'user ownership', integration: true do
    it { should belong_to(:user).optional }

    describe 'shared vs personal' do
      let(:shared) { create(:category, name: 'Food', user: nil) }
      let(:user)   { create(:user) }
      let(:personal) { create(:category, name: 'Home Food', user: user) }

      it 'treats user_id IS NULL as a shared category' do
        expect(shared.user_id).to be_nil
        expect(shared).to be_shared
        expect(shared).not_to be_personal
      end

      it 'treats a category with a user_id as personal' do
        expect(personal).to be_personal
        expect(personal).not_to be_shared
        expect(personal.user).to eq(user)
      end
    end

    describe '.visible_to' do
      let(:user_a) { create(:user, email: 'a@example.com') }
      let(:user_b) { create(:user, email: 'b@example.com') }
      let!(:shared)     { create(:category, name: 'Food', user: nil) }
      let!(:a_personal) { create(:category, name: 'Home Food', user: user_a) }
      let!(:b_personal) { create(:category, name: 'Out Food', user: user_b) }

      it "returns shared plus the user's own personal categories" do
        visible = Category.visible_to(user_a)
        expect(visible).to include(shared, a_personal)
        expect(visible).not_to include(b_personal)
      end

      it "excludes other users' personal categories" do
        expect(Category.visible_to(user_b)).not_to include(a_personal)
      end
    end

    describe 'tree rules across ownership' do
      let(:user_a) { create(:user, email: 'a@example.com') }
      let(:user_b) { create(:user, email: 'b@example.com') }
      let(:shared_parent) { create(:category, name: 'Food', user: nil) }

      it 'allows a personal category parented under a shared category' do
        personal = build(:category, name: 'Out Food', user: user_a, parent: shared_parent)
        expect(personal).to be_valid
      end

      it 'allows a personal category with no parent (own top-level branch)' do
        personal = build(:category, name: 'Home Food', user: user_a, parent: nil)
        expect(personal).to be_valid
      end

      it "rejects a personal category parenting under another user's personal category" do
        b_personal = create(:category, name: 'B Out Food', user: user_b)
        invalid = build(:category, name: 'A Child', user: user_a, parent: b_personal)
        expect(invalid).not_to be_valid
        expect(invalid.errors[:parent]).to include('must belong to the same user or be shared')
      end

      it 'rejects a shared category being parented under a personal category' do
        a_personal = create(:category, name: 'A Branch', user: user_a)
        invalid = build(:category, name: 'New Shared', user: nil, parent: a_personal)
        expect(invalid).not_to be_valid
        expect(invalid.errors[:parent]).to include('shared category cannot have a personal parent')
      end
    end

    describe 'unique name per user scope' do
      let(:user_a) { create(:user, email: 'a@example.com') }
      let(:user_b) { create(:user, email: 'b@example.com') }

      it 'allows two users to each own a category with the same name' do
        create(:category, name: 'Out Food', user: user_a)
        duplicate_for_b = build(:category, name: 'Out Food', user: user_b)
        expect(duplicate_for_b).to be_valid
      end

      it 'prevents the same user from having two personal categories with the same name' do
        create(:category, name: 'Out Food', user: user_a)
        second = build(:category, name: 'Out Food', user: user_a)
        expect(second).not_to be_valid
      end

      it 'prevents case-insensitive duplicates for the same user' do
        create(:category, name: 'Out Food', user: user_a)
        mixed_case = build(:category, name: 'out food', user: user_a)
        expect(mixed_case).not_to be_valid
        expect(mixed_case.errors[:name]).to be_present
      end

      it 'allows two shared categories to share a name (no uniqueness constraint)' do
        create(:category, name: 'Food', user: nil)
        duplicate_shared = build(:category, name: 'Food', user: nil)
        expect(duplicate_shared).to be_valid
      end
    end

    describe 'update-path tree rule invariants' do
      let(:user_a) { create(:user, email: 'a@example.com') }
      let(:user_b) { create(:user, email: 'b@example.com') }

      it 'rejects reparenting a shared category under a personal one via update' do
        shared_child = create(:category, name: 'Shared Child', user: nil)
        personal = create(:category, name: 'A Branch', user: user_a)
        shared_child.parent = personal
        expect(shared_child).not_to be_valid
        expect(shared_child.errors[:parent]).to include('shared category cannot have a personal parent')
      end

      it "rejects reparenting a personal category under another user's personal" do
        a_child = create(:category, name: 'A Child', user: user_a)
        b_personal = create(:category, name: 'B Branch', user: user_b)
        a_child.parent = b_personal
        expect(a_child).not_to be_valid
        expect(a_child.errors[:parent]).to include('must belong to the same user or be shared')
      end

      it 'forbids changing user_id while the category has children (would orphan invariants)' do
        parent = create(:category, name: 'Food', user: nil)
        create(:category, name: 'Out Food', user: user_a, parent: parent)

        parent.user = user_a
        expect(parent).not_to be_valid
        expect(parent.errors[:user_id]).to include('cannot change while the category has children')
      end

      it 'permits changing user_id on a childless category' do
        childless = create(:category, name: 'Tmp', user: user_a)
        childless.user = nil
        expect(childless).to be_valid
      end
    end
  end
end
