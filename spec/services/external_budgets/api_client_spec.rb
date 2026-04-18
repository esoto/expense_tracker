# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe Services::ExternalBudgets::ApiClient, :unit do
  let(:base_url) { "https://salary-calc.estebansoto.dev" }
  let(:source) { create(:external_budget_source, base_url: base_url, api_token: "tok") }
  let(:path) { "#{base_url}/api/v1/monthly_budgets/current" }

  subject(:client) { described_class.new(source: source) }

  describe "#fetch_current_budget" do
    let(:valid_body) do
      {
        monthly_budget: {
          id: 42, year: 2026, month: 4,
          exchange_rate: "503.0",
          shared_with_household: false,
          updated_at: "2026-04-17T15:00:00Z"
        },
        budget_items: [
          {
            id: 101, name: "Rent", category: "fixed", amount: "800.0",
            currency: "USD", position: 1, paid: false,
            updated_at: "2026-04-15T10:00:00Z"
          }
        ]
      }.to_json
    end

    context "when server returns 200" do
      before do
        stub_request(:get, path)
          .with(headers: { "Authorization" => "Bearer tok", "Accept" => "application/json" })
          .to_return(status: 200, body: valid_body, headers: { "Content-Type" => "application/json" })
      end

      it "returns an ok Result with parsed JSON body" do
        result = client.fetch_current_budget
        expect(result.ok?).to be true
        expect(result.not_modified?).to be false
        expect(result.status).to eq(200)
        expect(result.body).to include("monthly_budget", "budget_items")
        expect(result.body["budget_items"].first["id"]).to eq(101)
      end
    end

    context "when if_modified_since is passed" do
      let(:since) { Time.parse("2026-04-10T00:00:00Z") }

      before do
        stub_request(:get, path)
          .with(headers: { "If-Modified-Since" => since.httpdate })
          .to_return(status: 200, body: valid_body, headers: { "Content-Type" => "application/json" })
      end

      it "sends the If-Modified-Since header in httpdate format" do
        client.fetch_current_budget(if_modified_since: since)
        expect(WebMock).to have_requested(:get, path)
          .with(headers: { "If-Modified-Since" => since.httpdate })
      end
    end

    context "when server returns 304" do
      before do
        stub_request(:get, path).to_return(status: 304, body: "")
      end

      it "returns a not_modified Result with nil body" do
        result = client.fetch_current_budget
        expect(result.status).to eq(304)
        expect(result.body).to be_nil
        expect(result.not_modified?).to be true
        expect(result.ok?).to be false
      end
    end

    context "when server returns 401" do
      before do
        stub_request(:get, path).to_return(status: 401, body: "invalid or expired token")
      end

      it "raises UnauthorizedError with body in message" do
        expect { client.fetch_current_budget }
          .to raise_error(described_class::UnauthorizedError, /invalid or expired token/)
      end
    end

    context "when server returns 404" do
      before do
        stub_request(:get, path).to_return(status: 404, body: "not found")
      end

      it "raises NotFoundError" do
        expect { client.fetch_current_budget }.to raise_error(described_class::NotFoundError)
      end
    end

    context "when server returns 500" do
      before do
        stub_request(:get, path).to_return(status: 500, body: "boom")
      end

      it "raises ServerError with status in message" do
        expect { client.fetch_current_budget }
          .to raise_error(described_class::ServerError, /status=500/)
      end
    end

    context "when the network times out" do
      before do
        stub_request(:get, path).to_raise(Net::OpenTimeout)
      end

      it "raises NetworkError" do
        expect { client.fetch_current_budget }.to raise_error(described_class::NetworkError)
      end
    end

    context "when TLS handshake fails" do
      before do
        stub_request(:get, path).to_raise(OpenSSL::SSL::SSLError.new("bad certificate"))
      end

      it "raises NetworkError" do
        expect { client.fetch_current_budget }
          .to raise_error(described_class::NetworkError, /SSLError/)
      end
    end
  end
end
