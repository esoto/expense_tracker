require 'rails_helper'

RSpec.describe SyncPerformanceController, type: :controller do
  describe "GET #index" do
    let!(:sync_session) { create(:sync_session) }
    let!(:email_account) { create(:email_account) }

    before do
      # Create some test metrics
      create_list(:sync_metric, 5, :account_sync,
        sync_session: sync_session,
        email_account: email_account,
        started_at: 1.hour.ago
      )

      create_list(:sync_metric, 3, :failed,
        sync_session: sync_session,
        started_at: 2.hours.ago
      )
    end

    context "with HTML format" do
      it "returns success" do
        get :index
        expect(response).to have_http_status(:success)
      end

      it "assigns metrics summary" do
        get :index
        expect(assigns(:metrics_summary)).to be_present
        expect(assigns(:metrics_summary)).to include(
          :total_syncs,
          :success_rate,
          :average_duration,
          :processing_rate
        )
      end

      it "assigns performance data" do
        get :index
        expect(assigns(:performance_data)).to be_present
        expect(assigns(:performance_data)).to include(
          :timeline,
          :duration_trend,
          :emails_trend,
          :success_rate_trend
        )
      end

      it "assigns account metrics" do
        get :index
        expect(assigns(:account_metrics)).to be_present
        expect(assigns(:account_metrics)).to be_an(Array)
      end

      it "assigns error analysis" do
        get :index
        expect(assigns(:error_analysis)).to be_present
        expect(assigns(:error_analysis)).to include(
          :total_errors,
          :error_rate,
          :error_types
        )
      end

      it "assigns peak times" do
        get :index
        expect(assigns(:peak_times)).to be_present
        expect(assigns(:peak_times)).to include(
          :hourly,
          :daily,
          :peak_hours
        )
      end
    end

    context "with period parameter" do
      it "accepts last_hour period" do
        get :index, params: { period: "last_hour" }
        expect(response).to have_http_status(:success)
        expect(assigns(:period)).to eq("last_hour")
      end

      it "accepts last_7_days period" do
        get :index, params: { period: "last_7_days" }
        expect(response).to have_http_status(:success)
        expect(assigns(:period)).to eq("last_7_days")
      end

      it "accepts last_30_days period" do
        get :index, params: { period: "last_30_days" }
        expect(response).to have_http_status(:success)
        expect(assigns(:period)).to eq("last_30_days")
      end

      it "defaults to last_24_hours without period" do
        get :index
        expect(assigns(:period)).to eq("last_24_hours")
      end
    end

    context "with JSON format" do
      it "returns JSON response" do
        get :index, format: :json
        expect(response).to have_http_status(:success)
        expect(response.content_type).to match(/json/)
      end

      it "includes all dashboard data in JSON" do
        get :index, format: :json
        json = JSON.parse(response.body)

        expect(json).to include(
          "summary",
          "performance",
          "accounts",
          "errors",
          "peak_times",
          "generated_at"
        )
      end
    end
  end

  describe "GET #export" do
    let!(:sync_session) { create(:sync_session) }
    let!(:metrics) do
      create_list(:sync_metric, 10, sync_session: sync_session, started_at: 1.day.ago)
    end

    it "exports data as CSV" do
      get :export, format: :csv
      expect(response).to have_http_status(:success)
      expect(response.content_type).to match(/csv/)
    end

    it "includes correct CSV headers" do
      get :export, format: :csv
      csv = CSV.parse(response.body, headers: true)

      expect(csv.headers).to include(
        "Fecha/Hora",
        "Sesión ID",
        "Cuenta",
        "Tipo de Métrica",
        "Duración (ms)",
        "Correos Procesados",
        "Éxito",
        "Tipo de Error",
        "Mensaje de Error"
      )
    end

    it "filters by period parameter" do
      old_session = create(:sync_session)
      recent_session = create(:sync_session)

      old_metric = create(:sync_metric, sync_session: old_session, started_at: 10.days.ago)
      recent_metric = create(:sync_metric, sync_session: recent_session, started_at: 1.hour.ago)

      get :export, params: { period: "last_24_hours" }, format: :csv
      csv = CSV.parse(response.body, headers: true)

      # Filter should be based on time, not session ID
      timestamps = csv.map { |row| DateTime.parse(row["Fecha/Hora"]) }

      # All timestamps should be within last 24 hours
      expect(timestamps).to all(be >= 24.hours.ago)

      # Check that recent metric timestamp is included (convert to same timezone)
      recent_time = recent_metric.started_at.strftime("%Y-%m-%d %H:%M:%S")
      csv_times = csv.map { |row| row["Fecha/Hora"] }
      expect(csv_times).to include(recent_time)
    end
  end

  describe "GET #realtime" do
    let!(:sync_session) { create(:sync_session) }

    before do
      create_list(:sync_metric, 3,
        sync_session: sync_session,
        started_at: 2.minutes.ago
      )
    end

    it "returns real-time metrics as JSON" do
      get :realtime, format: :json
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json).to include(
        "current_operations",
        "success_rate",
        "average_duration",
        "emails_per_second",
        "active_jobs",
        "queue_depth"
      )
    end

    it "returns turbo stream format" do
      get :realtime, format: :turbo_stream
      expect(response).to have_http_status(:success)
      # Rails 7+ uses different content type format
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    end
  end
end
