# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::BaseController, type: :controller, integration: true do
  # Create a test controller that inherits from BaseController
  controller do
    def index
      render json: { message: "success" }
    end

    def show
      raise ActiveRecord::RecordNotFound, "Could not find record"
    end

    def create
      expense = Expense.new
      expense.errors.add(:base, "Name can't be blank")
      raise ActiveRecord::RecordInvalid.new(expense)
    end

    def update
      raise ActionController::ParameterMissing, "param is missing or the value is empty: required_param"
    end

    def destroy
      raise StandardError, "Unexpected error occurred"
    end
  end

  let(:api_token) { create(:api_token) }

  describe "Authentication", integration: true do
    context "with valid token" do
      before do
        request.headers["Authorization"] = "Bearer #{api_token.token}"
      end

      it "allows access to the endpoint" do
        get :index
        expect(response).to have_http_status(:ok)
      end

      it "sets the current API token" do
        get :index
        expect(controller.instance_variable_get(:@current_api_token)).to eq(api_token)
      end

      it "updates token last_used_at" do
        expect {
          get :index
        }.to change { api_token.reload.last_used_at }
      end
    end

    context "without token" do
      it "returns 401 unauthorized" do
        get :index
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq("Missing API token")
      end
    end

    context "with invalid token" do
      before do
        request.headers["Authorization"] = "Bearer invalid_token"
      end

      it "returns 401 unauthorized" do
        get :index
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq("Invalid or expired API token")
      end
    end

    context "with expired token" do
      let(:expired_token) { create(:api_token, expires_at: 1.day.from_now) }

      before do
        # Manually expire the token after creation to bypass validation
        expired_token.update_column(:expires_at, 1.day.ago)
        request.headers["Authorization"] = "Bearer #{expired_token.token}"
      end

      it "returns 401 unauthorized" do
        get :index
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "Error Handling", integration: true do
    before do
      request.headers["Authorization"] = "Bearer #{api_token.token}"
    end

    context "ActiveRecord::RecordNotFound" do
      it "returns 404 with error message" do
        get :show, params: { id: 1 }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Could not find record")
        expect(json["status"]).to eq(404)
      end
    end

    context "ActiveRecord::RecordInvalid" do
      it "returns 422 with validation errors" do
        post :create

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq(422)
        expect(json["errors"]).to be_an(Array)
      end
    end

    context "ActionController::ParameterMissing" do
      it "returns 400 bad request" do
        patch :update, params: { id: 1 }

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq(400)
        expect(json["error"]).to include("param is missing")
      end
    end

    context "StandardError" do
      it "returns 500 internal server error" do
        allow_any_instance_of(ActionDispatch::Request).to receive(:request_id).and_return("test-error-id")
        delete :destroy, params: { id: 1 }

        expect(response).to have_http_status(:internal_server_error)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Internal server error")
        expect(json["status"]).to eq(500)
        expect(json["request_id"]).to eq("test-error-id")
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/Unexpected error occurred/)
        expect(Rails.logger).to receive(:error).with(/api\/base_controller_spec/)

        delete :destroy, params: { id: 1 }
      end
    end
  end

  describe "Headers", integration: true do
    before do
      request.headers["Authorization"] = "Bearer #{api_token.token}"
    end

    it "sets API version header" do
      get :index
      expect(response.headers["X-API-Version"]).to eq("v1")
    end

    it "sets request ID header" do
      request.headers["X-Request-ID"] = "test-request-id-123"
      allow_any_instance_of(ActionDispatch::Request).to receive(:request_id).and_return("test-request-id-123")
      get :index
      expect(response.headers["X-Request-ID"]).to eq("test-request-id-123")
    end

    it "skips CSRF protection" do
      expect(controller).to receive(:verify_authenticity_token).never
      get :index
    end
  end

  describe "Request Logging", integration: true do
    before do
      request.headers["Authorization"] = "Bearer #{api_token.token}"
    end

    it "logs API requests" do
      expect(Rails.logger).to receive(:info).with(/API Request: GET.*Token: #{api_token.name}.*Request ID:/)

      get :index
    end
  end

  describe "#render_success", integration: true do
    controller do
      def index
        render_success({ data: "test" })
      end

      def show
        render_success({ data: "created" }, status: :created)
      end
    end

    before do
      request.headers["Authorization"] = "Bearer #{api_token.token}"
    end

    it "renders success response with default status" do
      get :index

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("success")
      expect(json["data"]).to eq("test")
    end

    it "renders success response with custom status" do
      get :show, params: { id: 1 }

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("success")
    end
  end

  describe "#render_error", integration: true do
    controller do
      def index
        render_error("Something went wrong", [ "Error 1", "Error 2" ])
      end

      def show
        render_error("Not found", [], status: :not_found)
      end
    end

    before do
      request.headers["Authorization"] = "Bearer #{api_token.token}"
    end

    it "renders error response with default status" do
      allow_any_instance_of(ActionDispatch::Request).to receive(:request_id).and_return("test-render-error-id")
      get :index

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Something went wrong")
      expect(json["errors"]).to eq([ "Error 1", "Error 2" ])
      expect(json["request_id"]).to eq("test-render-error-id")
    end

    it "renders error response with custom status" do
      get :show, params: { id: 1 }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
    end
  end
end
