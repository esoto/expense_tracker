# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /bulk_categorizations/export.csv", :unit, type: :request do
  let!(:admin_user) { create(:user, :admin) }
  let!(:email_account) { create(:email_account, user: admin_user) }
  let!(:expense) { create(:expense, email_account: email_account) }

  describe "authentication" do
    context "when unauthenticated" do
      it "returns 401 JSON instead of redirecting to admin login for CSV format", :unit do
        get bulk_categorizations_export_path(format: :csv),
            params: { expense_ids: [ expense.id ] }

        expect(response).to have_http_status(:unauthorized)
        expect(response.content_type).to include("application/json")
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Authentication required")
      end

      it "does not return HTML admin login page for CSV format", :unit do
        get bulk_categorizations_export_path(format: :csv),
            params: { expense_ids: [ expense.id ] }

        expect(response.body).not_to include("<html")
        expect(response.body).not_to include("Iniciar Sesión")
      end

      it "returns 401 for JSON format (pre-existing behavior unchanged)", :unit do
        get bulk_categorizations_export_path(format: :json),
            params: { expense_ids: [ expense.id ] }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Authentication required")
      end
    end

    context "when authenticated" do
      before { sign_in_admin(admin_user) }

      it "returns 200 with CSV content type", :unit do
        csv_data = "id,merchant_name,amount\n#{expense.id},Test Merchant,100.0\n"
        service_double = instance_double(Services::Categorization::BulkCategorizationService)
        allow(Services::Categorization::BulkCategorizationService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:export).with(format: :csv).and_return(csv_data)

        get bulk_categorizations_export_path(format: :csv),
            params: { expense_ids: [ expense.id ] }

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("text/csv")
      end

      it "returns CSV attachment with correct filename", :unit do
        csv_data = "id,merchant_name,amount\n"
        service_double = instance_double(Services::Categorization::BulkCategorizationService)
        allow(Services::Categorization::BulkCategorizationService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:export).with(format: :csv).and_return(csv_data)

        get bulk_categorizations_export_path(format: :csv),
            params: { expense_ids: [ expense.id ] }

        expect(response.headers["Content-Disposition"]).to include("attachment")
        expect(response.headers["Content-Disposition"]).to include("bulk_categorizations_")
        expect(response.headers["Content-Disposition"]).to include(".csv")
      end
    end
  end
end
