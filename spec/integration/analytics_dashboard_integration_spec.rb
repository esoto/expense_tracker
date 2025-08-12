# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Analytics Dashboard Integration", type: :request do
  let(:admin_user) { create(:admin_user, role: :admin) }
  let(:category) { create(:category, name: "Test Category") }
  let(:expense) { create(:expense, amount: 100, description: "Test expense") }

  before do
    # Create test data
    5.times do |i|
      pattern = create(:categorization_pattern,
        category: category,
        pattern_type: "keyword",
        pattern_value: "test#{i}",
        usage_count: 10 + i,
        success_count: 8 + i
      )

      create(:pattern_feedback,
        categorization_pattern: pattern,
        expense: expense,
        category: category,
        feedback_type: i.even? ? "accepted" : "rejected",
        was_correct: i.even?
      )
    end

    # For request specs, we need to properly authenticate by setting up the session
    # First, ensure the admin user has a valid session token
    admin_user.regenerate_session_token

    # Use the correct module path for stubbing
    allow_any_instance_of(Admin::BaseController).to receive(:current_admin_user).and_return(admin_user)
    allow_any_instance_of(Admin::BaseController).to receive(:admin_signed_in?).and_return(true)
    allow_any_instance_of(Admin::BaseController).to receive(:require_admin_authentication).and_return(true)
    allow_any_instance_of(Admin::BaseController).to receive(:check_session_expiry).and_return(true)
    allow_any_instance_of(Analytics::PatternDashboardController).to receive(:require_analytics_permission).and_return(true)
  end

  describe "GET /analytics/pattern_dashboard" do
    it "loads the dashboard successfully" do
      get analytics_pattern_dashboard_index_path

      expect(response).to be_successful
      expect(response.body).to include("Pattern Analytics Dashboard")
    end

    it "handles custom date ranges" do
      get analytics_pattern_dashboard_index_path, params: {
        time_period: "custom",
        start_date: 1.month.ago.to_date.to_s,
        end_date: Date.current.to_s
      }

      expect(response).to be_successful
    end

    it "handles invalid date ranges gracefully" do
      get analytics_pattern_dashboard_index_path, params: {
        time_period: "custom",
        start_date: "invalid",
        end_date: Date.current.to_s
      }

      expect(response).to be_successful
      expect(flash[:alert]).to include("Invalid date format")
    end
  end

  describe "GET /analytics/pattern_dashboard/trends" do
    it "returns trend data as JSON" do
      get trends_analytics_pattern_dashboard_index_path,
          params: { interval: "daily" },
          headers: { "Accept" => "application/json" }

      expect(response).to be_successful
      expect(response.content_type).to include("application/json")

      data = JSON.parse(response.body)
      expect(data).to be_an(Array)
    end

    it "prevents SQL injection in interval parameter" do
      get trends_analytics_pattern_dashboard_index_path,
          params: { interval: "'; DROP TABLE users; --" },
          headers: { "Accept" => "application/json" }

      expect(response).to be_successful
      # Should not raise an error and should use default interval
      data = JSON.parse(response.body)
      expect(data).to be_an(Array)
    end
  end

  describe "GET /analytics/pattern_dashboard/heatmap" do
    it "returns heatmap data as JSON" do
      get heatmap_analytics_pattern_dashboard_index_path,
          headers: { "Accept" => "application/json" }

      expect(response).to be_successful
      expect(response.content_type).to include("application/json")

      data = JSON.parse(response.body)
      expect(data).to be_an(Array)
      expect(data.size).to eq(168) # 7 days * 24 hours
    end
  end

  describe "GET /analytics/pattern_dashboard/export" do
    it "exports data as CSV" do
      get export_analytics_pattern_dashboard_index_path,
          params: { format_type: "csv" }

      expect(response).to be_successful
      expect(response.content_type).to include("text/csv")
      expect(response.headers["Content-Disposition"]).to include("pattern_analytics")
    end

    it "exports data as JSON" do
      get export_analytics_pattern_dashboard_index_path,
          params: { format_type: "json" }

      expect(response).to be_successful
      expect(response.content_type).to include("application/json")
    end

    it "rejects invalid export formats" do
      get export_analytics_pattern_dashboard_index_path,
          params: { format_type: "exe" }

      expect(response).to redirect_to(analytics_pattern_dashboard_index_path)
      expect(flash[:alert]).to eq("Invalid export format")
    end

    it "enforces rate limiting" do
      # Make 5 requests (the limit)
      5.times do
        get export_analytics_pattern_dashboard_index_path,
            params: { format_type: "csv" }
        expect(response).to be_successful
      end

      # 6th request should be rate limited
      get export_analytics_pattern_dashboard_index_path,
          params: { format_type: "csv" }

      expect(response).to redirect_to(admin_root_path)
      expect(flash[:alert]).to include("rate limit exceeded")
    end
  end

  describe "Cache invalidation" do
    it "clears analytics cache when patterns are updated" do
      pattern = create(:categorization_pattern, category: category)

      # Prime the cache
      get analytics_pattern_dashboard_index_path
      expect(response).to be_successful

      # Update pattern should clear cache
      expect(Rails.cache).to receive(:delete_matched).with("pattern_analytics/*").at_least(:once)
      pattern.update!(confidence_weight: 3.0)
    end

    it "clears analytics cache when feedback is created" do
      expect(Rails.cache).to receive(:delete_matched).with("pattern_analytics/*")

      create(:pattern_feedback,
        expense: expense,
        category: category,
        feedback_type: "accepted"
      )
    end
  end
end
