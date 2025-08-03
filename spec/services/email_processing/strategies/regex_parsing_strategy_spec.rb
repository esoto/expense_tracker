require 'rails_helper'

RSpec.describe EmailProcessing::Strategies::Regex do
  let(:parsing_rule) do
    create(:parsing_rule,
      bank_name: 'Banco Nacional',
      amount_pattern: 'Monto: (?:₡|CRC)?\s?([0-9,.]+)',
      date_pattern: 'Fecha: ([0-9]{2}/[0-9]{2}/[0-9]{4})',
      merchant_pattern: 'Comercio: (.+)',
      description_pattern: 'Descripción: (.+)'
    )
  end

  let(:strategy) { described_class.new(parsing_rule) }

  let(:email_content) do
    <<~EMAIL
      Estimado cliente,

      Se ha realizado una transacción con su tarjeta:
      Fecha: 15/08/2024
      Monto: ₡25,000.50
      Comercio: SUPER MERCADO CENTRAL
      Descripción: Compra de alimentos

      Gracias por usar nuestros servicios.
    EMAIL
  end

  describe '#initialize' do
    it 'sets the parsing rule' do
      expect(strategy.instance_variable_get(:@parsing_rule)).to eq(parsing_rule)
    end
  end

  describe '#parse_email' do
    it 'extracts all data from email content' do
      result = strategy.parse_email(email_content)

      expect(result[:amount]).to eq(BigDecimal('25000.50'))
      expect(result[:transaction_date]).to eq(Date.new(2024, 8, 15))
      expect(result[:merchant_name]).to eq('SUPER MERCADO CENTRAL')
      expect(result[:description]).to eq('Compra de alimentos')
    end

    it 'handles missing optional fields gracefully' do
      rule_without_optionals = create(:parsing_rule,
        bank_name: 'Simple Bank',
        amount_pattern: 'Amount: ([0-9,.]+)',
        date_pattern: 'Date: ([0-9]{2}/[0-9]{2}/[0-9]{4})',
        merchant_pattern: nil,
        description_pattern: nil
      )
      strategy = described_class.new(rule_without_optionals)

      content = "Amount: 1000.00\nDate: 15/08/2024"
      result = strategy.parse_email(content)

      expect(result[:amount]).to eq(BigDecimal('1000.00'))
      expect(result[:transaction_date]).to eq(Date.new(2024, 8, 15))
      expect(result[:merchant_name]).to be_nil
      expect(result[:description]).to be_nil
    end

    it 'handles missing required fields' do
      content = "No amount or date here"
      result = strategy.parse_email(content)

      expect(result[:amount]).to be_nil
      expect(result[:transaction_date]).to be_nil
    end

    context 'amount extraction' do
      it 'handles different currency symbols' do
        patterns_and_content = [
          { pattern: 'Amount: \$([0-9,.]+)', content: 'Amount: $1,234.56', expected: BigDecimal('1234.56') },
          { pattern: 'Monto: €([0-9,.]+)', content: 'Monto: €999.99', expected: BigDecimal('999.99') },
          { pattern: 'Total: ([0-9,.]+)', content: 'Total: 5000', expected: BigDecimal('5000') }
        ]

        patterns_and_content.each do |test_case|
          rule = create(:parsing_rule,
            amount_pattern: test_case[:pattern],
            date_pattern: 'Date: ([0-9]{2}/[0-9]{2}/[0-9]{4})'
          )
          strategy = described_class.new(rule)

          content = "#{test_case[:content]}\nDate: 01/01/2024"
          result = strategy.parse_email(content)

          expect(result[:amount]).to eq(test_case[:expected])
        end
      end

      it 'handles invalid amount strings' do
        rule = create(:parsing_rule,
          amount_pattern: 'Amount: ([A-Z]+)',
          date_pattern: 'Date: ([0-9]{2}/[0-9]{2}/[0-9]{4})'
        )
        strategy = described_class.new(rule)

        content = "Amount: INVALID\nDate: 01/01/2024"
        result = strategy.parse_email(content)

        expect(result[:amount]).to be_nil
      end
    end

    context 'date extraction' do
      it 'handles different date formats' do
        date_formats = [
          { pattern: 'Date: ([0-9]{2}/[0-9]{2}/[0-9]{4})', content: 'Date: 15/08/2024', expected: Date.new(2024, 8, 15) },
          { pattern: 'Fecha: ([0-9]{2}-[0-9]{2}-[0-9]{4})', content: 'Fecha: 15-08-2024', expected: Date.new(2024, 8, 15) },
          { pattern: 'Date: ([A-Za-z]{3} [0-9]{1,2}, [0-9]{4})', content: 'Date: Aug 15, 2024', expected: Date.new(2024, 8, 15) }
        ]

        date_formats.each do |test_case|
          rule = create(:parsing_rule,
            amount_pattern: 'Amount: ([0-9,.]+)',
            date_pattern: test_case[:pattern]
          )
          strategy = described_class.new(rule)

          content = "Amount: 100.00\n#{test_case[:content]}"
          result = strategy.parse_email(content)

          expect(result[:transaction_date]).to eq(test_case[:expected])
        end
      end

      it 'handles Spanish month abbreviations' do
        rule = create(:parsing_rule,
          amount_pattern: 'Amount: ([0-9,.]+)',
          date_pattern: 'Fecha: ([A-Za-z]{3} [0-9]{1,2}, [0-9]{4})'
        )
        strategy = described_class.new(rule)

        content = "Amount: 100.00\nFecha: Ago 15, 2024"
        result = strategy.parse_email(content)

        expect(result[:transaction_date]).to eq(Date.new(2024, 8, 15))
      end

      it 'handles invalid date strings' do
        rule = create(:parsing_rule,
          amount_pattern: 'Amount: ([0-9,.]+)',
          date_pattern: 'Date: ([A-Z]+)'
        )
        strategy = described_class.new(rule)

        content = "Amount: 100.00\nDate: INVALID"
        result = strategy.parse_email(content)

        expect(result[:transaction_date]).to be_nil
      end
    end

    context 'case insensitive matching' do
      it 'matches patterns regardless of case' do
        content_upper = email_content.upcase
        result = strategy.parse_email(content_upper)

        expect(result[:amount]).to eq(BigDecimal('25000.50'))
        expect(result[:transaction_date]).to eq(Date.new(2024, 8, 15))
        expect(result[:merchant_name]).to eq('SUPER MERCADO CENTRAL')
        expect(result[:description]).to eq('COMPRA DE ALIMENTOS')
      end
    end
  end

  describe '#can_parse?' do
    it 'returns true when required patterns match' do
      expect(strategy.can_parse?(email_content)).to be true
    end

    it 'returns false when amount pattern does not match' do
      content = "No amount here\nFecha: 15/08/2024"
      expect(strategy.can_parse?(content)).to be false
    end

    it 'returns false when date pattern does not match' do
      content = "Monto: ₡1000\nNo date here"
      expect(strategy.can_parse?(content)).to be false
    end

    it 'returns false for invalid regex patterns' do
      invalid_rule = create(:parsing_rule,
        amount_pattern: '[invalid regex',
        date_pattern: 'Date: ([0-9]{2}/[0-9]{2}/[0-9]{4})'
      )
      strategy = described_class.new(invalid_rule)

      expect(strategy.can_parse?(email_content)).to be false
    end

    it 'returns false for nil content' do
      expect(strategy.can_parse?(nil)).to be false
    end

    it 'returns false for empty content' do
      expect(strategy.can_parse?('')).to be false
    end
  end

  describe 'private methods' do
    describe '#extract_amount' do
      it 'cleans and converts amount strings' do
        test_cases = [
          { input: '₡1,234.56', expected: BigDecimal('1234.56') },
          { input: '$999.99', expected: BigDecimal('999.99') },
          { input: '1 000.50', expected: BigDecimal('1000.50') },
          { input: '5000', expected: BigDecimal('5000') }
        ]

        test_cases.each do |test_case|
          result = strategy.send(:extract_amount, test_case[:input])
          expect(result).to eq(test_case[:expected])
        end
      end

      it 'returns nil for invalid amounts' do
        invalid_amounts = [ 'invalid', '', nil, 'abc123' ]

        invalid_amounts.each do |amount|
          result = strategy.send(:extract_amount, amount)
          expect(result).to be_nil
        end
      end
    end

    describe '#parse_date' do
      it 'parses various date formats' do
        test_cases = [
          { input: '15/08/2024', expected: Date.new(2024, 8, 15) },
          { input: '15-08-2024', expected: Date.new(2024, 8, 15) },
          { input: '2024-08-15', expected: Date.new(2024, 8, 15) },
          { input: 'Aug 15, 2024', expected: Date.new(2024, 8, 15) },
          { input: 'Ago 15, 2024', expected: Date.new(2024, 8, 15) }  # Spanish month
        ]

        test_cases.each do |test_case|
          result = strategy.send(:parse_date, test_case[:input])
          expect(result).to eq(test_case[:expected])
        end
      end

      it 'returns nil for invalid dates' do
        invalid_dates = [ 'invalid', '', '32/13/2024', 'not a date' ]

        invalid_dates.each do |date|
          result = strategy.send(:parse_date, date)
          expect(result).to be_nil
        end
      end

      it 'handles whitespace in date strings' do
        result = strategy.send(:parse_date, '  15/08/2024  ')
        expect(result).to eq(Date.new(2024, 8, 15))
      end
    end
  end
end
