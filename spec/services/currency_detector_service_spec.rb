require 'rails_helper'

RSpec.describe CurrencyDetectorService do
  let(:email_content) { 'Transaction completed at AMAZON.COM for USD 250.00' }
  let(:service) { described_class.new(email_content: email_content) }

  describe '#initialize' do
    it 'sets email content' do
      expect(service.instance_variable_get(:@email_content)).to eq(email_content)
    end

    it 'allows nil email content' do
      service = described_class.new
      expect(service.instance_variable_get(:@email_content)).to be_nil
    end
  end

  describe '#detect_currency' do
    context 'USD detection' do
      it 'detects currency from $ symbol in email content' do
        service = described_class.new(email_content: 'Purchase for $150.00')
        currency = service.detect_currency
        expect(currency).to eq('usd')
      end

      it 'detects currency from "usd" text in email content' do
        service = described_class.new(email_content: 'Amount: USD 250.00')
        currency = service.detect_currency
        expect(currency).to eq('usd')
      end

      it 'detects currency from "dollar" text in email content' do
        service = described_class.new(email_content: 'Payment in dollars')
        currency = service.detect_currency
        expect(currency).to eq('usd')
      end

      it 'detects currency from $ symbol in parsed data amount' do
        parsed_data = { amount: '$75.50' }
        currency = service.detect_currency(parsed_data)
        expect(currency).to eq('usd')
      end

      it 'detects currency from USD in description' do
        parsed_data = { description: 'Purchase for USD payment' }
        currency = service.detect_currency(parsed_data)
        expect(currency).to eq('usd')
      end

      it 'detects currency from dollar in merchant name' do
        parsed_data = { merchant_name: 'Dollar Store' }
        currency = service.detect_currency(parsed_data)
        expect(currency).to eq('usd')
      end

      it 'is case insensitive' do
        service = described_class.new(email_content: 'Amount: uSd 250.00')
        currency = service.detect_currency
        expect(currency).to eq('usd')
      end
    end

    context 'EUR detection' do
      it 'detects currency from € symbol in email content' do
        service = described_class.new(email_content: 'Purchase for €150.00')
        currency = service.detect_currency
        expect(currency).to eq('eur')
      end

      it 'detects currency from "eur" text in email content' do
        service = described_class.new(email_content: 'Amount: EUR 250.00')
        currency = service.detect_currency
        expect(currency).to eq('eur')
      end

      it 'detects currency from "euro" text in email content' do
        service = described_class.new(email_content: 'Payment in euros')
        currency = service.detect_currency
        expect(currency).to eq('eur')
      end

      it 'detects currency from € symbol in parsed data' do
        # Use service without USD content in email
        service = described_class.new(email_content: 'Local transaction')
        parsed_data = { amount: '€75.50' }
        currency = service.detect_currency(parsed_data)
        expect(currency).to eq('eur')
      end

      it 'is case insensitive' do
        service = described_class.new(email_content: 'Amount: EuR 250.00')
        currency = service.detect_currency
        expect(currency).to eq('eur')
      end
    end

    context 'CRC default currency' do
      it 'defaults to CRC when no currency patterns found' do
        service = described_class.new(email_content: 'Purchase at local store')
        currency = service.detect_currency
        expect(currency).to eq('crc')
      end

      it 'defaults to CRC with nil email content' do
        service = described_class.new(email_content: nil)
        currency = service.detect_currency
        expect(currency).to eq('crc')
      end

      it 'defaults to CRC with empty parsed data' do
        service = described_class.new(email_content: 'Local transaction')
        currency = service.detect_currency({})
        expect(currency).to eq('crc')
      end

      it 'defaults to CRC with nil values in parsed data' do
        # Use service without USD content in email
        service = described_class.new(email_content: 'Local transaction')
        parsed_data = { amount: nil, description: nil, merchant_name: nil }
        currency = service.detect_currency(parsed_data)
        expect(currency).to eq('crc')
      end
    end

    context 'priority handling' do
      it 'USD takes priority over EUR when both present' do
        service = described_class.new(email_content: 'Transfer from USD to EUR account')
        currency = service.detect_currency
        expect(currency).to eq('usd')
      end
    end

    context 'with complex content' do
      it 'handles mixed currency mentions correctly' do
        service = described_class.new(email_content: 'Exchange rate: 1 EUR = 1.1 USD, charged $50')
        currency = service.detect_currency
        expect(currency).to eq('usd')  # USD comes first in pattern matching
      end

      it 'combines email content and parsed data for detection' do
        service = described_class.new(email_content: 'International purchase')
        parsed_data = {
          amount: '€125.00',
          description: 'European store purchase',
          merchant_name: 'EU MERCHANT'
        }
        currency = service.detect_currency(parsed_data)
        expect(currency).to eq('eur')
      end
    end
  end

  describe '#apply_currency_to_expense' do
    let(:expense) { instance_double(Expense, usd!: nil, eur!: nil, crc!: nil) }

    it 'applies USD currency to expense' do
      service = described_class.new(email_content: 'Purchase for $100')
      service.apply_currency_to_expense(expense)
      expect(expense).to have_received(:usd!)
    end

    it 'applies EUR currency to expense' do
      service = described_class.new(email_content: 'Purchase for €100')
      service.apply_currency_to_expense(expense)
      expect(expense).to have_received(:eur!)
    end

    it 'applies CRC currency to expense by default' do
      service = described_class.new(email_content: 'Local purchase')
      service.apply_currency_to_expense(expense)
      expect(expense).to have_received(:crc!)
    end

    it 'uses parsed data for currency detection' do
      service = described_class.new(email_content: 'Transaction')
      parsed_data = { amount: '$75.00' }
      service.apply_currency_to_expense(expense, parsed_data)
      expect(expense).to have_received(:usd!)
    end

    it 'falls back to CRC for unknown currency' do
      # Mock the detect_currency method to return an unknown currency
      allow(service).to receive(:detect_currency).and_return('unknown')
      service.apply_currency_to_expense(expense)
      expect(expense).to have_received(:crc!)
    end
  end

  describe 'constants' do
    it 'defines USD patterns' do
      expect(described_class::USD_PATTERNS).to eq(%w[$ usd dollar])
    end

    it 'defines EUR patterns' do
      expect(described_class::EUR_PATTERNS).to eq(%w[€ eur euro])
    end

    it 'defines default currency' do
      expect(described_class::DEFAULT_CURRENCY).to eq('crc')
    end
  end

  describe 'private methods' do
    describe '#build_detection_text' do
      it 'combines all text sources' do
        service = described_class.new(email_content: 'Email content')
        parsed_data = {
          amount: '$100',
          description: 'Purchase desc',
          merchant_name: 'Store name'
        }

        # Access private method for testing
        text = service.send(:build_detection_text, parsed_data)
        expect(text).to eq('email content $100 purchase desc store name')
      end

      it 'handles nil values gracefully' do
        service = described_class.new(email_content: nil)
        parsed_data = { amount: nil, description: 'Valid desc', merchant_name: nil }

        text = service.send(:build_detection_text, parsed_data)
        expect(text).to eq('valid desc')
      end

      it 'converts to lowercase' do
        service = described_class.new(email_content: 'UPPER CASE')
        text = service.send(:build_detection_text, {})
        expect(text).to eq('upper case')
      end
    end

    describe '#contains_usd?' do
      it 'detects USD patterns' do
        expect(service.send(:contains_usd?, 'amount $100')).to be true
        expect(service.send(:contains_usd?, 'usd payment')).to be true
        expect(service.send(:contains_usd?, 'dollar store')).to be true
        expect(service.send(:contains_usd?, 'no currency')).to be false
      end
    end

    describe '#contains_eur?' do
      it 'detects EUR patterns' do
        expect(service.send(:contains_eur?, 'amount €100')).to be true
        expect(service.send(:contains_eur?, 'eur payment')).to be true
        expect(service.send(:contains_eur?, 'euro store')).to be true
        expect(service.send(:contains_eur?, 'no currency')).to be false
      end
    end
  end
end
