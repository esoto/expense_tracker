require "rails_helper"

RSpec.describe "POST /api/webhooks/add_expense", type: :request do
  let(:api_token) { create(:api_token) }

  let(:auth_headers) do
    {
      "Authorization" => "Bearer #{api_token.token}",
      "Content-Type" => "application/json"
    }
  end

  describe "input validation", :unit do
    context "when the request body is completely missing the expense key" do
      # PR 11: BaseController rescues ParameterMissing via bad_request → 400.
      it "returns 400 JSON instead of 500 HTML" do
        post "/api/webhooks/add_expense",
             params: {}.to_json,
             headers: auth_headers

        expect(response).to have_http_status(:bad_request)
        expect(response.media_type).to eq("application/json")

        json = JSON.parse(response.body)
        expect(json["error"]).to be_present
      end
    end

    context "when expense key is present but body is empty" do
      # PR 11: empty hash still raises ParameterMissing → bad_request → 400.
      it "returns 400 JSON with error message (empty hash triggers ParameterMissing)" do
        post "/api/webhooks/add_expense",
             params: { expense: {} }.to_json,
             headers: auth_headers

        expect(response).to have_http_status(:bad_request)
        expect(response.media_type).to eq("application/json")

        json = JSON.parse(response.body)
        expect(json["error"]).to be_present
      end
    end

    context "with valid expense params" do
      let(:category) { create(:category) }
      # Ensure an active email account exists so default_email_account finds it
      # instead of calling create_default_manual_account (requires admin User).
      let!(:active_email_account) { create(:email_account) }

      it "returns 201 JSON with the created expense" do
        post "/api/webhooks/add_expense",
             params: {
               expense: {
                 amount: 1500.00,
                 description: "Supermercado",
                 merchant_name: "PriceSmart",
                 transaction_date: Date.current.iso8601,
                 category_id: category.id
               }
             }.to_json,
             headers: auth_headers

        expect(response).to have_http_status(:created)
        expect(response.media_type).to eq("application/json")

        json = JSON.parse(response.body)
        expect(json["status"]).to eq("success")
        expect(json["expense"]).to be_present
        expect(json["expense"]["amount"]).to eq(1500.00)
      end
    end

    context "without authentication" do
      it "returns 401 JSON" do
        post "/api/webhooks/add_expense",
             params: { expense: {} }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
        expect(response.media_type).to eq("application/json")
      end
    end
  end
end
