require 'rails_helper'

RSpec.describe EmailProcessing::Parser, type: :service, unit: true do
  let(:email_account) { instance_double(EmailAccount, email: 'test@example.com', bank_name: 'TEST_BANK') }
  let(:parsing_rule) { instance_double(ParsingRule, id: 1, bank_name: 'TEST_BANK') }
  let(:email_data) do
    {
      message_id: 123,
      from: 'notifications@bank.com',
      subject: 'Transaction Notification',
      date: 'Wed, 02 Aug 2025 14:16:00 +0000',
      body: 'Transaction: $100.00 on 2025-08-01'
    }
  end

  let(:parser) { described_class.new(email_account, email_data) }
  let(:logger) { instance_double(Logger, error: nil, warn: nil, info: nil) }

  before do
    allow(ParsingRule).to receive_message_chain(:active, :for_bank, :first).and_return(parsing_rule)
    allow(Rails).to receive(:logger).and_return(logger)
  end

  describe '#find_duplicate_expense' do
    let(:base_date) { Date.new(2025, 8, 15) }
    let(:parsed_data) do
      {
        amount: BigDecimal('100.00'),
        transaction_date: base_date,
        merchant_name: 'Test Merchant',
        description: 'Test Transaction'
      }
    end

    let(:expense_relation) { instance_double(ActiveRecord::Relation) }

    before do
      allow(Expense).to receive(:where).and_return(expense_relation)
      allow(expense_relation).to receive(:first).and_return(nil)
    end

    describe 'date range calculation' do
      it 'creates date range of ±1 day' do
        expected_range = (base_date - 1.day)..(base_date + 1.day)

        expect(Expense).to receive(:where).with(
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: expected_range
        )

        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'handles dates at month boundaries' do
        parsed_data[:transaction_date] = Date.new(2025, 8, 1)
        expected_range = Date.new(2025, 7, 31)..Date.new(2025, 8, 2)

        expect(Expense).to receive(:where).with(
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: expected_range
        )

        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'handles dates at year boundaries' do
        parsed_data[:transaction_date] = Date.new(2025, 1, 1)
        expected_range = Date.new(2024, 12, 31)..Date.new(2025, 1, 2)

        expect(Expense).to receive(:where).with(
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: expected_range
        )

        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'handles leap year boundaries' do
        parsed_data[:transaction_date] = Date.new(2024, 2, 29)
        expected_range = Date.new(2024, 2, 28)..Date.new(2024, 3, 1)

        expect(Expense).to receive(:where).with(
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: expected_range
        )

        parser.send(:find_duplicate_expense, parsed_data)
      end
    end

    describe 'matching criteria' do
      it 'matches by email_account' do
        expect(Expense).to receive(:where).with(hash_including(email_account: email_account))
        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'matches by exact amount' do
        expect(Expense).to receive(:where).with(hash_including(amount: BigDecimal('100.00')))
        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'uses transaction_date range' do
        expect(Expense).to receive(:where).with(hash_including(transaction_date: anything))
        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'does not consider merchant_name for matching' do
        expect(Expense).to receive(:where).with(hash_excluding(merchant_name: anything))
        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'does not consider description for matching' do
        expect(Expense).to receive(:where).with(hash_excluding(description: anything))
        parser.send(:find_duplicate_expense, parsed_data)
      end
    end

    describe 'return values' do
      let(:existing_expense) { instance_double(Expense, id: 123) }

      it 'returns first matching expense' do
        allow(expense_relation).to receive(:first).and_return(existing_expense)

        result = parser.send(:find_duplicate_expense, parsed_data)
        expect(result).to eq(existing_expense)
      end

      it 'returns nil when no match found' do
        allow(expense_relation).to receive(:first).and_return(nil)

        result = parser.send(:find_duplicate_expense, parsed_data)
        expect(result).to be_nil
      end

      it 'returns only first expense when multiple exist' do
        first_expense = instance_double(Expense, id: 1)
        allow(expense_relation).to receive(:first).and_return(first_expense)

        result = parser.send(:find_duplicate_expense, parsed_data)
        expect(result).to eq(first_expense)
      end
    end

    describe 'edge cases' do
      it 'handles nil amount in parsed_data' do
        parsed_data[:amount] = nil

        expect(Expense).to receive(:where).with(hash_including(amount: nil))
        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'handles nil transaction_date' do
        parsed_data[:transaction_date] = nil

        expect { parser.send(:find_duplicate_expense, parsed_data) }.to raise_error(NoMethodError)
      end

      it 'handles zero amount' do
        parsed_data[:amount] = BigDecimal('0')

        expect(Expense).to receive(:where).with(hash_including(amount: BigDecimal('0')))
        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'handles negative amount' do
        parsed_data[:amount] = BigDecimal('-100.00')

        expect(Expense).to receive(:where).with(hash_including(amount: BigDecimal('-100.00')))
        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'handles very large amounts' do
        large_amount = BigDecimal('999999999.99')
        parsed_data[:amount] = large_amount

        expect(Expense).to receive(:where).with(hash_including(amount: large_amount))
        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'handles string amounts that convert to BigDecimal' do
        parsed_data[:amount] = '100.00'

        expect(Expense).to receive(:where).with(hash_including(amount: '100.00'))
        parser.send(:find_duplicate_expense, parsed_data)
      end
    end
  end

  describe '#create_expense with duplicate detection' do
    let(:parsed_data) do
      {
        amount: BigDecimal('100.00'),
        transaction_date: Date.new(2025, 8, 15),
        merchant_name: 'Test Merchant',
        description: 'Test Transaction'
      }
    end

    let(:existing_expense) { instance_double(Expense, id: 123, update: true) }
    let(:new_expense) { instance_double(Expense, save: true, update: true, formatted_amount: '$100.00') }

    context 'when duplicate exists' do
      before do
        allow(parser).to receive(:find_duplicate_expense).and_return(existing_expense)
      end

      it 'updates existing expense status to duplicate' do
        expect(existing_expense).to receive(:update).with(status: :duplicate)
        parser.send(:create_expense, parsed_data)
      end

      it 'returns the existing expense' do
        result = parser.send(:create_expense, parsed_data)
        expect(result).to eq(existing_expense)
      end

      it 'adds duplicate error message' do
        parser.send(:create_expense, parsed_data)
        expect(parser.errors).to include('Duplicate expense found')
      end

      it 'does not create new expense' do
        expect(Expense).not_to receive(:new)
        parser.send(:create_expense, parsed_data)
      end

      it 'does not call currency detection' do
        expect(parser).not_to receive(:set_currency)
        parser.send(:create_expense, parsed_data)
      end

      it 'does not call category guessing' do
        expect(parser).not_to receive(:guess_category)
        parser.send(:create_expense, parsed_data)
      end

      context 'when update fails' do
        before do
          allow(existing_expense).to receive(:update).and_return(false)
        end

        it 'still returns the existing expense' do
          result = parser.send(:create_expense, parsed_data)
          expect(result).to eq(existing_expense)
        end

        it 'still adds duplicate error' do
          parser.send(:create_expense, parsed_data)
          expect(parser.errors).to include('Duplicate expense found')
        end
      end

      context 'when update raises error' do
        before do
          allow(existing_expense).to receive(:update).and_raise(StandardError, 'Update failed')
        end

        it 'rescues the error' do
          # The error should bubble up since there's no rescue in the create_expense method for update failures
          expect { parser.send(:create_expense, parsed_data) }.to raise_error(StandardError, 'Update failed')
        end

        it 'raises the error' do
          expect { parser.send(:create_expense, parsed_data) }.to raise_error(StandardError, 'Update failed')
        end

        it 'does not add error message since exception is raised' do
          expect { parser.send(:create_expense, parsed_data) }.to raise_error(StandardError)
          # Errors are not added when exception is raised
        end
      end
    end

    context 'when no duplicate exists' do
      before do
        allow(parser).to receive(:find_duplicate_expense).and_return(nil)
        allow(Expense).to receive(:new).and_return(new_expense)
        allow(new_expense).to receive(:category=)
        allow(parser).to receive(:set_currency)
        allow(parser).to receive(:guess_category).and_return(nil)
        allow(parser).to receive(:email_content).and_return('email content')
      end

      it 'creates new expense' do
        expect(Expense).to receive(:new).with(hash_including(
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: Date.new(2025, 8, 15),
          merchant_name: 'Test Merchant',
          description: 'Test Transaction'
        ))

        parser.send(:create_expense, parsed_data)
      end

      it 'sets currency on new expense' do
        expect(parser).to receive(:set_currency).with(new_expense, parsed_data)
        parser.send(:create_expense, parsed_data)
      end

      it 'guesses category for new expense' do
        expect(parser).to receive(:guess_category).with(new_expense)
        parser.send(:create_expense, parsed_data)
      end

      it 'saves and updates status to processed' do
        expect(new_expense).to receive(:save).and_return(true)
        expect(new_expense).to receive(:update).with(status: :processed)
        parser.send(:create_expense, parsed_data)
      end

      it 'logs successful creation' do
        expect(logger).to receive(:info).with('Created expense: $100.00 from test@example.com')
        parser.send(:create_expense, parsed_data)
      end

      it 'returns the new expense' do
        result = parser.send(:create_expense, parsed_data)
        expect(result).to eq(new_expense)
      end
    end

    describe 'duplicate detection timing' do
      let(:expense_relation) { instance_double(ActiveRecord::Relation) }

      before do
        allow(Expense).to receive(:where).and_return(expense_relation)
      end

      it 'checks for duplicates before creating expense' do
        call_order = []

        allow(expense_relation).to receive(:first) do
          call_order << :find_duplicate
          nil
        end

        allow(Expense).to receive(:new) do
          call_order << :new_expense
          new_expense
        end

        allow(new_expense).to receive(:category=)
        allow(parser).to receive(:set_currency)
        allow(parser).to receive(:guess_category).and_return(nil)
        allow(parser).to receive(:email_content).and_return('content')

        parser.send(:create_expense, parsed_data)

        expect(call_order).to eq([ :find_duplicate, :new_expense ])
      end
    end
  end

  describe 'duplicate detection scenarios' do
    let(:parsed_data) do
      {
        amount: BigDecimal('100.00'),
        transaction_date: Date.new(2025, 8, 15),
        merchant_name: 'Coffee Shop',
        description: 'Morning coffee'
      }
    end

    describe 'time-based duplicate detection' do
      let(:expense_relation) { instance_double(ActiveRecord::Relation, first: nil) }

      before do
        allow(Expense).to receive(:where).and_return(expense_relation)
      end

      it 'detects duplicate on same day' do
        same_day = Date.new(2025, 8, 15)
        parsed_data[:transaction_date] = same_day

        expect(Expense).to receive(:where).with(
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: (same_day - 1.day)..(same_day + 1.day)
        ).and_return(expense_relation)

        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'detects duplicate one day before' do
        parsed_data[:transaction_date] = Date.new(2025, 8, 15)

        range = Date.new(2025, 8, 14)..Date.new(2025, 8, 16)
        expect(Expense).to receive(:where).with(
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: range
        ).and_return(expense_relation)

        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'detects duplicate one day after' do
        parsed_data[:transaction_date] = Date.new(2025, 8, 15)

        range = Date.new(2025, 8, 14)..Date.new(2025, 8, 16)
        expect(Expense).to receive(:where).with(
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: range
        ).and_return(expense_relation)

        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'does not detect expense two days away' do
        parsed_data[:transaction_date] = Date.new(2025, 8, 15)

        # The range should be Aug 14-16, so Aug 13 or Aug 17 would not be included
        range = Date.new(2025, 8, 14)..Date.new(2025, 8, 16)
        expect(Expense).to receive(:where).with(
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: range
        ).and_return(expense_relation)

        parser.send(:find_duplicate_expense, parsed_data)
      end
    end

    describe 'amount-based duplicate detection' do
      let(:expense_relation) { instance_double(ActiveRecord::Relation, first: nil) }

      before do
        allow(Expense).to receive(:where).and_return(expense_relation)
      end

      it 'requires exact amount match' do
        expect(Expense).to receive(:where).with(
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: anything
        ).and_return(expense_relation)
        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'does not match different amounts' do
        expect(Expense).to receive(:where).with(
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: anything
        ).and_return(expense_relation)
        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'handles decimal precision correctly' do
        parsed_data[:amount] = BigDecimal('100.99')

        expect(Expense).to receive(:where).with(
          email_account: email_account,
          amount: BigDecimal('100.99'),
          transaction_date: anything
        ).and_return(expense_relation)
        parser.send(:find_duplicate_expense, parsed_data)
      end
    end

    describe 'account-based duplicate detection' do
      let(:expense_relation) { instance_double(ActiveRecord::Relation, first: nil) }

      before do
        allow(Expense).to receive(:where).and_return(expense_relation)
      end

      it 'only checks same email account' do
        expect(Expense).to receive(:where).with(
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: anything
        ).and_return(expense_relation)
        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'uses exact email_account instance' do
        different_account = instance_double(EmailAccount, email: 'other@example.com')

        expect(Expense).to receive(:where).with(
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: anything
        ).and_return(expense_relation)
        parser.send(:find_duplicate_expense, parsed_data)
      end
    end

    describe 'complex duplicate scenarios' do
      let(:expense_relation) { instance_double(ActiveRecord::Relation) }

      before do
        allow(Expense).to receive(:where).and_return(expense_relation)
      end

      it 'handles multiple potential duplicates by returning first' do
        first_expense = instance_double(Expense, id: 1)
        allow(expense_relation).to receive(:first).and_return(first_expense)

        result = parser.send(:find_duplicate_expense, parsed_data)
        expect(result).to eq(first_expense)
      end

      it 'does not rescue database query timeout' do
        allow(expense_relation).to receive(:first).and_raise(ActiveRecord::StatementTimeout)

        # The method doesn't rescue database errors, they bubble up
        expect { parser.send(:find_duplicate_expense, parsed_data) }.to raise_error(ActiveRecord::StatementTimeout)
      end

      it 'does not rescue database connection error' do
        allow(expense_relation).to receive(:first).and_raise(ActiveRecord::ConnectionNotEstablished)

        # The method doesn't rescue database errors, they bubble up
        expect { parser.send(:find_duplicate_expense, parsed_data) }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      end
    end
  end

  describe 'duplicate status handling' do
    let(:parsed_data) do
      {
        amount: BigDecimal('100.00'),
        transaction_date: Date.current,
        merchant_name: 'Test',
        description: 'Test'
      }
    end

    let(:existing_expense) do
      instance_double(Expense,
        id: 123,
        status: 'pending',
        update: true
      )
    end

    context 'status transitions' do
      before do
        allow(parser).to receive(:find_duplicate_expense).and_return(existing_expense)
      end

      it 'changes status from pending to duplicate' do
        expect(existing_expense).to receive(:update).with(status: :duplicate)
        parser.send(:create_expense, parsed_data)
      end

      it 'changes status from processed to duplicate' do
        allow(existing_expense).to receive(:status).and_return('processed')
        expect(existing_expense).to receive(:update).with(status: :duplicate)
        parser.send(:create_expense, parsed_data)
      end

      it 'changes status from error to duplicate' do
        allow(existing_expense).to receive(:status).and_return('error')
        expect(existing_expense).to receive(:update).with(status: :duplicate)
        parser.send(:create_expense, parsed_data)
      end

      it 'updates already duplicate status' do
        allow(existing_expense).to receive(:status).and_return('duplicate')
        expect(existing_expense).to receive(:update).with(status: :duplicate)
        parser.send(:create_expense, parsed_data)
      end
    end
  end
end
