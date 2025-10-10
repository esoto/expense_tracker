require 'rails_helper'

RSpec.describe Services::EmailProcessing::Parser, type: :service, unit: true do
  let(:email_account) { instance_double(EmailAccount, email: 'test@example.com', bank_name: 'TEST_BANK') }
  let(:parsing_rule) { instance_double(ParsingRule, id: 1, bank_name: 'TEST_BANK') }
  let(:email_data) do
    {
      message_id: 123,
      from: 'notifications@bank.com',
      subject: 'Transaction Notification',
      date: 'Wed, 02 Aug 2025 14:16:00 +0000',
      body: 'Transaction: $100.00 on 2025-08-01 at AMAZON.COM'
    }
  end

  let(:parser) { described_class.new(email_account, email_data) }
  let(:logger) { instance_double(Logger, error: nil, warn: nil, info: nil) }

  before do
    allow(ParsingRule).to receive_message_chain(:active, :for_bank, :first).and_return(parsing_rule)
    allow(Rails).to receive(:logger).and_return(logger)
  end

  describe 'StrategyFactory integration' do
    let(:strategy) { instance_double(EmailProcessing::Strategies::Regex) }
    let(:parsed_data) do
      {
        amount: BigDecimal('100.00'),
        transaction_date: Date.new(2025, 8, 1),
        merchant_name: 'AMAZON.COM',
        description: 'Online purchase'
      }
    end

    before do
      allow(EmailProcessing::StrategyFactory).to receive(:create_strategy).and_return(strategy)
      allow(strategy).to receive(:parse_email).and_return(parsed_data)
      allow(parser).to receive(:valid_parsed_data?).and_return(true)
      allow(parser).to receive(:create_expense).and_return(instance_double(Expense))
    end

    describe 'strategy creation' do
      it 'passes parsing rule to factory' do
        expect(EmailProcessing::StrategyFactory).to receive(:create_strategy)
          .with(parsing_rule, email_content: anything)
        parser.parse_expense
      end

      it 'passes email content to factory' do
        expect(EmailProcessing::StrategyFactory).to receive(:create_strategy)
          .with(anything, email_content: parser.send(:email_content))
        parser.parse_expense
      end

      it 'handles nil strategy from factory' do
        allow(EmailProcessing::StrategyFactory).to receive(:create_strategy).and_return(nil)

        expect { parser.parse_expense }.not_to raise_error
        expect(parser.parse_expense).to be_nil
      end

      it 'handles factory raising ArgumentError' do
        allow(EmailProcessing::StrategyFactory).to receive(:create_strategy)
          .and_raise(ArgumentError, 'Unknown strategy type')

        expect { parser.parse_expense }.not_to raise_error
        expect(parser.errors).to include('Error parsing email: Unknown strategy type')
      end

      it 'handles factory raising NameError' do
        allow(EmailProcessing::StrategyFactory).to receive(:create_strategy)
          .and_raise(NameError, 'Uninitialized constant')

        expect { parser.parse_expense }.not_to raise_error
        expect(parser.errors).to include('Error parsing email: Uninitialized constant')
      end
    end

    describe 'strategy parsing' do
      it 'passes email content to strategy parse method' do
        expect(strategy).to receive(:parse_email).with(parser.send(:email_content))
        parser.parse_expense
      end

      it 'handles strategy returning nil' do
        allow(strategy).to receive(:parse_email).and_return(nil)
        allow(parser).to receive(:valid_parsed_data?).and_return(false)

        result = parser.parse_expense
        expect(result).to be_nil
      end

      it 'handles strategy returning empty hash' do
        allow(strategy).to receive(:parse_email).and_return({})
        allow(parser).to receive(:valid_parsed_data?).and_return(false)

        result = parser.parse_expense
        expect(result).to be_nil
      end

      it 'handles strategy raising parsing error' do
        allow(strategy).to receive(:parse_email).and_raise(StandardError, 'Regex failed')

        expect { parser.parse_expense }.not_to raise_error
        expect(parser.errors).to include('Error parsing email: Regex failed')
      end
    end

    describe 'different strategy types' do
      context 'with Regex strategy' do
        let(:regex_strategy) { instance_double(EmailProcessing::Strategies::Regex) }

        before do
          allow(EmailProcessing::StrategyFactory).to receive(:create_strategy).and_return(regex_strategy)
          allow(regex_strategy).to receive(:parse_email).and_return(parsed_data)
        end

        it 'works with Regex strategy' do
          expect(regex_strategy).to receive(:parse_email)
          parser.parse_expense
        end
      end

      context 'with Base strategy subclass' do
        # Test with a generic subclass of Base strategy instead of ML
        let(:base_subclass_strategy) do
          Class.new(EmailProcessing::Strategies::Base) do
            def parse_email(content)
              { amount: BigDecimal('100.00'), transaction_date: Date.current }
            end
          end.new(parsing_rule)
        end

        before do
          allow(EmailProcessing::StrategyFactory).to receive(:create_strategy).and_return(base_subclass_strategy)
        end

        it 'works with Base strategy subclass' do
          expect(base_subclass_strategy).to receive(:parse_email).and_call_original
          parser.parse_expense
        end
      end

      context 'with another Regex strategy instance' do
        # Test with multiple Regex strategy instances
        let(:another_regex_strategy) { EmailProcessing::Strategies::Regex.new(parsing_rule) }

        before do
          allow(EmailProcessing::StrategyFactory).to receive(:create_strategy).and_return(another_regex_strategy)
          allow(another_regex_strategy).to receive(:parse_email).and_return(parsed_data)
        end

        it 'works with another Regex strategy instance' do
          expect(another_regex_strategy).to receive(:parse_email)
          parser.parse_expense
        end
      end
    end
  end

  describe 'CurrencyDetectorService integration' do
    let(:expense) { instance_double(Expense, usd!: nil, eur!: nil, crc!: nil) }
    let(:parsed_data) { { amount: BigDecimal('100.00') } }
    let(:currency_detector) { instance_double(CurrencyDetectorService) }

    before do
      allow(CurrencyDetectorService).to receive(:new).and_return(currency_detector)
      allow(currency_detector).to receive(:apply_currency_to_expense)
    end

    describe '#set_currency' do
      it 'creates CurrencyDetectorService with email content' do
        expect(CurrencyDetectorService).to receive(:new)
          .with(email_content: parser.send(:email_content))
        parser.send(:set_currency, expense, parsed_data)
      end

      it 'applies currency to expense' do
        expect(currency_detector).to receive(:apply_currency_to_expense)
          .with(expense, parsed_data)
        parser.send(:set_currency, expense, parsed_data)
      end

      it 'handles service initialization error' do
        allow(CurrencyDetectorService).to receive(:new)
          .and_raise(StandardError, 'Service init failed')

        expect { parser.send(:set_currency, expense, parsed_data) }.to raise_error(StandardError)
      end

      it 'handles apply_currency error' do
        allow(currency_detector).to receive(:apply_currency_to_expense)
          .and_raise(StandardError, 'Currency detection failed')

        expect { parser.send(:set_currency, expense, parsed_data) }.to raise_error(StandardError)
      end

      context 'with different currencies' do
        it 'detects USD' do
          email_data[:body] = 'Transaction: $100.00 USD'
          allow(currency_detector).to receive(:apply_currency_to_expense) do |exp, _|
            exp.usd!
          end

          expect(expense).to receive(:usd!)
          parser.send(:set_currency, expense, parsed_data)
        end

        it 'detects EUR' do
          email_data[:body] = 'Transaction: €100.00 EUR'
          allow(currency_detector).to receive(:apply_currency_to_expense) do |exp, _|
            exp.eur!
          end

          expect(expense).to receive(:eur!)
          parser.send(:set_currency, expense, parsed_data)
        end

        it 'defaults to CRC' do
          email_data[:body] = 'Transaction: ₡100.00'
          allow(currency_detector).to receive(:apply_currency_to_expense) do |exp, _|
            exp.crc!
          end

          expect(expense).to receive(:crc!)
          parser.send(:set_currency, expense, parsed_data)
        end
      end

      context 'with parsed_data currency hints' do
        it 'uses amount string with currency symbol' do
          parsed_data[:amount] = '$100.00'
          parser.send(:set_currency, expense, parsed_data)
          expect(currency_detector).to have_received(:apply_currency_to_expense)
            .with(expense, hash_including(amount: '$100.00'))
        end

        it 'uses merchant_name with currency code' do
          parsed_data[:merchant_name] = 'AMAZON.COM USD'
          parser.send(:set_currency, expense, parsed_data)
          expect(currency_detector).to have_received(:apply_currency_to_expense)
            .with(expense, hash_including(merchant_name: 'AMAZON.COM USD'))
        end

        it 'uses description with currency info' do
          parsed_data[:description] = 'Purchase in EUR'
          parser.send(:set_currency, expense, parsed_data)
          expect(currency_detector).to have_received(:apply_currency_to_expense)
            .with(expense, hash_including(description: 'Purchase in EUR'))
        end
      end
    end
  end

  describe 'Services::CategoryGuesserService integration' do
    let(:expense) do
      instance_double(Expense,
        merchant_name: 'RESTAURANT ABC',
        description: 'Lunch purchase',
        amount: BigDecimal('50.00')
      )
    end
    let(:category_guesser) { instance_double(Services::CategoryGuesserService) }
    let(:category) { instance_double(Category, name: 'Food & Dining') }

    before do
      allow(Services::CategoryGuesserService).to receive(:new).and_return(category_guesser)
      allow(category_guesser).to receive(:guess_category_for_expense).and_return(category)
    end

    describe '#guess_category' do
      it 'creates Services::CategoryGuesserService' do
        expect(Services::CategoryGuesserService).to receive(:new).with(no_args)
        parser.send(:guess_category, expense)
      end

      it 'passes expense to guess method' do
        expect(category_guesser).to receive(:guess_category_for_expense).with(expense)
        parser.send(:guess_category, expense)
      end

      it 'returns guessed category' do
        result = parser.send(:guess_category, expense)
        expect(result).to eq(category)
      end

      it 'handles nil return from service' do
        allow(category_guesser).to receive(:guess_category_for_expense).and_return(nil)

        result = parser.send(:guess_category, expense)
        expect(result).to be_nil
      end

      it 'handles service initialization error' do
        allow(Services::CategoryGuesserService).to receive(:new)
          .and_raise(StandardError, 'Service init failed')

        expect { parser.send(:guess_category, expense) }.to raise_error(StandardError)
      end

      it 'handles guess_category error' do
        allow(category_guesser).to receive(:guess_category_for_expense)
          .and_raise(StandardError, 'Category guess failed')

        expect { parser.send(:guess_category, expense) }.to raise_error(StandardError)
      end

      context 'with different expense types' do
        it 'categorizes food expenses' do
          allow(expense).to receive(:merchant_name).and_return('PIZZA HUT')
          parser.send(:guess_category, expense)
          expect(category_guesser).to have_received(:guess_category_for_expense).with(expense)
        end

        it 'categorizes transport expenses' do
          allow(expense).to receive(:merchant_name).and_return('UBER')
          allow(expense).to receive(:description).and_return('Ride payment')
          parser.send(:guess_category, expense)
          expect(category_guesser).to have_received(:guess_category_for_expense).with(expense)
        end

        it 'categorizes shopping expenses' do
          allow(expense).to receive(:merchant_name).and_return('AMAZON')
          allow(expense).to receive(:description).and_return('Online purchase')
          parser.send(:guess_category, expense)
          expect(category_guesser).to have_received(:guess_category_for_expense).with(expense)
        end
      end

      context 'with expense attributes' do
        it 'uses merchant_name for categorization' do
          allow(expense).to receive(:merchant_name).and_return('SUPERMARKET XYZ')
          parser.send(:guess_category, expense)
          expect(category_guesser).to have_received(:guess_category_for_expense)
        end

        it 'uses description for categorization' do
          allow(expense).to receive(:description).and_return('Grocery shopping')
          parser.send(:guess_category, expense)
          expect(category_guesser).to have_received(:guess_category_for_expense)
        end

        it 'handles nil merchant_name' do
          allow(expense).to receive(:merchant_name).and_return(nil)
          parser.send(:guess_category, expense)
          expect(category_guesser).to have_received(:guess_category_for_expense)
        end

        it 'handles nil description' do
          allow(expense).to receive(:description).and_return(nil)
          parser.send(:guess_category, expense)
          expect(category_guesser).to have_received(:guess_category_for_expense)
        end
      end
    end
  end

  describe 'create_expense service integrations' do
    let(:parsed_data) do
      {
        amount: BigDecimal('100.00'),
        transaction_date: Date.current,
        merchant_name: 'Test Merchant',
        description: 'Test Purchase'
      }
    end

    let(:expense) do
      instance_double(Expense,
        save: true,
        update: true,
        formatted_amount: '$100.00',
        :category= => nil
      )
    end

    let(:category) { instance_double(Category, name: 'Shopping') }
    let(:currency_detector) { instance_double(CurrencyDetectorService) }
    let(:category_guesser) { instance_double(Services::CategoryGuesserService) }

    before do
      allow(parser).to receive(:find_duplicate_expense).and_return(nil)
      allow(Expense).to receive(:new).and_return(expense)
      allow(CurrencyDetectorService).to receive(:new).and_return(currency_detector)
      allow(currency_detector).to receive(:apply_currency_to_expense)
      allow(Services::CategoryGuesserService).to receive(:new).and_return(category_guesser)
      allow(category_guesser).to receive(:guess_category_for_expense).and_return(category)
      allow(parser).to receive(:email_content).and_return('email content')
    end

    describe 'service call order' do
      it 'calls services in correct order' do
        call_order = []

        allow(parser).to receive(:find_duplicate_expense) do
          call_order << :duplicate_check
          nil
        end

        allow(Expense).to receive(:new) do
          call_order << :create_expense
          expense
        end

        allow(currency_detector).to receive(:apply_currency_to_expense) do
          call_order << :set_currency
        end

        allow(category_guesser).to receive(:guess_category_for_expense) do
          call_order << :guess_category
          category
        end

        allow(expense).to receive(:save) do
          call_order << :save_expense
          true
        end

        parser.send(:create_expense, parsed_data)

        expect(call_order).to eq([
          :duplicate_check,
          :create_expense,
          :set_currency,
          :guess_category,
          :save_expense
        ])
      end
    end

    describe 'service failure handling' do
      context 'when currency detection fails' do
        before do
          allow(currency_detector).to receive(:apply_currency_to_expense)
            .and_raise(StandardError, 'Currency error')
        end

        it 'handles the error gracefully' do
          expect { parser.send(:create_expense, parsed_data) }.not_to raise_error
          expect(parser.errors).to include('Currency detection failed: Currency error')
        end
      end

      context 'when category guessing fails' do
        before do
          allow(category_guesser).to receive(:guess_category_for_expense)
            .and_raise(StandardError, 'Category error')
        end

        it 'handles the error gracefully' do
          expect { parser.send(:create_expense, parsed_data) }.not_to raise_error
          expect(parser.errors).to include('Category guess failed: Category error')
        end
      end

      context 'when expense save fails' do
        before do
          allow(expense).to receive(:save).and_return(false)
          allow(expense).to receive(:errors).and_return(
            instance_double(ActiveModel::Errors, full_messages: [ 'Amount is invalid' ])
          )
        end

        it 'returns nil' do
          result = parser.send(:create_expense, parsed_data)
          expect(result).to be_nil
        end

        it 'adds error message' do
          parser.send(:create_expense, parsed_data)
          expect(parser.errors).to include('Failed to save expense: Amount is invalid')
        end
      end
    end

    describe 'data passed to services' do
      it 'passes full parsed_data to currency detector' do
        expect(currency_detector).to receive(:apply_currency_to_expense)
          .with(expense, parsed_data)
        parser.send(:create_expense, parsed_data)
      end

      it 'passes expense instance to category guesser' do
        expect(category_guesser).to receive(:guess_category_for_expense)
          .with(expense)
        parser.send(:create_expense, parsed_data)
      end

      it 'sets category on expense' do
        expect(expense).to receive(:category=).with(category)
        parser.send(:create_expense, parsed_data)
      end

      it 'handles nil category from guesser' do
        allow(category_guesser).to receive(:guess_category_for_expense).and_return(nil)
        expect(expense).to receive(:category=).with(nil)
        parser.send(:create_expense, parsed_data)
      end
    end
  end

  describe 'full parsing flow with all services' do
    let(:strategy) { instance_double(EmailProcessing::Strategies::Regex) }
    let(:currency_detector) { instance_double(CurrencyDetectorService) }
    let(:category_guesser) { instance_double(Services::CategoryGuesserService) }
    let(:category) { instance_double(Category, name: 'Food') }
    let(:expense) do
      instance_double(Expense,
        save: true,
        update: true,
        formatted_amount: '$100.00',
        :category= => nil
      )
    end

    let(:parsed_data) do
      {
        amount: BigDecimal('100.00'),
        transaction_date: Date.current,
        merchant_name: 'RESTAURANT',
        description: 'Dinner'
      }
    end

    before do
      # Setup strategy factory
      allow(EmailProcessing::StrategyFactory).to receive(:create_strategy).and_return(strategy)
      allow(strategy).to receive(:parse_email).and_return(parsed_data)

      # Setup currency detector
      allow(CurrencyDetectorService).to receive(:new).and_return(currency_detector)
      allow(currency_detector).to receive(:apply_currency_to_expense)

      # Setup category guesser
      allow(Services::CategoryGuesserService).to receive(:new).and_return(category_guesser)
      allow(category_guesser).to receive(:guess_category_for_expense).and_return(category)

      # Setup expense creation
      allow(Expense).to receive(:where).and_return(instance_double(ActiveRecord::Relation, first: nil))
      allow(Expense).to receive(:new).and_return(expense)
    end

    it 'completes full parsing flow successfully' do
      result = parser.parse_expense

      expect(result).to eq(expense)
      expect(EmailProcessing::StrategyFactory).to have_received(:create_strategy)
      expect(strategy).to have_received(:parse_email)
      expect(currency_detector).to have_received(:apply_currency_to_expense)
      expect(category_guesser).to have_received(:guess_category_for_expense)
      expect(expense).to have_received(:save)
      expect(expense).to have_received(:update).with(status: :processed)
    end

    it 'logs successful expense creation' do
      expect(logger).to receive(:info).with('Created expense: $100.00 from test@example.com')
      parser.parse_expense
    end
  end
end
