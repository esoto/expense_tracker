require 'rails_helper'

RSpec.describe "Expenses Dashboard", type: :request do
  describe "GET /expenses/dashboard" do
    it "displays the dashboard with sync status widget" do
      # Create test data
      email_account = create(:email_account, active: true)
      create(:expense, email_account: email_account, amount: 100, transaction_date: Date.current)

      # Mock SolidQueue::Job
      jobs_relation = double("jobs_relation", exists?: false, count: 0)
      allow(SolidQueue::Job).to receive(:where)
        .with(class_name: "ProcessEmailsJob", finished_at: nil)
        .and_return(double("intermediate", where: jobs_relation))

      get dashboard_expenses_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Dashboard de Gastos")
      expect(response.body).to include("Sincronización de Correos")
      expect(response.body).to include("No hay sincronización activa")
    end

    it "displays active sync session when present" do
      # Create test data
      email_account = create(:email_account, active: true)
      sync_session = create(:sync_session, :running)
      create(:sync_session_account,
        sync_session: sync_session,
        email_account: email_account,
        status: 'processing',
        total_emails: 100,
        processed_emails: 45
      )

      # Mock SolidQueue::Job
      jobs_relation = double("jobs_relation", exists?: false, count: 0)
      allow(SolidQueue::Job).to receive(:where)
        .with(class_name: "ProcessEmailsJob", finished_at: nil)
        .and_return(double("intermediate", where: jobs_relation))

      get dashboard_expenses_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Progreso General")
      expect(response.body).to include("45%")
      expect(response.body).to include("gastos detectados")
    end
  end
end
