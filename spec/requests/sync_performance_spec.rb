require 'rails_helper'

RSpec.describe "SyncPerformance", type: :request do
  describe "GET /sync_performance" do
    it "displays the performance dashboard" do
      # Create test data
      email_account = create(:email_account, active: true)
      sync_session = create(:sync_session, :completed)
      
      # Create some sync metrics
      create(:sync_metric, 
        sync_session: sync_session,
        email_account: email_account,
        metric_type: "account_sync",
        success: true,
        emails_processed: 100,
        duration: 5000,
        started_at: 1.hour.ago
      )
      
      get sync_performance_path
      
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Panel de Rendimiento de Sincronización")
    end
  end
end