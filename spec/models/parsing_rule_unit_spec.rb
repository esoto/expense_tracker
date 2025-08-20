require 'rails_helper'

RSpec.describe ParsingRule, type: :model, unit: true do
  # Use build_stubbed for true unit tests
  let(:parsing_rule) { build_stubbed(:parsing_rule) }

  describe 'validations' do
    context 'bank_name validation' do
      it 'requires presence of bank_name' do
        parsing_rule = build(:parsing_rule, bank_name: nil)
        expect(parsing_rule).not_to be_valid
        expect(parsing_rule.errors[:bank_name]).to include("can't be blank")
      end

      it 'accepts any non-empty bank_name' do
        bank_names = ['BAC', 'BCR', 'Scotiabank', 'Custom Bank', '123']
        bank_names.each do |bank_name|
          parsing_rule = build(:parsing_rule, bank_name: bank_name)
          expect(parsing_rule).to be_valid, "Bank name '#{bank_name}' should be valid"
        end
      end

      it 'rejects empty string bank_name' do
        parsing_rule = build(:parsing_rule, bank_name: '')
        expect(parsing_rule).not_to be_valid
        expect(parsing_rule.errors[:bank_name]).to include("can't be blank")
      end
    end

    context 'amount_pattern validation' do
      it 'requires presence of amount_pattern' do
        parsing_rule = build(:parsing_rule, amount_pattern: nil)
        expect(parsing_rule).not_to be_valid
        expect(parsing_rule.errors[:amount_pattern]).to include("can't be blank")
      end

      it 'accepts valid regex patterns' do
        patterns = [
          '\\d+\\.\\d{2}',
          'Monto:[\\s]*([\\d,]+\\.\\d{2})',
          '[0-9]+',
          '.*'
        ]
        patterns.each do |pattern|
          parsing_rule = build(:parsing_rule, amount_pattern: pattern)
          expect(parsing_rule).to be_valid, "Pattern '#{pattern}' should be valid"
        end
      end

      it 'rejects empty string amount_pattern' do
        parsing_rule = build(:parsing_rule, amount_pattern: '')
        expect(parsing_rule).not_to be_valid
        expect(parsing_rule.errors[:amount_pattern]).to include("can't be blank")
      end
    end

    context 'date_pattern validation' do
      it 'requires presence of date_pattern' do
        parsing_rule = build(:parsing_rule, date_pattern: nil)
        expect(parsing_rule).not_to be_valid
        expect(parsing_rule.errors[:date_pattern]).to include("can't be blank")
      end

      it 'accepts valid regex patterns' do
        patterns = [
          '\\d{2}/\\d{2}/\\d{4}',
          'Fecha:[\\s]*(.+)',
          '[A-Za-z]+ \\d+, \\d{4}',
          '.*'
        ]
        patterns.each do |pattern|
          parsing_rule = build(:parsing_rule, date_pattern: pattern)
          expect(parsing_rule).to be_valid, "Pattern '#{pattern}' should be valid"
        end
      end

      it 'rejects empty string date_pattern' do
        parsing_rule = build(:parsing_rule, date_pattern: '')
        expect(parsing_rule).not_to be_valid
        expect(parsing_rule.errors[:date_pattern]).to include("can't be blank")
      end
    end

    context 'active validation' do
      it 'validates active as boolean' do
        [true, false].each do |value|
          parsing_rule = build(:parsing_rule, active: value)
          expect(parsing_rule).to be_valid
        end
      end

      it 'rejects nil for active' do
        parsing_rule = build(:parsing_rule, active: nil)
        expect(parsing_rule).not_to be_valid
        expect(parsing_rule.errors[:active]).to include("is not included in the list")
      end
    end

    context 'optional pattern validations' do
      it 'allows nil merchant_pattern' do
        parsing_rule = build(:parsing_rule, merchant_pattern: nil)
        expect(parsing_rule).to be_valid
      end

      it 'allows nil description_pattern' do
        parsing_rule = build(:parsing_rule, description_pattern: nil)
        expect(parsing_rule).to be_valid
      end

      it 'allows empty merchant_pattern' do
        parsing_rule = build(:parsing_rule, merchant_pattern: '')
        expect(parsing_rule).to be_valid
      end

      it 'allows empty description_pattern' do
        parsing_rule = build(:parsing_rule, description_pattern: '')
        expect(parsing_rule).to be_valid
      end
    end
  end

  describe 'associations' do
    it 'defines has_many email_accounts with custom keys' do
      association = ParsingRule.reflect_on_association(:email_accounts)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:primary_key]).to eq(:bank_name)
      expect(association.options[:foreign_key]).to eq(:bank_name)
    end
  end

  describe 'scopes' do
    describe '.active' do
      it 'filters by active status' do
        expect(ParsingRule.active.to_sql).to include('"parsing_rules"."active" = ')
      end
    end

    describe '.for_bank' do
      it 'filters by bank_name' do
        sql = ParsingRule.for_bank('BAC').to_sql
        expect(sql).to include('bank_name')
        expect(sql).to include('BAC')
      end
    end
  end

  describe '#parse_email' do
    let(:parsing_rule) do
      build_stubbed(:parsing_rule,
        amount_pattern: 'Monto:[\\s]*([\\d,]+\\.\\d{2})',
        date_pattern: 'Fecha:[\\s]*(.+?)(?=\\n|$)',
        merchant_pattern: 'Comercio:[\\s]*(.+?)(?=\\n|$)',
        description_pattern: 'Tipo:[\\s]*(.+?)(?=\\n|$)'
      )
    end

    context 'with matching content' do
      let(:email_content) do
        "Comercio: Test Store\nFecha: Aug 1, 2025\nMonto: 1,500.00\nTipo: COMPRA"
      end

      it 'extracts amount using pattern' do
        result = parsing_rule.parse_email(email_content)
        expect(result[:amount]).to eq(BigDecimal('1500.00'))
      end

      it 'extracts date using pattern' do
        result = parsing_rule.parse_email(email_content)
        expect(result[:transaction_date]).to eq(Date.new(2025, 8, 1))
      end

      it 'extracts merchant using pattern' do
        result = parsing_rule.parse_email(email_content)
        expect(result[:merchant_name]).to eq('Test Store')
      end

      it 'extracts description using pattern' do
        result = parsing_rule.parse_email(email_content)
        expect(result[:description]).to eq('COMPRA')
      end

      it 'handles case-insensitive matching' do
        uppercase_content = email_content.upcase
        result = parsing_rule.parse_email(uppercase_content)
        expect(result[:amount]).to eq(BigDecimal('1500.00'))
      end
    end

    context 'with non-matching content' do
      let(:email_content) { 'This email has no transaction data' }

      it 'returns nil for unmatched amount' do
        result = parsing_rule.parse_email(email_content)
        expect(result[:amount]).to be_nil
      end

      it 'returns nil for unmatched date' do
        result = parsing_rule.parse_email(email_content)
        expect(result[:transaction_date]).to be_nil
      end

      it 'returns nil for unmatched merchant' do
        result = parsing_rule.parse_email(email_content)
        expect(result[:merchant_name]).to be_nil
      end

      it 'returns nil for unmatched description' do
        result = parsing_rule.parse_email(email_content)
        expect(result[:description]).to be_nil
      end
    end

    context 'with partial matches' do
      it 'extracts available fields when some patterns match' do
        partial_content = "Monto: 100.00\nOther text here"
        result = parsing_rule.parse_email(partial_content)
        
        expect(result[:amount]).to eq(BigDecimal('100.00'))
        expect(result[:transaction_date]).to be_nil
        expect(result[:merchant_name]).to be_nil
      end
    end

    context 'with capture groups' do
      it 'uses first capture group when present' do
        parsing_rule.amount_pattern = 'Total: \\$([\\d.]+) USD'
        content = 'Total: $50.25 USD'
        
        result = parsing_rule.parse_email(content)
        expect(result[:amount]).to eq(BigDecimal('50.25'))
      end

      it 'uses full match when no capture group' do
        parsing_rule.amount_pattern = '\\d+\\.\\d{2}'
        content = 'Amount is 75.50 dollars'
        
        result = parsing_rule.parse_email(content)
        expect(result[:amount]).to eq(BigDecimal('75.50'))
      end
    end

    context 'with nil patterns' do
      it 'skips extraction for nil patterns' do
        parsing_rule.merchant_pattern = nil
        parsing_rule.description_pattern = nil
        
        content = "Comercio: Store\nTipo: COMPRA\nMonto: 100.00"
        result = parsing_rule.parse_email(content)
        
        expect(result[:amount]).to eq(BigDecimal('100.00'))
        expect(result[:merchant_name]).to be_nil
        expect(result[:description]).to be_nil
      end
    end

    context 'with multiline patterns' do
      it 'handles multiline flag in patterns' do
        parsing_rule.description_pattern = 'Notes:(.+)End'
        content = "Notes:\nLine 1\nLine 2\nEnd"
        
        result = parsing_rule.parse_email(content)
        # Multiline flag is set with Regexp::MULTILINE
        expect(result[:description]).to include('Line')
      end
    end
  end

  describe '#test_patterns' do
    let(:parsing_rule) do
      build_stubbed(:parsing_rule,
        amount_pattern: '\\d+\\.\\d{2}',
        date_pattern: '\\d{2}/\\d{2}/\\d{4}',
        merchant_pattern: '[A-Z]+ Store',
        description_pattern: 'Type: (\\w+)'
      )
    end

    let(:test_content) { "Amount: 100.00\nDate: 01/08/2025\nABC Store\nType: Purchase" }

    it 'tests all patterns and returns results' do
      results = parsing_rule.test_patterns(test_content)
      
      expect(results[:amount][:matched]).to be true
      expect(results[:date][:matched]).to be true
      expect(results[:merchant][:matched]).to be true
      expect(results[:description][:matched]).to be true
    end

    it 'returns match details for successful matches' do
      results = parsing_rule.test_patterns(test_content)
      amount_result = results[:amount]
      
      expect(amount_result[:full_match]).to eq('100.00')
      expect(amount_result[:captured_group]).to be_nil  # No capture group
      expect(amount_result[:position]).to be_a(Integer)
    end

    it 'returns captured group when present' do
      results = parsing_rule.test_patterns(test_content)
      desc_result = results[:description]
      
      expect(desc_result[:full_match]).to eq('Type: Purchase')
      expect(desc_result[:captured_group]).to eq('Purchase')
    end

    it 'returns nil for blank patterns' do
      parsing_rule.merchant_pattern = ''
      results = parsing_rule.test_patterns(test_content)
      
      expect(results[:merchant]).to be_nil
    end

    it 'returns nil for nil patterns' do
      parsing_rule.merchant_pattern = nil
      results = parsing_rule.test_patterns(test_content)
      
      expect(results[:merchant]).to be_nil
    end

    it 'handles invalid regex gracefully' do
      parsing_rule.amount_pattern = '[invalid('
      results = parsing_rule.test_patterns(test_content)
      
      expect(results[:amount][:error]).to be_present
      expect(results[:amount][:matched]).to be_nil
    end

    it 'returns nil for non-matching patterns' do
      parsing_rule.amount_pattern = 'NOMATCH'
      results = parsing_rule.test_patterns(test_content)
      
      expect(results[:amount]).to be_nil
    end
  end

  describe 'private methods' do
    describe '#extract_amount' do
      let(:parsing_rule) { build_stubbed(:parsing_rule) }

      it 'removes currency symbols' do
        amounts = {
          '$100.50' => BigDecimal('100.50'),
          '₡1,500.00' => BigDecimal('1500.00'),
          '€25.75' => BigDecimal('25.75')
        }
        
        amounts.each do |input, expected|
          result = parsing_rule.send(:extract_amount, input)
          expect(result).to eq(expected)
        end
      end

      it 'handles comma as thousands separator' do
        result = parsing_rule.send(:extract_amount, '1,234,567.89')
        expect(result).to eq(BigDecimal('1234567.89'))
      end

      it 'handles spaces in amounts' do
        result = parsing_rule.send(:extract_amount, '1 500.00')
        expect(result).to eq(BigDecimal('1500.00'))
      end

      it 'returns nil for invalid amounts' do
        invalid_amounts = ['abc', 'not a number', '', nil]
        
        invalid_amounts.each do |invalid|
          result = parsing_rule.send(:extract_amount, invalid)
          expect(result).to be_nil
        end
      end

      it 'handles ArgumentError from BigDecimal' do
        # BigDecimal() method, not .new
        allow(Kernel).to receive(:BigDecimal).and_raise(ArgumentError)
        result = parsing_rule.send(:extract_amount, '100.00')
        expect(result).to be_nil
      end

      it 'handles TypeError from BigDecimal' do
        # BigDecimal() method, not .new
        allow(Kernel).to receive(:BigDecimal).and_raise(TypeError)
        result = parsing_rule.send(:extract_amount, '100.00')
        expect(result).to be_nil
      end
    end

    describe '#parse_date' do
      let(:parsing_rule) { build_stubbed(:parsing_rule) }

      context 'Spanish month conversion' do
        it 'converts Spanish month abbreviations to English' do
          spanish_months = {
            'Ene 1, 2025' => Date.new(2025, 1, 1),
            'Feb 15, 2025' => Date.new(2025, 2, 15),
            'Mar 20, 2025' => Date.new(2025, 3, 20),
            'Abr 10, 2025' => Date.new(2025, 4, 10),
            'May 5, 2025' => Date.new(2025, 5, 5),
            'Jun 30, 2025' => Date.new(2025, 6, 30),
            'Jul 4, 2025' => Date.new(2025, 7, 4),
            'Ago 15, 2025' => Date.new(2025, 8, 15),
            'Sep 1, 2025' => Date.new(2025, 9, 1),
            'Oct 31, 2025' => Date.new(2025, 10, 31),
            'Nov 11, 2025' => Date.new(2025, 11, 11),
            'Dic 25, 2025' => Date.new(2025, 12, 25)
          }
          
          spanish_months.each do |input, expected|
            result = parsing_rule.send(:parse_date, input)
            expect(result).to eq(expected), "Failed to parse '#{input}'"
          end
        end
      end

      context 'date format parsing' do
        it 'parses various date formats' do
          formats = {
            '01/08/2025' => Date.new(2025, 8, 1),
            '01-08-2025' => Date.new(2025, 8, 1),
            '2025-08-01' => Date.new(2025, 8, 1),
            '01/08/2025 14:30' => Date.new(2025, 8, 1),
            '01-08-2025 14:30' => Date.new(2025, 8, 1),
            'Aug 1, 2025' => Date.new(2025, 8, 1),
            'Aug 1, 2025, 14:16' => Date.new(2025, 8, 1)
          }
          
          formats.each do |input, expected|
            result = parsing_rule.send(:parse_date, input)
            expect(result).to eq(expected), "Failed to parse '#{input}'"
          end
        end
      end

      context 'Chronic fallback' do
        it 'uses Chronic as fallback for natural language dates' do
          tomorrow = Date.tomorrow
          allow(Chronic).to receive(:parse).with('tomorrow').and_return(tomorrow.to_time)
          
          result = parsing_rule.send(:parse_date, 'tomorrow')
          expect(result).to eq(tomorrow)
        end

        it 'returns nil when Chronic returns nil' do
          allow(Chronic).to receive(:parse).and_return(nil)
          
          result = parsing_rule.send(:parse_date, 'invalid')
          expect(result).to be_nil
        end

        it 'handles Chronic parse errors' do
          allow(Chronic).to receive(:parse).and_raise(StandardError)
          
          result = parsing_rule.send(:parse_date, 'error')
          expect(result).to be_nil
        end
      end

      context 'edge cases' do
        it 'strips whitespace from date strings' do
          result = parsing_rule.send(:parse_date, '  01/08/2025  ')
          expect(result).to eq(Date.new(2025, 8, 1))
        end

        it 'returns nil for empty string' do
          result = parsing_rule.send(:parse_date, '')
          expect(result).to be_nil
        end

        it 'returns nil for nil input' do
          result = parsing_rule.send(:parse_date, nil)
          expect(result).to be_nil
        end

        it 'handles general exceptions' do
          allow(Date).to receive(:strptime).and_raise(StandardError)
          allow(Chronic).to receive(:parse).and_raise(StandardError)
          
          result = parsing_rule.send(:parse_date, 'error date')
          expect(result).to be_nil
        end
      end
    end

    describe '#test_pattern' do
      let(:parsing_rule) { build_stubbed(:parsing_rule) }

      it 'returns match details for successful match' do
        result = parsing_rule.send(:test_pattern, '\\d+', 'abc 123 def')
        
        expect(result[:matched]).to be true
        expect(result[:full_match]).to eq('123')
        expect(result[:position]).to eq(4)
      end

      it 'returns captured group when present' do
        result = parsing_rule.send(:test_pattern, 'value: (\\d+)', 'value: 42')
        
        expect(result[:captured_group]).to eq('42')
        expect(result[:full_match]).to eq('value: 42')
      end

      it 'returns nil for blank pattern' do
        result = parsing_rule.send(:test_pattern, '', 'test text')
        expect(result).to be_nil
      end

      it 'returns nil for nil pattern' do
        result = parsing_rule.send(:test_pattern, nil, 'test text')
        expect(result).to be_nil
      end

      it 'returns nil for non-matching pattern' do
        result = parsing_rule.send(:test_pattern, 'xyz', 'abc def')
        expect(result).to be_nil
      end

      it 'returns error for invalid regex' do
        result = parsing_rule.send(:test_pattern, '[invalid(', 'test')
        
        expect(result[:error]).to be_present
        expect(result[:matched]).to be_nil
      end

      it 'uses case-insensitive matching' do
        result = parsing_rule.send(:test_pattern, 'TEST', 'test value')
        
        expect(result[:matched]).to be true
        expect(result[:full_match]).to eq('test')
      end
    end
  end

  describe 'edge cases' do
    describe 'pattern complexity' do
      it 'handles complex nested patterns' do
        parsing_rule = build_stubbed(:parsing_rule,
          amount_pattern: '(?:Monto|Amount|Total):[\\s]*(?:CRC|USD)?[\\s]*([\\d,]+(?:\\.\\d{2})?)'
        )
        
        content = 'Monto: CRC 1,500.00'
        result = parsing_rule.parse_email(content)
        expect(result[:amount]).to eq(BigDecimal('1500.00'))
      end

      it 'handles patterns with lookahead/lookbehind' do
        parsing_rule = build_stubbed(:parsing_rule,
          merchant_pattern: '(?<=Comercio: ).*?(?=\\n|$)'
        )
        
        content = "Comercio: Test Store\nNext line"
        result = parsing_rule.parse_email(content)
        expect(result[:merchant_name]).to eq('Test Store')
      end
    end

    describe 'performance considerations' do
      it 'handles very long email content' do
        parsing_rule = build_stubbed(:parsing_rule, amount_pattern: '\\d+\\.\\d{2}')
        long_content = 'x' * 10000 + ' 100.00 ' + 'y' * 10000
        
        result = parsing_rule.parse_email(long_content)
        expect(result[:amount]).to eq(BigDecimal('100.00'))
      end

      it 'handles patterns that could cause catastrophic backtracking' do
        # Pattern that could cause issues with naive regex engines
        parsing_rule = build_stubbed(:parsing_rule,
          description_pattern: '(a+)+b'
        )
        
        # This could hang with catastrophic backtracking
        content = 'a' * 30 + 'c'
        
        # Should complete without hanging
        Timeout.timeout(1) do
          result = parsing_rule.parse_email(content)
          expect(result[:description]).to be_nil
        end
      end
    end

    describe 'encoding issues' do
      it 'handles UTF-8 content' do
        parsing_rule = build_stubbed(:parsing_rule, merchant_pattern: 'Tienda: (.+)')
        content = "Tienda: Café José's ñ"
        
        result = parsing_rule.parse_email(content)
        expect(result[:merchant_name]).to eq("Café José's ñ")
      end

      it 'handles different encodings in patterns' do
        parsing_rule = build_stubbed(:parsing_rule,
          amount_pattern: '[€₡$]([\\d,]+\\.\\d{2})'
        )
        
        content = '€100.00'
        result = parsing_rule.parse_email(content)
        expect(result[:amount]).to eq(BigDecimal('100.00'))
      end
    end
  end
end