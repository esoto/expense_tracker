# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PER-421: Bank breakdown relocation", type: :request, unit: true do
  let(:admin_user) { create(:admin_user) }

  before do
    sign_in_admin(admin_user)
  end

  describe "GET /email_accounts" do
    context "when expenses exist with different banks" do
      let!(:bac_account) { create(:email_account, :bac) }
      let!(:bcr_account) { create(:email_account, :bcr) }

      before do
        create(:expense, bank_name: "BAC", amount: 5000, email_account: bac_account)
        create(:expense, bank_name: "BAC", amount: 3000, email_account: bac_account)
        create(:expense, bank_name: "BCR", amount: 2000, email_account: bcr_account)
      end

      it "renders the bank breakdown section" do
        get email_accounts_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("email_accounts.bank_breakdown.title"))
      end

      it "shows bank names" do
        get email_accounts_path
        expect(response.body).to include("BAC")
        expect(response.body).to include("BCR")
      end

      it "shows summed amounts per bank" do
        get email_accounts_path
        # BAC: 5000 + 3000 = 8000, BCR: 2000
        # Delimiter varies by locale (es uses ".", en uses ",")
        expect(response.body).to match(/₡8[.,]000/)
        expect(response.body).to match(/₡2[.,]000/)
      end

      it "orders banks by highest amount first" do
        get email_accounts_path
        # Extract the bank breakdown section to verify ordering
        title = I18n.t("email_accounts.bank_breakdown.title")
        breakdown_start = response.body.index(title)
        breakdown_section = response.body[breakdown_start..]
        # Within the breakdown section, BAC (8000) should appear before BCR (2000)
        expect(breakdown_section.index("₡8")).to be < breakdown_section.index("₡2")
      end
    end

    context "when no expenses exist" do
      it "shows an empty state message" do
        get email_accounts_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("email_accounts.bank_breakdown.empty"))
      end
    end
  end

  describe "Dashboard v2 (GET /dashboard-v2)" do
    before do
      # Mock SolidQueue::Job used by DashboardService#sync_info
      jobs_relation = double("jobs_relation", exists?: false, count: 0)
      allow(SolidQueue::Job).to receive(:where)
        .with(class_name: "ProcessEmailsJob", finished_at: nil)
        .and_return(double("intermediate", where: jobs_relation))
    end

    it "does NOT contain bank breakdown" do
      get dashboard_v2_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(I18n.t("email_accounts.bank_breakdown.title"))
      expect(response.body).not_to include("bank-breakdown")
    end
  end
end
