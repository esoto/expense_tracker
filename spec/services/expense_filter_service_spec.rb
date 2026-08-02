# frozen_string_literal: true

require "rails_helper"
require "benchmark"

RSpec.describe Services::ExpenseFilterService, type: :service do
  let(:email_account) { create(:email_account, provider: "gmail", email: "test@example.com", bank_name: "BAC", active: true) }
  let(:category) { Category.create!(name: "Food", color: "#FF0000") }

  before do
    # Create test expenses
    Expense.create!(
      email_account: email_account,
      user: email_account.user,
      amount: 100.00,
      transaction_date: Date.current,
      merchant_name: "Test Store",
      category: category,
      status: "processed",
      currency: "crc"
    )

    Expense.create!(
      email_account: email_account,
      user: email_account.user,
      amount: 200.00,
      transaction_date: 1.week.ago,
      merchant_name: "Another Store",
      category: nil,
      status: "pending",
      currency: "crc"
    )

    Expense.create!(
      email_account: email_account,
      user: email_account.user,
      amount: 50.00,
      transaction_date: 1.month.ago,
      merchant_name: "Old Store",
      category: category,
      status: "processed",
      currency: "crc"
    )
  end

  describe "#call" do
    context "with no filters" do
      let(:service) { described_class.new(account_ids: [ email_account.id ]) }

      it "returns all expenses" do
        result = service.call
        expect(result).to be_success
        expect(result.expenses.count).to eq(3)
        expect(result.total_count).to eq(3)
      end

      it "includes performance metrics" do
        result = service.call
        expect(result.performance_metrics).to include(
          :query_time_ms,
          :cached,
          :index_used,
          :queries_executed,
          :rows_examined
        )
        expect(result.performance_metrics[:query_time_ms]).to be < 50
      end
    end

    context "with date range filter" do
      let(:service) do
        described_class.new(
          account_ids: [ email_account.id ],
          start_date: 2.weeks.ago,
          end_date: Date.current
        )
      end

      it "filters expenses by date" do
        result = service.call
        expect(result.expenses.count).to eq(2)
        expect(result.expenses.map(&:merchant_name)).to include("Test Store", "Another Store")
      end
    end

    context "with category filter" do
      let(:service) do
        described_class.new(
          account_ids: [ email_account.id ],
          category_ids: [ category.id ]
        )
      end

      it "filters expenses by category" do
        result = service.call
        expect(result.expenses.count).to eq(2)
        expect(result.expenses.all? { |e| e.category_id == category.id }).to be true
      end
    end

    context "with uncategorized filter" do
      let(:service) do
        described_class.new(
          account_ids: [ email_account.id ],
          category_ids: [ "uncategorized" ]
        )
      end

      it "returns only uncategorized expenses" do
        result = service.call
        expect(result.expenses.count).to eq(1)
        expect(result.expenses.first.category_id).to be_nil
      end
    end

    context "with amount range filter" do
      let(:service) do
        described_class.new(
          account_ids: [ email_account.id ],
          min_amount: 75,
          max_amount: 150
        )
      end

      it "filters expenses by amount range" do
        result = service.call
        expect(result.expenses.count).to eq(1)
        expect(result.expenses.first.amount).to eq(100.00)
      end
    end

    context "with search filter" do
      let(:service) do
        described_class.new(
          account_ids: [ email_account.id ],
          search_query: "Test"
        )
      end

      it "searches expenses by merchant name" do
        result = service.call
        expect(result.expenses.count).to eq(1)
        expect(result.expenses.first.merchant_name).to eq("Test Store")
      end
    end

    context "with pagination" do
      let(:service) do
        described_class.new(
          account_ids: [ email_account.id ],
          page: 1,
          per_page: 2
        )
      end

      it "paginates results" do
        result = service.call
        expect(result.expenses.count).to eq(2)
        expect(result.total_count).to eq(3)
        expect(result.metadata[:page]).to eq(1)
        expect(result.metadata[:per_page]).to eq(2)
      end
    end

    context "with sorting" do
      let(:service) do
        described_class.new(
          account_ids: [ email_account.id ],
          sort_by: "amount",
          sort_direction: "asc"
        )
      end

      it "sorts results" do
        result = service.call
        amounts = result.expenses.map(&:amount)
        expect(amounts).to eq(amounts.sort)
      end
    end

    context "performance" do
      before do
        # Create more expenses for performance testing
        50.times do |i|
          Expense.create!(
            email_account: email_account,
            user: email_account.user,
            amount: rand(10..1000),
            transaction_date: rand(90).days.ago,
            merchant_name: "Store #{i}",
            category: [ category, nil ].sample,
            status: [ "pending", "processed" ].sample,
            currency: "crc"
          )
        end
      end

      it "completes complex queries within 50ms", performance: true do
        service = described_class.new(
          account_ids: [ email_account.id ],
          start_date: 30.days.ago,
          end_date: Date.current,
          category_ids: [ category.id ],
          min_amount: 50,
          max_amount: 500,
          search_query: "Store"
        )

        result = nil
        time = Benchmark.realtime { result = service.call }

        expect(time * 1000).to be < 50 # Convert to ms
        expect(result).to be_success
      end

      it "uses indexes for queries" do
        service = described_class.new(
          account_ids: [ email_account.id ],
          start_date: 30.days.ago,
          end_date: Date.current
        )

        result = service.call
        expect(result.performance_metrics[:index_used]).to be true
      end
    end

    # REGRESSION: twin of the MetricsCalculator timezone boundary bug (PR
    # #561) / ExpensesController (PR #564). #calculate_period_range,
    # #filter_by_dates, and #parse_date_range used to build transaction_date
    # range endpoints via bare Date#beginning_of_day/end_of_day, which
    # convert through the system/Postgres session time zone rather than the
    # app's configured Time.zone ("Central America", -06:00) — so expenses
    # exactly at local midnight could land on the wrong side of a
    # period/filter boundary. Fixed by anchoring every endpoint via
    # #in_time_zone.
    context "with expenses exactly at local midnight boundaries" do
      before { Expense.where(email_account: email_account).delete_all }

      context "with a period filter" do
        let(:service) do
          described_class.new(account_ids: [ email_account.id ], period: "month")
        end

        before do
          # 00:00:00 local time on the first day of the current month — must count
          Expense.create!(
            email_account: email_account,
            user: email_account.user,
            amount: 10.00,
            transaction_date: Date.current.beginning_of_month.in_time_zone.beginning_of_day,
            merchant_name: "Boundary Start",
            currency: "crc"
          )

          # 23:59:59 local time on the last day of the current month — must count
          Expense.create!(
            email_account: email_account,
            user: email_account.user,
            amount: 20.00,
            transaction_date: Date.current.end_of_month.in_time_zone.end_of_day,
            merchant_name: "Boundary End",
            currency: "crc"
          )

          # 00:00:00 local time the day AFTER the month ends — must NOT count
          Expense.create!(
            email_account: email_account,
            user: email_account.user,
            amount: 999.00,
            transaction_date: (Date.current.end_of_month + 1.day).in_time_zone.beginning_of_day,
            merchant_name: "Outside Boundary",
            currency: "crc"
          )
        end

        it "includes both midnight-boundary expenses and excludes the one after the period ends" do
          result = service.call
          expect(result.total_count).to eq(2)
          expect(result.expenses.map(&:amount)).to contain_exactly(10.00, 20.00)
        end
      end

      context "with an explicit date_from/date_to range" do
        let(:from_date) { Date.current - 5.days }
        let(:to_date) { Date.current - 3.days }
        let(:service) do
          described_class.new(account_ids: [ email_account.id ], date_from: from_date, date_to: to_date)
        end

        before do
          Expense.create!(
            email_account: email_account,
            user: email_account.user,
            amount: 10.00,
            transaction_date: from_date.in_time_zone.beginning_of_day,
            merchant_name: "Boundary Start",
            currency: "crc"
          )

          Expense.create!(
            email_account: email_account,
            user: email_account.user,
            amount: 20.00,
            transaction_date: to_date.in_time_zone.end_of_day,
            merchant_name: "Boundary End",
            currency: "crc"
          )

          Expense.create!(
            email_account: email_account,
            user: email_account.user,
            amount: 999.00,
            transaction_date: (to_date + 1.day).in_time_zone.beginning_of_day,
            merchant_name: "Outside Boundary",
            currency: "crc"
          )
        end

        it "includes both midnight-boundary expenses and excludes the one after the range ends" do
          result = service.call
          expect(result.total_count).to eq(2)
          expect(result.expenses.map(&:amount)).to contain_exactly(10.00, 20.00)
        end
      end

      context "with traditional start_date/end_date filters" do
        let(:start_date) { Date.current - 5.days }
        let(:end_date) { Date.current - 3.days }
        let(:service) do
          described_class.new(account_ids: [ email_account.id ], start_date: start_date, end_date: end_date)
        end

        before do
          Expense.create!(
            email_account: email_account,
            user: email_account.user,
            amount: 10.00,
            transaction_date: start_date.in_time_zone.beginning_of_day,
            merchant_name: "Boundary Start",
            currency: "crc"
          )

          Expense.create!(
            email_account: email_account,
            user: email_account.user,
            amount: 20.00,
            transaction_date: end_date.in_time_zone.end_of_day,
            merchant_name: "Boundary End",
            currency: "crc"
          )

          Expense.create!(
            email_account: email_account,
            user: email_account.user,
            amount: 999.00,
            transaction_date: (end_date + 1.day).in_time_zone.beginning_of_day,
            merchant_name: "Outside Boundary",
            currency: "crc"
          )
        end

        it "includes both midnight-boundary expenses and excludes the one after the range ends" do
          result = service.call
          expect(result.total_count).to eq(2)
          expect(result.expenses.map(&:amount)).to contain_exactly(10.00, 20.00)
        end
      end
    end
  end

  describe "#to_json" do
    let(:service) { described_class.new(account_ids: [ email_account.id ]) }

    it "returns JSON representation" do
      result = service.call
      json = JSON.parse(result.to_json)

      expect(json).to have_key("data")
      expect(json).to have_key("meta")
      expect(json["meta"]).to include(
        "total",
        "page",
        "per_page",
        "filters_applied",
        "sort",
        "performance"
      )
    end
  end

  # PER-183: Pagination page 2 shows 0 expenses despite records existing
  # Root cause: page param arrives as String from HTTP params; "2" - 1 raises TypeError
  describe "pagination with string page params (PER-183)", :unit do
    before do
      # Ensure we have 3 expenses (1 from outer before + 2 more here)
      # to test page 2 with per_page: 2
      Expense.create!(
        email_account: email_account,
        user: email_account.user,
        amount: 75.00,
        transaction_date: 2.weeks.ago,
        merchant_name: "Extra Store D",
        status: "processed",
        currency: "crc"
      )
    end

    context "when page is a string from HTTP params" do
      it "handles page: '1' without error" do
        service = described_class.new(
          account_ids: [ email_account.id ],
          page: "1",
          per_page: 2
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.expenses.count).to eq(2)
        expect(result.total_count).to eq(4)
        expect(result.metadata[:page]).to eq(1)
        expect(result.performance_metrics[:error]).not_to be true
      end

      it "handles page: '2' without raising TypeError" do
        service = described_class.new(
          account_ids: [ email_account.id ],
          page: "2",
          per_page: 2
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.expenses.count).to eq(2)
        expect(result.total_count).to eq(4)
        expect(result.performance_metrics[:error]).not_to be true
      end

      it "does NOT return 0 expenses on page 2 when records exist (the bug)" do
        service = described_class.new(
          account_ids: [ email_account.id ],
          page: "2",
          per_page: 2
        )
        result = service.call

        # Before fix: "2" - 1 raised TypeError → rescue → total_count: 0
        expect(result.total_count).not_to eq(0)
        expect(result.expenses).not_to be_empty
      end
    end

    context "when page is nil" do
      it "defaults to page 1" do
        service = described_class.new(
          account_ids: [ email_account.id ],
          page: nil,
          per_page: 2
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.expenses.count).to eq(2)
        expect(result.metadata[:page]).to eq(1)
      end
    end

    context "when page is '0' (invalid boundary)" do
      it "clamps to page 1" do
        service = described_class.new(
          account_ids: [ email_account.id ],
          page: "0",
          per_page: 2
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.expenses.count).to eq(2)
        expect(result.metadata[:page]).to eq(1)
      end
    end

    context "when page is '-1' (negative string)" do
      it "clamps to page 1" do
        service = described_class.new(
          account_ids: [ email_account.id ],
          page: "-1",
          per_page: 2
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.expenses.count).to eq(2)
        expect(result.metadata[:page]).to eq(1)
      end
    end

    context "when page is 0 (integer zero)" do
      it "clamps to page 1" do
        service = described_class.new(
          account_ids: [ email_account.id ],
          page: 0,
          per_page: 2
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.expenses.count).to eq(2)
        expect(result.metadata[:page]).to eq(1)
      end
    end

    context "when page is -1 (negative integer)" do
      it "clamps to page 1" do
        service = described_class.new(
          account_ids: [ email_account.id ],
          page: -1,
          per_page: 2
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.expenses.count).to eq(2)
        expect(result.metadata[:page]).to eq(1)
      end
    end

    context "when page is 'abc' (non-numeric string)" do
      it "clamps to page 1 (.to_i returns 0 → clamped to 1)" do
        service = described_class.new(
          account_ids: [ email_account.id ],
          page: "abc",
          per_page: 2
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.expenses.count).to eq(2)
        expect(result.metadata[:page]).to eq(1)
      end
    end
  end

  describe "#set_defaults page coercion (PER-183)", :unit do
    it "converts string page to integer" do
      service = described_class.new(account_ids: [ email_account.id ], page: "3")
      expect(service.page).to eq(3)
    end

    it "converts string '0' to minimum page 1" do
      service = described_class.new(account_ids: [ email_account.id ], page: "0")
      expect(service.page).to eq(1)
    end

    it "converts nil page to 1" do
      service = described_class.new(account_ids: [ email_account.id ], page: nil)
      expect(service.page).to eq(1)
    end

    it "converts negative string page to 1" do
      service = described_class.new(account_ids: [ email_account.id ], page: "-5")
      expect(service.page).to eq(1)
    end

    it "converts negative integer page to 1" do
      service = described_class.new(account_ids: [ email_account.id ], page: -3)
      expect(service.page).to eq(1)
    end

    it "converts integer 0 to page 1" do
      service = described_class.new(account_ids: [ email_account.id ], page: 0)
      expect(service.page).to eq(1)
    end

    it "converts non-numeric string 'abc' to page 1 (.to_i returns 0)" do
      service = described_class.new(account_ids: [ email_account.id ], page: "abc")
      expect(service.page).to eq(1)
    end

    it "keeps valid integer pages unchanged" do
      service = described_class.new(account_ids: [ email_account.id ], page: 5)
      expect(service.page).to eq(5)
    end
  end
end
