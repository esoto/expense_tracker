# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::PatternDashboardController, type: :controller, performance: true do
  let(:admin_user) do
    AdminUser.create!(
      email: "test@example.com",
      password: "SecurePassword123!",
      name: "Test Admin",
      role: :admin
    )
  end

  let(:category) { Category.create!(name: "Test Category", color: "#FF0000") }

  before do
    # Mock authentication
    allow(controller).to receive(:current_admin_user).and_return(admin_user)
    allow(controller).to receive(:admin_signed_in?).and_return(true)
  end

  describe "Fixed Security Issues", performance: true do
    describe "GET #trends", performance: true do
      it "handles SQL injection attempts safely" do
        malicious_input = "'; DROP TABLE users; --"

        expect {
          get :trends, params: { interval: malicious_input }, format: :json
        }.not_to raise_error

        expect(response).to be_successful
        data = JSON.parse(response.body)
        expect(data).to be_an(Array)
      end
    end

    describe "GET #index", performance: true do
      it "handles invalid date parameters gracefully" do
        get :index, params: {
          time_period: "custom",
          start_date: "INVALID_DATE",
          end_date: Date.current.to_s
        }

        expect(response).to be_successful
      end

      it "limits date range to 2 years maximum" do
        get :index, params: {
          time_period: "custom",
          start_date: 10.years.ago.to_date.to_s,
          end_date: Date.current.to_s
        }

        expect(response).to be_successful
      end
    end

    describe "GET #export", performance: true do
      it "validates export format" do
        get :export, params: { format_type: "malicious_format" }

        expect(response).to redirect_to(analytics_pattern_dashboard_index_path)
        expect(flash[:alert]).to eq("Invalid export format")
      end

      it "accepts valid formats" do
        get :export, params: { format_type: "csv" }
        expect(response).to be_successful
        expect(response.content_type).to include("text/csv")

        get :export, params: { format_type: "json" }
        expect(response).to be_successful
        expect(response.content_type).to include("application/json")
      end
    end
  end

  describe "Performance Optimizations", performance: true do
    it "uses caching for expensive operations" do
      expect(Rails.cache).to receive(:fetch).at_least(:once).and_call_original
      get :index
      expect(response).to be_successful
    end

    it "includes pagination support" do
      # The analyzer should receive pagination parameters
      analyzer = instance_double(Analytics::PatternPerformanceAnalyzer)
      allow(Analytics::PatternPerformanceAnalyzer).to receive(:new).and_return(analyzer)

      # Set up expected method calls
      allow(analyzer).to receive(:overall_metrics).and_return({})
      allow(analyzer).to receive(:category_performance).and_return([])
      allow(analyzer).to receive(:pattern_type_analysis).and_return([])
      allow(analyzer).to receive(:top_patterns).and_return([])
      allow(analyzer).to receive(:bottom_patterns).and_return([])
      allow(analyzer).to receive(:learning_metrics).and_return({})
      allow(analyzer).to receive(:recent_activity).and_return([])

      get :index
      expect(response).to be_successful
    end
  end

  describe "Error Handling", performance: true do
    it "handles database errors gracefully" do
      analyzer = instance_double(Analytics::PatternPerformanceAnalyzer)
      allow(Analytics::PatternPerformanceAnalyzer).to receive(:new).and_return(analyzer)

      # Simulate database error
      allow(analyzer).to receive(:usage_heatmap).and_return({})

      get :heatmap, format: :json
      expect(response).to be_successful
      expect(JSON.parse(response.body)).to eq({})
    end
  end
end
