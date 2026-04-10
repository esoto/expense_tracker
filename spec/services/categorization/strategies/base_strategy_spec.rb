# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Strategies::BaseStrategy, type: :service, unit: true do
  subject(:strategy) { described_class.new }

  describe "#call" do
    it "raises NotImplementedError" do
      expense = build(:expense)
      expect { strategy.call(expense) }.to raise_error(NotImplementedError, /must be implemented/)
    end
  end

  describe "#layer_name" do
    it "raises NotImplementedError" do
      expect { strategy.layer_name }.to raise_error(NotImplementedError, /must be implemented/)
    end
  end
end
