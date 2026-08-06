require 'rails_helper'

RSpec.describe Services::EmailProcessing::Parser, type: :service, unit: true do
  let(:email_account) { instance_double(EmailAccount, id: 42, email: 'test@example.com', bank_name: 'TEST_BANK', user: build_stubbed(:user, :admin)) }
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

  let(:db_connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }

  before do
    allow(ParsingRule).to receive_message_chain(:active, :for_bank, :first).and_return(parsing_rule)
    allow(Rails).to receive(:logger).and_return(logger)
    allow(ActiveRecord::Base).to receive(:connection).and_return(db_connection)
    allow(db_connection).to receive(:execute)
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

    # PER (data-loss fix): the hard-discard matcher is now aligned with the
    # DB's own idx_expenses_duplicate_check unique partial index (exact
    # email_account_id + amount + merchant_name + transaction_date, WHERE
    # deleted_at IS NULL) instead of a ±1-day/no-merchant fuzzy match. The
    # old fuzzy match silently dropped legitimate same-amount expenses at
    # different merchants — see 'duplicate detection scenarios' below for
    # the regression coverage.
    describe 'same-calendar-day range calculation' do
      it 'creates a same-day range anchored via #in_time_zone' do
        expected_range = base_date.in_time_zone.all_day

        expect(Expense).to receive(:where).with(
          email_account: email_account,
          amount: BigDecimal('100.00'),
          merchant_name: 'Test Merchant',
          transaction_date: expected_range,
          deleted_at: nil
        )

        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'handles dates at month boundaries' do
        parsed_data[:transaction_date] = Date.new(2025, 8, 1)
        expected_range = Date.new(2025, 8, 1).in_time_zone.all_day

        expect(Expense).to receive(:where).with(hash_including(transaction_date: expected_range))

        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'handles dates at year boundaries' do
        parsed_data[:transaction_date] = Date.new(2025, 1, 1)
        expected_range = Date.new(2025, 1, 1).in_time_zone.all_day

        expect(Expense).to receive(:where).with(hash_including(transaction_date: expected_range))

        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'handles leap year boundaries' do
        parsed_data[:transaction_date] = Date.new(2024, 2, 29)
        expected_range = Date.new(2024, 2, 29).in_time_zone.all_day

        expect(Expense).to receive(:where).with(hash_including(transaction_date: expected_range))

        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'does not span into the previous or next calendar day' do
        expected_range = base_date.in_time_zone.all_day

        expect(Expense).to receive(:where).with(hash_including(transaction_date: expected_range))

        parser.send(:find_duplicate_expense, parsed_data)

        expect(expected_range).not_to cover(base_date.in_time_zone.beginning_of_day - 1.second)
        expect(expected_range).not_to cover(base_date.in_time_zone.end_of_day + 1.second)
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

      it 'uses a same-calendar-day transaction_date range' do
        expect(Expense).to receive(:where).with(hash_including(transaction_date: anything))
        parser.send(:find_duplicate_expense, parsed_data)
      end

      # This is the crux of the data-loss fix: merchant_name now MUST match.
      # The removed test this replaces ("does not consider merchant_name for
      # matching") encoded the bug — it asserted the exact condition that let
      # a second, different-merchant purchase get silently discarded as a
      # "duplicate" of an unrelated one.
      it 'matches by exact merchant_name (was: ignored merchant_name entirely — the data-loss bug)' do
        expect(Expense).to receive(:where).with(hash_including(merchant_name: 'Test Merchant'))
        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'excludes soft-deleted expenses, mirroring the DB index WHERE clause' do
        expect(Expense).to receive(:where).with(hash_including(deleted_at: nil))
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

      it 'does NOT mutate the existing expense status — it is the survivor, not the duplicate' do
        expect(existing_expense).not_to receive(:update)
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
        expect(parser).not_to receive(:categorize_expense)
        parser.send(:create_expense, parsed_data)
      end
    end

    context 'when no duplicate exists' do
      before do
        allow(parser).to receive(:find_duplicate_expense).and_return(nil)
        allow(Expense).to receive(:new).and_return(new_expense)

        allow(parser).to receive(:set_currency)
        allow(parser).to receive(:categorize_expense).and_return(nil)
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
        expect(parser).to receive(:categorize_expense).with(new_expense)
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


        allow(parser).to receive(:set_currency)
        allow(parser).to receive(:categorize_expense).and_return(nil)
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

      it 'detects duplicate on the same day, same merchant' do
        same_day = Date.new(2025, 8, 15)
        parsed_data[:transaction_date] = same_day

        expect(Expense).to receive(:where).with(
          email_account: email_account,
          amount: BigDecimal('100.00'),
          merchant_name: 'Coffee Shop',
          transaction_date: same_day.in_time_zone.all_day,
          deleted_at: nil
        ).and_return(expense_relation)

        parser.send(:find_duplicate_expense, parsed_data)
      end

      # Regression coverage: the old ±1-day tolerance is GONE. A same-amount
      # purchase one calendar day before/after is no longer matched at all —
      # it is created as a brand-new expense (see 'duplicate detection
      # scenarios' real-DB specs below for the end-to-end version of this).
      it 'does not extend the query range to the day before' do
        parsed_data[:transaction_date] = Date.new(2025, 8, 15)
        same_day_range = Date.new(2025, 8, 15).in_time_zone.all_day

        expect(Expense).to receive(:where).with(hash_including(transaction_date: same_day_range)).and_return(expense_relation)

        parser.send(:find_duplicate_expense, parsed_data)

        expect(same_day_range).not_to cover(Date.new(2025, 8, 14).in_time_zone.end_of_day)
      end

      it 'does not extend the query range to the day after' do
        parsed_data[:transaction_date] = Date.new(2025, 8, 15)
        same_day_range = Date.new(2025, 8, 15).in_time_zone.all_day

        expect(Expense).to receive(:where).with(hash_including(transaction_date: same_day_range)).and_return(expense_relation)

        parser.send(:find_duplicate_expense, parsed_data)

        expect(same_day_range).not_to cover(Date.new(2025, 8, 16).in_time_zone.beginning_of_day)
      end

      it 'does not detect expense two days away' do
        parsed_data[:transaction_date] = Date.new(2025, 8, 15)
        same_day_range = Date.new(2025, 8, 15).in_time_zone.all_day

        expect(Expense).to receive(:where).with(hash_including(transaction_date: same_day_range)).and_return(expense_relation)

        parser.send(:find_duplicate_expense, parsed_data)
      end
    end

    describe 'merchant-based duplicate detection' do
      let(:expense_relation) { instance_double(ActiveRecord::Relation, first: nil) }

      before do
        allow(Expense).to receive(:where).and_return(expense_relation)
      end

      it 'requires exact merchant_name match' do
        expect(Expense).to receive(:where).with(hash_including(merchant_name: 'Coffee Shop')).and_return(expense_relation)
        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'passes through a different merchant_name unchanged (no fuzzy matching happens here)' do
        parsed_data[:merchant_name] = 'Another Merchant'

        expect(Expense).to receive(:where).with(hash_including(merchant_name: 'Another Merchant')).and_return(expense_relation)
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
          hash_including(email_account: email_account, amount: BigDecimal('100.00'))
        ).and_return(expense_relation)
        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'handles decimal precision correctly' do
        parsed_data[:amount] = BigDecimal('100.99')

        expect(Expense).to receive(:where).with(
          hash_including(email_account: email_account, amount: BigDecimal('100.99'))
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
          hash_including(email_account: email_account, amount: BigDecimal('100.00'))
        ).and_return(expense_relation)
        parser.send(:find_duplicate_expense, parsed_data)
      end

      it 'uses exact email_account instance' do
        expect(Expense).to receive(:where).with(
          hash_including(email_account: email_account, amount: BigDecimal('100.00'))
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

      # Regression coverage for the duplicate-status-flip bug: regardless of
      # the survivor's prior status, create_expense must never mutate it —
      # the pre-existing expense is legitimate and the incoming email is the
      # duplicate, not the other way around.
      it 'leaves a pending existing expense untouched' do
        expect(existing_expense).not_to receive(:update)
        parser.send(:create_expense, parsed_data)
      end

      it 'leaves a processed existing expense untouched' do
        allow(existing_expense).to receive(:status).and_return('processed')
        expect(existing_expense).not_to receive(:update)
        parser.send(:create_expense, parsed_data)
      end

      it 'leaves a failed existing expense untouched' do
        allow(existing_expense).to receive(:status).and_return('failed')
        expect(existing_expense).not_to receive(:update)
        parser.send(:create_expense, parsed_data)
      end

      it 'leaves an already-duplicate existing expense untouched' do
        allow(existing_expense).to receive(:status).and_return('duplicate')
        expect(existing_expense).not_to receive(:update)
        parser.send(:create_expense, parsed_data)
      end
    end
  end

  describe '#create_expense advisory lock protection', unit: true do
    let(:parsed_data) do
      {
        amount: BigDecimal('100.00'),
        transaction_date: Date.new(2025, 8, 15),
        merchant_name: 'Test Merchant',
        description: 'Test Transaction'
      }
    end

    let(:new_expense) { instance_double(Expense, save: true, update: true, formatted_amount: '$100.00') }

    # Uses db_connection from top-level let/before

    context 'when email_account is present' do
      before do
        allow(parser).to receive(:find_duplicate_expense).and_return(nil)
        allow(Expense).to receive(:new).and_return(new_expense)

        allow(parser).to receive(:set_currency)
        allow(parser).to receive(:categorize_expense).and_return(nil)
        allow(parser).to receive(:email_content).and_return('email content')
      end

      it 'acquires pg_advisory_xact_lock before duplicate check' do
        call_order = []

        allow(db_connection).to receive(:execute) do |sql|
          if sql.include?('pg_advisory_xact_lock')
            call_order << :advisory_lock
          end
        end

        allow(parser).to receive(:find_duplicate_expense) do
          call_order << :find_duplicate
          nil
        end

        parser.send(:create_expense, parsed_data)

        expect(call_order).to eq([ :advisory_lock, :find_duplicate ])
      end

      it 'uses a lock key derived from expense attributes' do
        expect(db_connection).to receive(:execute).with(/pg_advisory_xact_lock\(\d+\)/)
        parser.send(:create_expense, parsed_data)
      end
    end

    context 'when email_account is nil' do
      let(:email_account) { nil }
      let(:parser) { described_class.new(nil, email_data) }

      before do
        allow(ParsingRule).to receive_message_chain(:active, :for_bank, :first).and_return(parsing_rule)
        allow(Rails).to receive(:logger).and_return(logger)
      end

      it 'skips advisory lock when email_account is nil' do
        expect(db_connection).not_to receive(:execute).with(/pg_advisory_xact_lock/)

        # Since email_account is nil, find_parsing_rule returns nil,
        # and create_expense won't normally be called via parse_expense.
        # We test the private method directly and need to stub find_duplicate_expense
        allow(parser).to receive(:find_duplicate_expense).and_return(nil)
        allow(Expense).to receive(:new).and_return(new_expense)

        allow(parser).to receive(:set_currency)
        allow(parser).to receive(:categorize_expense).and_return(nil)
        allow(parser).to receive(:email_content).and_return('email content')

        parser.send(:create_expense, parsed_data)
      end
    end

    context 'when expense.save raises ActiveRecord::RecordNotUnique' do
      let(:conflicting_expense) { instance_double(Expense, id: 999, update: true) }
      let(:expense_relation) { instance_double(ActiveRecord::Relation) }

      before do
        allow(parser).to receive(:find_duplicate_expense).and_return(nil)
        allow(Expense).to receive(:new).and_return(new_expense)

        allow(parser).to receive(:set_currency)
        allow(parser).to receive(:categorize_expense).and_return(nil)
        allow(parser).to receive(:email_content).and_return('email content')
        allow(new_expense).to receive(:save).and_raise(ActiveRecord::RecordNotUnique.new('duplicate key'))
      end

      it 'rescues RecordNotUnique, returns the winner of the race, and does NOT mutate its status' do
        allow(Expense).to receive(:where).and_return(expense_relation)
        allow(expense_relation).to receive(:first).and_return(conflicting_expense)

        result = parser.send(:create_expense, parsed_data)

        expect(conflicting_expense).not_to have_received(:update)
        expect(result).to eq(conflicting_expense)
      end

      it 'adds duplicate error when RecordNotUnique is rescued' do
        allow(Expense).to receive(:where).and_return(expense_relation)
        allow(expense_relation).to receive(:first).and_return(conflicting_expense)

        parser.send(:create_expense, parsed_data)

        expect(parser.errors).to include('Duplicate expense detected via unique constraint')
      end

      it 'returns nil when conflicting record is not found on re-query' do
        allow(Expense).to receive(:where).and_return(expense_relation)
        allow(expense_relation).to receive(:first).and_return(nil)

        result = parser.send(:create_expense, parsed_data)

        expect(result).to be_nil
        expect(parser.errors).to include('Duplicate expense conflict but original not found')
      end
    end
  end

  # Real-database regression coverage for the duplicate-status-flip bug
  # (Obsidian follow-up #7, surfaced during the PR #562 review). Unlike the
  # instance_double-based specs above, this round-trips a REAL persisted
  # Expense through the parser so the assertions can't be satisfied by a
  # mock that merely "isn't called" — they verify the actual DB row and the
  # actual production scope (Expense.by_status) a dashboard/filter view
  # would query. These fail on main today (main flips the survivor's status
  # to :duplicate and drops it out of the `by_status(:processed)` scope).
  describe 'real database integration — duplicate email does not corrupt the survivor', unit: true do
    let(:real_parsing_rule) { create(:parsing_rule, :bac, bank_name: "TEST_DUPSEM_BANK") }
    let(:real_email_account) { create(:email_account, :bac, bank_name: "TEST_DUPSEM_BANK") }
    let(:real_email_data) do
      {
        message_id: 456,
        from: 'notifications@bac.net',
        subject: 'Notificación de transacción',
        date: 'Wed, 02 Aug 2025 14:16:00 +0000',
        body: 'irrelevant — pre_parsed_data bypasses the strategy parser'
      }
    end

    let!(:existing_expense) do
      real_parsing_rule # ensure the parsing rule exists before the account is used
      create(:expense, :processed,
        email_account: real_email_account,
        user: real_email_account.user,
        amount: BigDecimal('100.00'),
        transaction_date: Date.current,
        merchant_name: 'Test Merchant',
        bank_name: "TEST_DUPSEM_BANK")
    end

    let(:duplicate_pre_parsed) do
      {
        amount: BigDecimal('100.00'),
        transaction_date: Date.current,
        merchant_name: 'Test Merchant',
        description: 'Duplicate notification of the same purchase'
      }
    end

    let(:duplicate_parser) do
      Services::EmailProcessing::Parser.new(real_email_account, real_email_data, pre_parsed_data: duplicate_pre_parsed)
    end

    it 'does not create a new expense row for the duplicate email' do
      expect { duplicate_parser.parse_expense }.not_to change(Expense, :count)
    end

    it 'keeps the pre-existing expense processed (does not flip it to duplicate)' do
      duplicate_parser.parse_expense
      expect(existing_expense.reload.status).to eq('processed')
    end

    it 'reports the duplicate via parser errors' do
      duplicate_parser.parse_expense
      expect(duplicate_parser.errors).to include('Duplicate expense found')
    end

    it 'returns the untouched existing expense from parse_expense' do
      result = duplicate_parser.parse_expense
      expect(result).to eq(existing_expense)
    end

    it 'still appears in the status-filtered scope a dashboard/filter view would use' do
      duplicate_parser.parse_expense
      expect(Expense.by_status(:processed)).to include(existing_expense)
      expect(Expense.by_status(:duplicate)).not_to include(existing_expense)
    end
  end

  # Real-database regression coverage for the DATA-LOSS bug this PR fixes.
  # These fail on main today: main's find_duplicate_expense ignores
  # merchant_name and matches on email_account + amount + transaction_date
  # within +/-1 day, so a second, different-merchant purchase of the same
  # amount gets matched against the first and create_expense discards it —
  # no second Expense row is ever created. This is the only duplicate guard
  # on the iPhone Shortcuts webhook path (ProcessEmailJob with no
  # sync_session skips Services::ConflictDetectionService entirely), so the
  # bug is live in production for real users, e.g. two ₡5,000 lunches at
  # different sodas on consecutive days.
  describe 'real database integration — different merchants are never silently discarded (data-loss regression)', unit: true do
    # Unlike the other describe blocks above, these specs go all the way
    # through a real #expense.save (no pre-existing match short-circuits
    # create_expense), which exercises categorize_expense ->
    # Services::Categorization::Engine -> FuzzyMatcher, which calls
    # ActiveRecord::Base.connection.extension_enabled?("pg_trgm"). The
    # top-level `before` block stubs ActiveRecord::Base.connection to a
    # bare instance_double (only #execute is stubbed, for the advisory
    # lock) — restore the real connection here so the full save path works
    # against the actual test database.
    before do
      allow(ActiveRecord::Base).to receive(:connection).and_call_original
      # The full save path also fires Expense#trigger_metrics_refresh ->
      # MetricsRefreshJob.enqueue_debounced -> Rails.logger.debug, which the
      # top-level logger double (error/warn/info only) doesn't stub.
      allow(logger).to receive(:debug)
    end

    let(:dl_parsing_rule) { create(:parsing_rule, :bac, bank_name: "TEST_DATALOSS_BANK") }
    let(:dl_email_account) { create(:email_account, :bac, bank_name: "TEST_DATALOSS_BANK") }

    let!(:first_expense) do
      dl_parsing_rule
      create(:expense, :processed,
        email_account: dl_email_account,
        user: dl_email_account.user,
        amount: BigDecimal('5000.00'),
        transaction_date: Date.new(2026, 1, 10),
        merchant_name: 'Soda La Esquina',
        bank_name: "TEST_DATALOSS_BANK")
    end

    def parser_for(pre_parsed)
      Services::EmailProcessing::Parser.new(
        dl_email_account,
        { message_id: rand(1_000_000), from: 'notifications@bac.net', subject: 'x', date: 'Wed, 02 Aug 2025 14:16:00 +0000', body: 'irrelevant' },
        pre_parsed_data: pre_parsed
      )
    end

    it 'persists a same-amount purchase at a DIFFERENT merchant one day later' do
      second_data = {
        amount: BigDecimal('5000.00'),
        transaction_date: Date.new(2026, 1, 11),
        merchant_name: 'Restaurante El Patio',
        description: 'Almuerzo'
      }

      expect { parser_for(second_data).parse_expense }.to change(Expense, :count).by(1)
      expect(Expense.where(email_account: dl_email_account, amount: BigDecimal('5000.00')).count).to eq(2)
    end

    it 'persists a same-amount, same-day purchase at a DIFFERENT merchant' do
      second_data = {
        amount: BigDecimal('5000.00'),
        transaction_date: Date.new(2026, 1, 10),
        merchant_name: 'Restaurante El Patio',
        description: 'Cena'
      }

      expect { parser_for(second_data).parse_expense }.to change(Expense, :count).by(1)
      expect(Expense.where(email_account: dl_email_account, amount: BigDecimal('5000.00')).count).to eq(2)
    end

    it 'still discards a true duplicate: same amount, same merchant, same day' do
      duplicate_data = {
        amount: BigDecimal('5000.00'),
        transaction_date: Date.new(2026, 1, 10),
        merchant_name: 'Soda La Esquina',
        description: 'Almuerzo, notificación repetida'
      }

      duplicate_parser = parser_for(duplicate_data)

      expect { duplicate_parser.parse_expense }.not_to change(Expense, :count)
      expect(duplicate_parser.errors).to include('Duplicate expense found')
      expect(first_expense.reload.status).to eq('processed')
    end
  end
end
