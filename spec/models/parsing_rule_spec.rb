require 'rails_helper'

RSpec.describe ParsingRule, type: :model, integration: true do
  describe 'validations', integration: true do
    it 'is valid with valid attributes' do
      rule = ParsingRule.new(
        bank_name: 'BAC',
        amount_pattern: '\\d+\\.\\d{2}',
        date_pattern: '\\d{2}/\\d{2}/\\d{4}',
        active: true
      )
      expect(rule).to be_valid
    end

    it 'requires bank_name' do
      rule = ParsingRule.new(amount_pattern: 'test', date_pattern: 'test')
      expect(rule).not_to be_valid
      expect(rule.errors[:bank_name]).to include("can't be blank")
    end

    it 'requires amount_pattern' do
      rule = ParsingRule.new(bank_name: 'BAC', date_pattern: 'test')
      expect(rule).not_to be_valid
      expect(rule.errors[:amount_pattern]).to include("can't be blank")
    end

    it 'requires date_pattern' do
      rule = ParsingRule.new(bank_name: 'BAC', amount_pattern: 'test')
      expect(rule).not_to be_valid
      expect(rule.errors[:date_pattern]).to include("can't be blank")
    end

    it 'validates active as boolean' do
      rule = ParsingRule.new(bank_name: 'BAC', amount_pattern: 'test', date_pattern: 'test', active: nil)
      expect(rule).not_to be_valid
      expect(rule.errors[:active]).to include('is not included in the list')
    end
  end

  describe 'associations', integration: true do
    let(:parsing_rule) { ParsingRule.create!(bank_name: 'BAC', amount_pattern: 'test', date_pattern: 'test', active: true) }

    it 'has many email_accounts through bank_name' do
      email_account = EmailAccount.create!(email: 'test@example.com', provider: 'gmail', bank_name: 'BAC', encrypted_password: 'pass')
      expect(parsing_rule.email_accounts).to include(email_account)
    end
  end

  describe 'scopes', integration: true do
    let!(:active_rule) { ParsingRule.create!(bank_name: 'BAC', amount_pattern: 'test', date_pattern: 'test', active: true) }
    let!(:inactive_rule) { ParsingRule.create!(bank_name: 'BCR', amount_pattern: 'test', date_pattern: 'test', active: false) }

    it 'returns active rules' do
      expect(ParsingRule.active).to include(active_rule)
      expect(ParsingRule.active).not_to include(inactive_rule)
    end

    it 'returns rules for specific bank' do
      bac_rules = ParsingRule.for_bank('BAC')
      expect(bac_rules).to include(active_rule)
      expect(bac_rules).not_to include(inactive_rule)
    end
  end

  describe '#parse_email', integration: true do
    let(:rule) do
      ParsingRule.create!(
        bank_name: 'BAC',
        amount_pattern: 'Monto:[\\s]*CRC[\\s]*([\\d,]+\\.\\d{2})',
        date_pattern: 'Fecha:[\\s]*(.+?)(?=\\n|$)',
        merchant_pattern: 'Comercio:[\\s]*([A-Z\\s]+?)(?=\\s*$|\\n)',
        description_pattern: 'Tipo de Transacci[oó]n:[\\s]*([A-Z]+)',
        active: true
      )
    end

    let(:email_content) do
      <<~EMAIL
        Hola ROGER ESTEBAN SOTO MADRIZ

        Comercio: PTA LEONA SOC
        Fecha: Ago 1, 2025, 14:16
        Monto: CRC 95,000.00
        Tipo de Transacción: COMPRA

        Si no reconoce esta transacción, comuníquese inmediatamente con BAC.
      EMAIL
    end

    it 'extracts amount from email content' do
      parsed_data = rule.parse_email(email_content)
      expect(parsed_data[:amount]).to eq(BigDecimal('95000.00'))
    end

    it 'extracts date from email content' do
      parsed_data = rule.parse_email(email_content)
      expect(parsed_data[:transaction_date]).to eq(Date.new(2025, 8, 1))
    end

    it 'extracts merchant from email content' do
      parsed_data = rule.parse_email(email_content)
      expect(parsed_data[:merchant_name]).to eq('PTA LEONA SOC')
    end

    it 'extracts description from email content' do
      parsed_data = rule.parse_email(email_content)
      expect(parsed_data[:description]).to eq('COMPRA')
    end

    it 'returns empty hash for non-matching content' do
      parsed_data = rule.parse_email('No transaction data here')
      expect(parsed_data[:amount]).to be_nil
      expect(parsed_data[:transaction_date]).to be_nil
      expect(parsed_data[:merchant_name]).to be_nil
      expect(parsed_data[:description]).to be_nil
    end
  end

  describe '#parse_date', integration: true do
    let(:rule) { ParsingRule.new }

    it 'parses Spanish month abbreviations' do
      spanish_dates = {
        'Ago 1, 2025, 14:16' => Date.new(2025, 8, 1),
        'Ene 15, 2025' => Date.new(2025, 1, 15),
        'Dic 31, 2024' => Date.new(2024, 12, 31)
      }

      spanish_dates.each do |date_str, expected_date|
        result = rule.send(:parse_date, date_str)
        expect(result).to eq(expected_date), "Failed to parse #{date_str}"
      end
    end

    it 'parses various date formats' do
      date_formats = {
        '01/08/2025' => Date.new(2025, 8, 1),
        '2025-08-01' => Date.new(2025, 8, 1),
        '01-08-2025' => Date.new(2025, 8, 1)
      }

      date_formats.each do |date_str, expected_date|
        result = rule.send(:parse_date, date_str)
        expect(result).to eq(expected_date), "Failed to parse #{date_str}"
      end
    end

    it 'returns nil for invalid dates' do
      result = rule.send(:parse_date, 'invalid date')
      expect(result).to be_nil
    end
  end

  describe '#extract_amount', integration: true do
    let(:rule) { ParsingRule.new }

    it 'extracts clean decimal amounts' do
      amounts = {
        '95,000.00' => BigDecimal('95000.00'),
        '$20.50' => BigDecimal('20.50'),
        '₡1,500.75' => BigDecimal('1500.75'),
        '100' => BigDecimal('100.00')
      }

      amounts.each do |amount_str, expected_amount|
        result = rule.send(:extract_amount, amount_str)
        expect(result).to eq(expected_amount), "Failed to extract #{amount_str}"
      end
    end

    it 'returns nil for invalid amounts' do
      result = rule.send(:extract_amount, 'not a number')
      expect(result).to be_nil
    end
  end

  describe '#test_patterns', integration: true do
    let(:rule) do
      ParsingRule.create!(
        bank_name: 'BAC',
        amount_pattern: 'Monto:[\\s]*([\\d,]+\\.\\d{2})',
        date_pattern: 'Fecha:[\\s]*(.+)',
        merchant_pattern: 'Comercio:[\\s]*(.+)',
        description_pattern: 'Tipo:[\\s]*(.+)',
        active: true
      )
    end

    let(:test_content) do
      <<~EMAIL
        Comercio: Test Merchant
        Fecha: Aug 1, 2025
        Monto: 100.00
        Tipo: COMPRA
      EMAIL
    end

    it 'tests all patterns against content' do
      results = rule.test_patterns(test_content)

      expect(results[:amount][:matched]).to be true
      expect(results[:date][:matched]).to be true
      expect(results[:merchant][:matched]).to be true
      expect(results[:description][:matched]).to be true
    end

    it 'handles invalid regex patterns gracefully' do
      rule.amount_pattern = '[invalid regex'
      results = rule.test_patterns(test_content)

      expect(results[:amount][:error]).to be_present
    end

    it 'returns nil for blank patterns' do
      rule.merchant_pattern = ''
      results = rule.test_patterns(test_content)
      expect(results[:merchant]).to be_nil
    end

    it 'returns full match details when pattern matches' do
      results = rule.test_patterns(test_content)
      amount_result = results[:amount]

      expect(amount_result[:matched]).to be true
      expect(amount_result[:full_match]).to eq('Monto: 100.00')
      expect(amount_result[:captured_group]).to eq('100.00')
      expect(amount_result[:position]).to be_a(Integer)
    end
  end

  describe 'edge cases and error handling', integration: true do
    let(:rule) { create(:parsing_rule, :bac) }

    it 'handles email content with nil patterns gracefully' do
      rule.merchant_pattern = nil
      rule.description_pattern = nil

      parsed_data = rule.parse_email('Monto: CRC 100.00\nFecha: Aug 1, 2025')
      expect(parsed_data[:merchant_name]).to be_nil
      expect(parsed_data[:description]).to be_nil
    end

    it 'extracts amount when using first capture group' do
      email_with_amount = 'Total: USD $100.50 charged'
      rule.amount_pattern = 'Total: USD \\$([\\d.]+)'

      parsed_data = rule.parse_email(email_with_amount)
      expect(parsed_data[:amount]).to eq(BigDecimal('100.50'))
    end

    it 'extracts amount when using full match (no capture group)' do
      email_with_amount = 'Amount: 75.25'
      rule.amount_pattern = '[\\d.]+'

      parsed_data = rule.parse_email(email_with_amount)
      expect(parsed_data[:amount]).to eq(BigDecimal('75.25'))
    end

    it 'handles currency symbols in amount extraction' do
      amounts_with_symbols = {
        '₡95,000.00' => BigDecimal('95000.00'),
        '$1,500.75' => BigDecimal('1500.75'),
        '₡2500.50' => BigDecimal('2500.50')  # Use ₡ symbol instead of CRC text
      }

      amounts_with_symbols.each do |amount_str, expected|
        result = rule.send(:extract_amount, amount_str)
        expect(result).to eq(expected)
      end
    end

    it 'handles malformed decimal amounts gracefully' do
      bad_amounts = [ 'abc', '', '..', '1.2.3', nil ]

      bad_amounts.each do |bad_amount|
        result = rule.send(:extract_amount, bad_amount.to_s)
        expect(result).to be_nil
      end
    end

    it 'uses chronic gem as fallback for date parsing' do
      # Mock Chronic.parse to test fallback
      allow(Chronic).to receive(:parse).with('tomorrow').and_return(Time.current + 1.day)

      result = rule.send(:parse_date, 'tomorrow')
      expect(result).to eq((Time.current + 1.day).to_date)
    end

    it 'handles chronic parse errors gracefully' do
      allow(Chronic).to receive(:parse).and_raise(StandardError, 'Parse error')

      result = rule.send(:parse_date, 'invalid date')
      expect(result).to be_nil
    end
  end
end
