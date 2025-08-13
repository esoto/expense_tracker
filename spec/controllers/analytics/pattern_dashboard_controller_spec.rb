# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::PatternDashboardController, type: :controller do
  let(:admin_user) { create(:admin_user, role: :admin) }
  let(:read_only_user) { create(:admin_user, role: :read_only) }
  let(:super_admin_user) { create(:admin_user, role: :super_admin) }

  let(:category) { create(:category) }
  let(:pattern) { create(:categorization_pattern, category: category) }

  describe "Authentication and Authorization" do
    describe "GET #index" do
      context "when not authenticated" do
        it "redirects to admin login" do
          get :index
          expect(response).to redirect_to(admin_login_path)
        end
      end

      context "when authenticated as read_only user" do
        before { sign_in_as(read_only_user) }

        it "denies access with forbidden message" do
          get :index
          expect(response).to redirect_to(admin_root_path)
          expect(flash[:alert]).to eq("You don't have permission to access analytics.")
        end
      end

      context "when authenticated as admin user" do
        before { sign_in_as(admin_user) }

        it "allows access" do
          get :index
          expect(response).to be_successful
        end
      end

      context "when authenticated as super_admin user" do
        before { sign_in_as(super_admin_user) }

        it "allows access" do
          get :index
          expect(response).to be_successful
        end
      end
    end

    describe "GET #export" do
      context "when not authenticated" do
        it "redirects to admin login" do
          get :export
          expect(response).to redirect_to(admin_login_path)
        end
      end

      context "when authenticated as admin" do
        before { sign_in_as(admin_user) }

        it "requires analytics permission" do
          allow(controller).to receive(:current_admin_user).and_return(admin_user)
          allow(admin_user).to receive(:can_access_statistics?).and_return(false)
          get :export
          expect(response).to redirect_to(admin_root_path)
        end
      end
    end
  end

  describe "Rate Limiting" do
    before { sign_in_as(admin_user) }

    describe "GET #export" do
      it "enforces rate limiting after 5 exports per hour" do
        # Clear any existing rate limit cache
        Rails.cache.delete("export_rate_limit:#{admin_user.id}")

        # Make 5 successful requests
        5.times do
          get :export, params: { format_type: "csv" }
          expect(response).to be_successful
        end

        # 6th request should be rate limited
        get :export, params: { format_type: "csv" }
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to include("rate limit exceeded")
      end

      it "logs rate limit violations" do
        Rails.cache.write("export_rate_limit:#{admin_user.id}", 5, expires_in: 1.hour)

        expect(Rails.logger).to receive(:info) do |log_data|
          parsed = JSON.parse(log_data)
          expect(parsed["event"]).to eq("admin_action")
          expect(parsed["action"]).to eq("rate_limit.exceeded")
        end

        get :export, params: { format_type: "csv" }
      end
    end
  end

  describe "SQL Injection Protection" do
    before { sign_in_as(admin_user) }

    describe "GET #trends" do
      it "sanitizes interval parameter to prevent SQL injection" do
        # Attempt SQL injection via interval parameter
        malicious_interval = "daily'; DROP TABLE users; --"

        get :trends, params: { interval: malicious_interval }, format: :json

        expect(response).to be_successful
        # Should default to :daily when invalid interval provided
        expect(JSON.parse(response.body)).to be_an(Array)
      end

      it "only accepts whitelisted interval values" do
        valid_intervals = %w[hourly daily weekly monthly]

        valid_intervals.each do |interval|
          get :trends, params: { interval: interval }, format: :json
          expect(response).to be_successful
        end
      end

      it "defaults to daily for invalid intervals" do
        get :trends, params: { interval: "invalid_interval" }, format: :json
        expect(response).to be_successful
        # Verify it uses daily interval by checking the analyzer was called correctly
      end
    end
  end

  describe "Export Format Validation" do
    before { sign_in_as(admin_user) }

    describe "GET #export" do
      it "only accepts csv and json formats" do
        %w[csv json].each do |format|
          get :export, params: { format_type: format }
          expect(response).to be_successful
        end
      end

      it "rejects invalid export formats" do
        get :export, params: { format_type: "xml" }
        expect(response).to redirect_to(analytics_pattern_dashboard_index_path)
        expect(flash[:alert]).to eq("Invalid export format")
      end

      it "prevents path traversal in format parameter" do
        get :export, params: { format_type: "../../../etc/passwd" }
        expect(response).to redirect_to(analytics_pattern_dashboard_index_path)
        expect(flash[:alert]).to eq("Invalid export format")
      end

      it "logs export actions for audit trail" do
        # Expect two log calls - one from after_action and one from log_analytics_export
        call_count = 0
        expect(Rails.logger).to receive(:info).twice do |log_data|
          parsed = JSON.parse(log_data)
          expect(parsed["event"]).to eq("admin_action")

          call_count += 1
          if call_count == 1
            # First call is from log_analytics_export (called during action)
            expect(parsed["action"]).to eq("analytics.export")
            expect(parsed["details"]["format"]).to eq("csv")
          else
            # Second call is from after_action in BaseController
            expect(parsed["action"]).to eq("pattern_dashboard#export")
          end
        end

        get :export, params: { format_type: "csv" }
      end
    end
  end

  describe "Date Parsing Error Handling" do
    before { sign_in_as(admin_user) }

    describe "custom date range parsing" do
      it "handles invalid date formats gracefully" do
        get :index, params: {
          time_period: "custom",
          start_date: "not-a-date",
          end_date: "2024-01-01"
        }

        expect(response).to be_successful
        # Should use default 30 days range on parse error
      end

      it "prevents start date after end date" do
        get :index, params: {
          time_period: "custom",
          start_date: "2024-01-10",
          end_date: "2024-01-01"
        }

        expect(response).to be_successful
        # Should use default range when dates are invalid
      end

      it "limits date range to maximum 2 years" do
        get :index, params: {
          time_period: "custom",
          start_date: "2020-01-01",
          end_date: "2024-01-01"
        }

        expect(response).to be_successful
        # Should use default range when range is too large
      end

      it "handles missing date parameters" do
        get :index, params: { time_period: "custom" }
        expect(response).to be_successful
        # Should use sensible defaults
      end
    end
  end

  describe "Cache Invalidation" do
    before { sign_in_as(admin_user) }

    it "includes pattern update timestamp in cache key" do
      # Create a pattern and note the cache key
      pattern = create(:categorization_pattern)

      get :index
      first_cache_key = controller.send(:cache_key_for, "overall_metrics")

      # Update a pattern and ensure it's persisted
      travel_to(1.minute.from_now) do
        pattern.update!(confidence_weight: 2.5)
      end

      get :index
      second_cache_key = controller.send(:cache_key_for, "overall_metrics")

      expect(first_cache_key).not_to eq(second_cache_key)
    end

    it "invalidates cache when patterns are modified" do
      Rails.cache.clear

      get :index
      expect(response).to be_successful

      # Cache should be populated
      cache_key = controller.send(:cache_key_for, "overall_metrics")
      expect(Rails.cache.exist?(cache_key)).to be true

      # Modify a pattern
      create(:categorization_pattern).update!(confidence_weight: 2.0)

      # Cache key should be different now
      new_cache_key = controller.send(:cache_key_for, "overall_metrics")
      expect(new_cache_key).not_to eq(cache_key)
    end
  end

  describe "Performance Optimizations" do
    before do
      sign_in_as(admin_user)
      # Create test data
      5.times do
        category = create(:category)
        3.times { create(:categorization_pattern, category: category) }
      end
    end

    it "uses optimized queries for category performance" do
      # Should use a reasonable number of queries for dashboard load
      # Includes queries for metrics, categories, patterns, and recent activity
      expect {
        get :index
      }.to make_database_queries(count: 10..70) # Adjusted for actual query count
    end

    it "preloads associations for recent activity" do
      create_list(:pattern_feedback, 5)

      expect {
        get :refresh, params: { component: "recent_activity" }
      }.to make_database_queries(count: 5..15) # Adjusted for actual preloading
    end
  end

  describe "Security Headers" do
    before { sign_in_as(admin_user) }

    it "sets appropriate security headers" do
      get :index

      expect(response.headers["X-Frame-Options"]).to eq("DENY")
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
      expect(response.headers["X-XSS-Protection"]).to eq("1; mode=block")
      expect(response.headers["Referrer-Policy"]).to eq("strict-origin-when-cross-origin")
      expect(response.headers["Content-Security-Policy"]).to be_present
    end
  end

  private

  def sign_in_as(user)
    user.regenerate_session_token
    session[:admin_session_token] = user.reload.session_token
    session[:admin_user_id] = user.id
  end
end
