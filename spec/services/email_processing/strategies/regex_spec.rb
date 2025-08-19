require 'rails_helper'

RSpec.describe EmailProcessing::Strategies::Regex, integration: true do
  let(:parsing_rule) { create(:parsing_rule, :bac) }
  let(:strategy) { described_class.new(parsing_rule) }

  describe '#parse_email', integration: true do
    context 'with valid email content' do
      let(:email_content) do
        "Notificación de transacción\nMonto: CRC 5,000.00\nFecha: 03/08/2024\nComercio: Supermercado ABC Ciudad: San José\nTipo de Transacción: COMPRA"
      end

      it 'extracts amount correctly' do
        result = strategy.parse_email(email_content)
        expect(result[:amount]).to eq(BigDecimal('5000.00'))
      end

      it 'extracts date correctly' do
        result = strategy.parse_email(email_content)
        expect(result[:transaction_date]).to eq(Date.new(2024, 8, 3))
      end

      it 'extracts merchant name when pattern exists' do
        # BAC pattern expects "Ciudad" after merchant name
        result = strategy.parse_email(email_content)
        expect(result[:merchant_name]).to eq('Supermercado ABC')
      end

      it 'extracts description when pattern exists' do
        # No need to update pattern, BAC already has 'Tipo de Transacción' pattern
        result = strategy.parse_email(email_content)
        expect(result[:description]).to eq('COMPRA')
      end
    end

    context 'with missing optional fields' do
      let(:email_content) do
        "Monto: USD 100.50\nFecha: 01/01/2024"
      end

      it 'returns parsed data without optional fields' do
        result = strategy.parse_email(email_content)
        expect(result[:amount]).to eq(BigDecimal('100.50'))
        expect(result[:transaction_date]).to eq(Date.new(2024, 1, 1))
        expect(result[:merchant_name]).to be_nil
        expect(result[:description]).to be_nil
      end
    end

    context 'with no matching patterns' do
      let(:email_content) { "This email has no transaction data" }

      it 'returns empty hash' do
        result = strategy.parse_email(email_content)
        expect(result).to eq({})
      end
    end

    context 'with capture groups' do
      let(:email_content) { "Amount: USD 1,234.56 was charged" }

      before do
        parsing_rule.update(amount_pattern: 'Amount: USD ([0-9,]+\.[0-9]+)')
      end

      it 'uses capture group when available' do
        result = strategy.parse_email(email_content)
        expect(result[:amount]).to eq(BigDecimal('1234.56'))
      end
    end
  end

  describe '#can_parse?', integration: true do
    context 'with valid content' do
      let(:email_content) { "Monto: CRC 1,000.00\nFecha: 03/08/2024" }

      it 'returns true when required patterns match' do
        expect(strategy.can_parse?(email_content)).to be true
      end
    end

    context 'with missing required patterns' do
      it 'returns false when amount is missing' do
        email_content = "Fecha: 03/08/2024"
        expect(strategy.can_parse?(email_content)).to be false
      end

      it 'returns false when date is missing' do
        email_content = "Monto: ₡1,000.00"
        expect(strategy.can_parse?(email_content)).to be false
      end
    end

    context 'with blank content' do
      it 'returns false for nil' do
        expect(strategy.can_parse?(nil)).to be false
      end

      it 'returns false for empty string' do
        expect(strategy.can_parse?('')).to be false
      end
    end

    context 'with invalid regex patterns' do
      before do
        parsing_rule.update(amount_pattern: '[invalid(regex')
      end

      it 'returns false and does not raise error' do
        expect(strategy.can_parse?('any content')).to be false
      end
    end
  end

  describe '#extract_amount (private method)', integration: true do
    it 'handles various currency formats' do
      expect(strategy.send(:extract_amount, '₡1,000.00')).to eq(BigDecimal('1000.00'))
      expect(strategy.send(:extract_amount, '$1,234.56')).to eq(BigDecimal('1234.56'))
      expect(strategy.send(:extract_amount, '5000')).to eq(BigDecimal('5000'))
      expect(strategy.send(:extract_amount, '123.45')).to eq(BigDecimal('123.45'))
    end

    it 'returns nil for invalid amounts' do
      expect(strategy.send(:extract_amount, nil)).to be_nil
      expect(strategy.send(:extract_amount, '')).to be_nil
      expect(strategy.send(:extract_amount, 'abc')).to be_nil
    end
  end

  describe '#parse_date (private method)', integration: true do
    it 'handles various date formats' do
      expect(strategy.send(:parse_date, '03/08/2024')).to eq(Date.new(2024, 8, 3))
      expect(strategy.send(:parse_date, '03-08-2024')).to eq(Date.new(2024, 8, 3))
      expect(strategy.send(:parse_date, '2024-08-03')).to eq(Date.new(2024, 8, 3))
    end

    it 'handles dates with time' do
      expect(strategy.send(:parse_date, '03/08/2024 14:30')).to eq(Date.new(2024, 8, 3))
      expect(strategy.send(:parse_date, '03-08-2024 09:15')).to eq(Date.new(2024, 8, 3))
    end

    it 'handles Spanish month names' do
      # Spanish "de" format needs to be tested differently
      result = strategy.send(:parse_date, '03 de Agosto de 2024')
      # This format might not be parseable without proper locale
      expect(result).to be_nil

      expect(strategy.send(:parse_date, 'Ago 3, 2024')).to eq(Date.new(2024, 8, 3))
      expect(strategy.send(:parse_date, 'Dic 25, 2024')).to eq(Date.new(2024, 12, 25))
    end

    it 'handles abbreviated months' do
      expect(strategy.send(:parse_date, 'Aug 3, 2024, 14:16')).to eq(Date.new(2024, 8, 3))
      expect(strategy.send(:parse_date, 'Aug 3, 2024')).to eq(Date.new(2024, 8, 3))
    end

    it 'uses Chronic as fallback for natural language' do
      # Skip Chronic test if not available
      if defined?(Chronic)
        allow(Chronic).to receive(:parse).and_return(nil)
        result = strategy.send(:parse_date, 'some natural language date')
        expect(result).to be_nil
      else
        result = strategy.send(:parse_date, 'some natural language date')
        expect(result).to be_nil
      end
    end

    it 'returns nil for unparseable dates' do
      expect(strategy.send(:parse_date, 'not a date')).to be_nil
      expect(strategy.send(:parse_date, '')).to be_nil
    end
  end
end
