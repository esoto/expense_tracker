require 'rails_helper'

RSpec.describe ApplicationRecord, type: :model, unit: true do
  describe 'abstract class', unit: true do
    it 'is an abstract class' do
      expect(ApplicationRecord.abstract_class?).to be true
    end

    it 'is the primary abstract class' do
      expect(ApplicationRecord.primary_class?).to be true
    end
  end

  describe 'inheritance', unit: true do
    let(:test_model_class) do
      Class.new(ApplicationRecord) do
        self.table_name = 'expenses' # Use existing table for testing
      end
    end

    it 'allows models to inherit from ApplicationRecord' do
      expect(test_model_class.superclass).to eq(ApplicationRecord)
    end

    it 'provides ActiveRecord functionality to subclasses' do
      expect(test_model_class.ancestors).to include(ActiveRecord::Base)
    end

    it 'allows subclasses to perform database operations' do
      expect(test_model_class).to respond_to(:all)
      expect(test_model_class).to respond_to(:find)
      expect(test_model_class).to respond_to(:create)
    end
  end
end
