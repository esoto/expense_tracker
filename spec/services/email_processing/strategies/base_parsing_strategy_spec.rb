require 'rails_helper'

RSpec.describe Services::EmailProcessing::Strategies::Base, unit: true do
  let(:parsing_rule) { instance_double(ParsingRule, bank_name: 'Test Bank') }
  let(:strategy) { described_class.new(parsing_rule) }

  describe '#initialize', unit: true do
    it 'sets the parsing rule' do
      expect(strategy.instance_variable_get(:@parsing_rule)).to eq(parsing_rule)
    end
  end

  describe '#parse_email', unit: true do
    it 'raises NotImplementedError' do
      expect { strategy.parse_email('test content') }.to raise_error(NotImplementedError, 'Subclasses must implement parse_email method')
    end
  end

  describe '#can_parse?', unit: true do
    it 'returns true by default' do
      expect(strategy.can_parse?('any content')).to be true
    end

    it 'accepts nil content' do
      expect(strategy.can_parse?(nil)).to be true
    end

    it 'accepts empty content' do
      expect(strategy.can_parse?('')).to be true
    end
  end
end
