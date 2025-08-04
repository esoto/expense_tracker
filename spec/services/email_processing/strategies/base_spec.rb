require 'rails_helper'

RSpec.describe EmailProcessing::Strategies::Base do
  let(:parsing_rule) { create(:parsing_rule) }
  let(:strategy) { described_class.new(parsing_rule) }

  describe '#initialize' do
    it 'stores the parsing rule' do
      expect(strategy.send(:parsing_rule)).to eq(parsing_rule)
    end
  end

  describe '#parse_email' do
    it 'raises NotImplementedError' do
      expect { strategy.parse_email('email content') }.to raise_error(
        NotImplementedError,
        "Subclasses must implement parse_email method"
      )
    end
  end

  describe '#can_parse?' do
    it 'returns true for any content' do
      expect(strategy.can_parse?('any content')).to be true
    end

    it 'returns true for empty content' do
      expect(strategy.can_parse?('')).to be true
    end

    it 'returns true for nil content' do
      expect(strategy.can_parse?(nil)).to be true
    end
  end

  describe 'inheritance' do
    let(:subclass) do
      Class.new(described_class) do
        def parse_email(email_content)
          { parsed: true, content: email_content }
        end
      end
    end

    it 'allows subclasses to implement parse_email' do
      subclass_instance = subclass.new(parsing_rule)
      result = subclass_instance.parse_email('test content')
      expect(result).to eq({ parsed: true, content: 'test content' })
    end

    it 'provides access to parsing_rule in subclasses' do
      subclass_with_rule_access = Class.new(described_class) do
        def rule_bank_name
          parsing_rule.bank_name
        end
      end

      instance = subclass_with_rule_access.new(parsing_rule)
      expect(instance.rule_bank_name).to eq(parsing_rule.bank_name)
    end
  end
end
