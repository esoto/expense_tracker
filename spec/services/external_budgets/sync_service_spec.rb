# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe Services::ExternalBudgets::SyncService, :unit do
  let(:base_url) { "https://salary-calc.estebansoto.dev" }
  let(:source) { create(:external_budget_source, base_url: base_url, api_token: "tok") }
  let(:account) { source.email_account }
  let(:path) { "#{base_url}/api/v1/monthly_budgets/current" }

  let(:period_start) { Date.new(2026, 4, 1) }
  let(:period_end)   { period_start.end_of_month }

  let(:rent_item) do
    {
      id: 101, name: "Rent", category: "fixed", amount: "800.0",
      currency: "USD", position: 1, paid: false,
      updated_at: "2026-04-15T10:00:00Z"
    }
  end

  let(:food_item) do
    {
      id: 102, name: "Food", category: "variable", amount: "200.0",
      currency: "USD", position: 2, paid: false,
      updated_at: "2026-04-15T10:00:00Z"
    }
  end

  def payload(items)
    {
      monthly_budget: {
        id: 42, year: 2026, month: 4,
        exchange_rate: "503.0",
        shared_with_household: false,
        updated_at: "2026-04-17T15:00:00Z"
      },
      budget_items: items
    }.to_json
  end

  subject(:service) { described_class.new(source: source) }

  describe "#call" do
    context "when response is 200 with a new item" do
      before do
        stub_request(:get, path)
          .to_return(status: 200, body: payload([ rent_item ]),
                     headers: { "Content-Type" => "application/json" })
      end

      it "creates a new Budget with expected attributes" do
        expect { service.call }.to change(account.budgets, :count).by(1)

        budget = account.budgets.find_by(external_source: "salary_calculator", external_id: 101)
        expect(budget).to be_present
        expect(budget.name).to eq("Rent")
        expect(budget.amount).to eq(800.0)
        expect(budget.currency).to eq("USD")
        expect(budget.period).to eq("monthly")
        expect(budget.start_date).to eq(period_start)
        expect(budget.end_date).to eq(period_end)
        expect(budget.category_id).to be_nil
        expect(budget.active).to be true
        expect(budget.external_synced_at).to be_within(5.seconds).of(Time.current)
      end

      it "marks the source as succeeded and returns true" do
        expect(service.call).to be true
        source.reload
        expect(source.last_sync_status).to eq("ok")
        expect(source.last_synced_at).to be_within(5.seconds).of(Time.current)
      end
    end

    context "when an existing synced budget is updated" do
      let!(:category) { create(:category) }
      let!(:existing) do
        account.budgets.create!(
          name: "Rent",
          amount: 800.0,
          currency: "USD",
          period: :monthly,
          start_date: period_start,
          end_date: period_end,
          external_source: "salary_calculator",
          external_id: 101,
          category_id: category.id,
          active: true,
          external_synced_at: 1.day.ago
        )
      end

      let(:updated_item) do
        rent_item.merge(amount: "900.0", name: "Rent — new")
      end

      before do
        stub_request(:get, path)
          .to_return(status: 200, body: payload([ updated_item ]),
                     headers: { "Content-Type" => "application/json" })
      end

      it "updates mutable fields and preserves category_id and active" do
        expect { service.call }.not_to change(account.budgets, :count)

        existing.reload
        expect(existing.amount).to eq(900.0)
        expect(existing.name).to eq("Rent — new")
        expect(existing.currency).to eq("USD")
        expect(existing.category_id).to eq(category.id)
        expect(existing.active).to be true
      end
    end

    context "when a previously synced item is dropped from the response" do
      let!(:dropped) do
        account.budgets.create!(
          name: "Gym", amount: 50.0, currency: "USD",
          period: :monthly, start_date: period_start, end_date: period_end,
          external_source: "salary_calculator", external_id: 999,
          active: true, external_synced_at: 1.day.ago
        )
      end

      let!(:native_budget) do
        create(:budget, email_account: account, name: "Native food", amount: 100_000)
      end

      before do
        stub_request(:get, path)
          .to_return(status: 200, body: payload([ rent_item ]),
                     headers: { "Content-Type" => "application/json" })
      end

      it "sets active: false on the dropped external budget" do
        service.call
        expect(dropped.reload.active).to be false
      end

      it "leaves native and unrelated-external budgets untouched" do
        service.call
        expect(native_budget.reload.active).to be true
      end
    end

    context "when response is 304 Not Modified" do
      before do
        stub_request(:get, path).to_return(status: 304, body: "")
      end

      it "does not create or modify any budgets and still marks the source succeeded" do
        expect { service.call }.not_to change(account.budgets, :count)
        expect(service.call).to be true
        expect(source.reload.last_sync_status).to eq("ok")
      end
    end

    context "when the API returns 404 (no budget for current month)" do
      before do
        stub_request(:get, path).to_return(status: 404, body: "not found")
      end

      it "silently succeeds and marks the source succeeded" do
        expect(service.call).to be true
        expect(source.reload.last_sync_status).to eq("ok")
      end
    end

    context "when the API returns 401" do
      before do
        stub_request(:get, path).to_return(status: 401, body: "bad token")
      end

      it "deactivates the source, returns false, does not raise" do
        expect { expect(service.call).to be false }.not_to raise_error
        source.reload
        expect(source.active).to be false
        expect(source.last_sync_status).to eq("failed")
        expect(source.last_sync_error).to include("unauthorized")
      end
    end

    context "when the API returns 500" do
      before do
        stub_request(:get, path).to_return(status: 500, body: "boom")
      end

      it "re-raises ServerError for job-layer retry" do
        expect { service.call }.to raise_error(Services::ExternalBudgets::ApiClient::ServerError)
      end
    end

    context "on a network failure" do
      before do
        stub_request(:get, path).to_raise(Net::OpenTimeout)
      end

      it "re-raises NetworkError for job-layer retry" do
        expect { service.call }.to raise_error(Services::ExternalBudgets::ApiClient::NetworkError)
      end
    end

    context "when source.last_synced_at is present" do
      let(:since) { Time.parse("2026-04-10T00:00:00Z") }

      before do
        source.update!(last_synced_at: since)
        stub_request(:get, path)
          .with(headers: { "If-Modified-Since" => since.httpdate })
          .to_return(status: 304, body: "")
      end

      it "passes it to ApiClient as If-Modified-Since" do
        service.call
        expect(WebMock).to have_requested(:get, path)
          .with(headers: { "If-Modified-Since" => since.httpdate })
      end
    end
  end
end
