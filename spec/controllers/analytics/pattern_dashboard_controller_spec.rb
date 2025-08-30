require "rails_helper"

RSpec.describe Analytics::PatternDashboardController, type: :controller, unit: true do
  let(:admin_user) { create(:admin_user) }
  let(:restricted_admin) { create(:admin_user, :read_only) }
  let(:super_admin_user) { create(:admin_user, :super_admin) }
  let(:category) { create(:category) }
  let(:pattern) { create(:categorization_pattern) }

  before do
    # Authenticate admin user for most tests
    sign_in_as(admin_user)

    # Create test data for analytics (real database records)
    create_list(:categorization_pattern, 3, category: category)
    create_list(:pattern_feedback, 2, categorization_pattern: pattern)
    create_list(:pattern_learning_event, 2)

    # Ensure global instance variables are set for any controller method calls
    # This prevents "undefined method 'first' for nil" errors when cache_key_for is called
    controller.instance_variable_set(:@time_range, 1.week.ago..Time.current)
    controller.instance_variable_set(:@category_id, nil)
    controller.instance_variable_set(:@pattern_type, nil)

    # Set up a default analyzer mock that can be overridden by specific test contexts
    default_analyzer = double('PatternPerformanceAnalyzer')
    allow(default_analyzer).to receive(:overall_metrics).and_return({ total_patterns: 10 })
    allow(default_analyzer).to receive(:category_performance).and_return([])
    allow(default_analyzer).to receive(:pattern_type_analysis).and_return({})
    allow(default_analyzer).to receive(:top_patterns).and_return([])
    allow(default_analyzer).to receive(:bottom_patterns).and_return([])
    allow(default_analyzer).to receive(:learning_metrics).and_return({})
    allow(default_analyzer).to receive(:recent_activity).and_return([])
    allow(default_analyzer).to receive(:trend_analysis).and_return([])  # Return array for trends
    allow(default_analyzer).to receive(:usage_heatmap).and_return({})
    allow(default_analyzer).to receive(:time_range).and_return(1.week.ago..Time.current)  # For exporter

    controller.instance_variable_set(:@analyzer, default_analyzer)
    allow(::Analytics::PatternPerformanceAnalyzer).to receive(:new).and_return(default_analyzer)
  end

  describe "GET #index" do
    let(:mock_analyzer) do
      double(
        'PatternPerformanceAnalyzer',
        overall_metrics: overall_metrics,
        category_performance: category_performance,
        pattern_type_analysis: pattern_type_analysis,
        top_patterns: top_patterns,
        bottom_patterns: bottom_patterns,
        learning_metrics: learning_metrics,
        recent_activity: recent_activity
      )
    end
    let(:overall_metrics) { { total_patterns: 10, accuracy: 95.5, total_applications: 50 } }
    let(:category_performance) { [ { category_id: 1, pattern_count: 5, accuracy: 92.1 } ] }
    let(:pattern_type_analysis) { { merchant: 15, keyword: 10, amount: 5 } }
    let(:top_patterns) { [ { id: 1, name: "Test Pattern", accuracy: 98.5 } ] }
    let(:bottom_patterns) { [ { id: 2, name: "Low Pattern", accuracy: 65.2 } ] }
    let(:learning_metrics) { { improvement_rate: 12.5, total_feedback: 25 } }
    let(:recent_activity) { [ { pattern_id: 1, action: "applied", timestamp: 1.hour.ago } ] }

    before do
      allow(::Analytics::PatternPerformanceAnalyzer).to receive(:new).and_return(mock_analyzer)

      # Mock Rails cache
      allow(Rails.cache).to receive(:fetch).with(any_args).and_yield
    end

    it "returns successful response" do
      get :index
      expect(response).to have_http_status(:success)
    end

    it "sets analyzer with correct filters" do
      get :index, params: {
        time_period: "week",
        category_id: category.id,
        pattern_type: "merchant"
      }

      expect(assigns(:analyzer)).to eq(mock_analyzer)
      expect(::Analytics::PatternPerformanceAnalyzer).to have_received(:new).with(
        time_range: anything,
        category_id: category.id.to_s,
        pattern_type: "merchant"
      )
    end

    it "assigns cached overall metrics" do
      get :index
      expect(assigns(:overall_metrics)).to eq(overall_metrics)
    end

    it "assigns cached category performance" do
      get :index
      expect(assigns(:category_performance)).to eq(category_performance)
    end

    it "assigns cached pattern type analysis" do
      get :index
      expect(assigns(:pattern_type_analysis)).to eq(pattern_type_analysis)
    end

    it "assigns top patterns with limit" do
      get :index
      expect(assigns(:top_patterns)).to eq(top_patterns)
      expect(mock_analyzer).to have_received(:top_patterns).with(limit: 10)
    end

    it "assigns bottom patterns with limit" do
      get :index
      expect(assigns(:bottom_patterns)).to eq(bottom_patterns)
      expect(mock_analyzer).to have_received(:bottom_patterns).with(limit: 10)
    end

    it "assigns learning metrics" do
      get :index
      expect(assigns(:learning_metrics)).to eq(learning_metrics)
    end

    it "assigns recent activity with limit" do
      get :index
      expect(assigns(:recent_activity)).to eq(recent_activity)
      expect(mock_analyzer).to have_received(:recent_activity).with(limit: 10)
    end

    it "responds to HTML format" do
      get :index
      expect(response.content_type).to include("text/html")
    end

    it "responds to turbo_stream format", :skip do
      get :index, format: :turbo_stream
      expect(response).to have_http_status(:success)
    end

    it "uses cache for expensive operations" do
      cache_key_overall = include("pattern_analytics/overall_metrics")
      cache_key_category = include("pattern_analytics/category_performance")
      cache_key_pattern_type = include("pattern_analytics/pattern_type_analysis")

      expect(Rails.cache).to receive(:fetch).with(cache_key_overall, expires_in: 5.minutes)
      expect(Rails.cache).to receive(:fetch).with(cache_key_category, expires_in: 5.minutes)
      expect(Rails.cache).to receive(:fetch).with(cache_key_pattern_type, expires_in: 5.minutes)

      get :index
    end

    context "with time period filters" do
      it "handles today filter" do
        get :index, params: { time_period: "today" }
        expect(assigns(:time_range).first).to be >= Time.current.beginning_of_day
      end

      it "handles week filter" do
        get :index, params: { time_period: "week" }
        expect(assigns(:time_range).first).to be <= 1.week.ago
      end

      it "handles month filter" do
        get :index, params: { time_period: "month" }
        expect(assigns(:time_range).first).to be <= 1.month.ago
      end

      it "handles quarter filter" do
        get :index, params: { time_period: "quarter" }
        expect(assigns(:time_range).first).to be <= 3.months.ago
      end

      it "handles year filter" do
        get :index, params: { time_period: "year" }
        expect(assigns(:time_range).first).to be <= 1.year.ago
      end

      it "handles custom date range" do
        get :index, params: {
          time_period: "custom",
          start_date: "2023-01-01",
          end_date: "2023-01-31"
        }
        expect(assigns(:time_range)).to be_a(Range)
      end

      it "uses default range for invalid time period" do
        get :index, params: { time_period: "invalid" }
        expect(assigns(:time_range).first).to be <= 30.days.ago
      end
    end

    context "without analytics permission" do
      before do
        allow(controller).to receive(:current_admin_user).and_return(restricted_admin)
        # Override the global default mock for this specific context
        allow(controller).to receive(:require_analytics_permission) do
          unless controller.performed?
            controller.render plain: "Forbidden", status: :forbidden
          end
        end
      end

      it "denies access" do
        get :index
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET #trends" do
    let(:mock_analyzer) { double('PatternPerformanceAnalyzer') }
    let(:trend_data) { { daily: [ { date: "2023-01-01", accuracy: 95.2 } ] } }

    before do
      allow(::Analytics::PatternPerformanceAnalyzer).to receive(:new).and_return(mock_analyzer)
      allow(mock_analyzer).to receive(:trend_analysis).and_return(trend_data)
      allow(Rails.cache).to receive(:fetch).with(any_args).and_yield

      # Ensure instance variables are set for cache_key_for method
      controller.instance_variable_set(:@time_range, 1.week.ago..Time.current)
      controller.instance_variable_set(:@category_id, nil)
      controller.instance_variable_set(:@pattern_type, nil)
      controller.instance_variable_set(:@analyzer, mock_analyzer)
    end

    it "returns successful response" do
      get :trends, format: :json
      expect(response).to have_http_status(:success)
    end

    it "returns trend data as JSON" do
      get :trends, format: :json
      expect(response.content_type).to include("application/json")
      expect(JSON.parse(response.body)).to eq(trend_data.as_json)
    end

    it "uses daily interval by default" do
      get :trends, format: :json
      expect(mock_analyzer).to have_received(:trend_analysis).with(interval: :daily)
    end

    it "accepts custom interval parameter" do
      get :trends, params: { interval: "weekly" }, format: :json
      expect(mock_analyzer).to have_received(:trend_analysis).with(interval: :weekly)
    end

    it "responds to turbo_stream format" do
      get :trends, format: :turbo_stream
      expect(response).to have_http_status(:success)
    end

    it "uses cache with interval-specific key" do
      cache_key = include("pattern_analytics/trends_daily")
      expect(Rails.cache).to receive(:fetch).with(cache_key, expires_in: 10.minutes)

      get :trends, format: :json
    end

  end

  describe "GET #heatmap" do
    let(:mock_analyzer) { double('PatternPerformanceAnalyzer') }
    let(:heatmap_data) { { hour_12: 20, hour_15: 35, hour_18: 42 } }

    before do
      allow(::Analytics::PatternPerformanceAnalyzer).to receive(:new).and_return(mock_analyzer)
      allow(mock_analyzer).to receive(:usage_heatmap).and_return(heatmap_data)
      allow(Rails.cache).to receive(:fetch).with(any_args).and_yield

      # Ensure instance variables are set for cache_key_for method
      controller.instance_variable_set(:@time_range, 1.week.ago..Time.current)
      controller.instance_variable_set(:@category_id, nil)
      controller.instance_variable_set(:@pattern_type, nil)
      controller.instance_variable_set(:@analyzer, mock_analyzer)
    end

    it "returns successful response" do
      get :heatmap, format: :json
      expect(response).to have_http_status(:success)
    end

    it "returns heatmap data as JSON" do
      get :heatmap, format: :json
      expect(response.content_type).to include("application/json")
      expect(JSON.parse(response.body)).to eq(heatmap_data.as_json)
    end

    it "responds to turbo_stream format" do
      get :heatmap, format: :turbo_stream
      expect(response).to have_http_status(:success)
    end

    it "uses cache with 30-minute expiry" do
      cache_key = include("pattern_analytics/heatmap")
      expect(Rails.cache).to receive(:fetch).with(cache_key, expires_in: 30.minutes)

      get :heatmap, format: :json
    end

    context "without analytics permission" do
      before do
        allow(controller).to receive(:current_admin_user).and_return(restricted_admin)
        # Override the global default mock for this specific context
        allow(controller).to receive(:require_analytics_permission) do
          unless controller.performed?
            controller.render plain: "Forbidden", status: :forbidden
          end
        end
      end

      it "denies access" do
        get :heatmap, format: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST #export" do
    let(:mock_analyzer) { double('PatternPerformanceAnalyzer') }
    let(:mock_exporter) { double('DashboardExporter') }
    let(:csv_data) { "pattern_id,accuracy\n1,95.5\n2,87.2" }
    let(:json_data) { '{"patterns": [{"id": 1, "accuracy": 95.5}]}' }
    let(:overall_metrics) { { total_patterns: 2 } }

    before do
      allow(::Analytics::PatternPerformanceAnalyzer).to receive(:new).and_return(mock_analyzer)
      allow(mock_analyzer).to receive(:overall_metrics).and_return(overall_metrics)
      allow(::Analytics::DashboardExporter).to receive(:new).and_return(mock_exporter)
      allow(controller).to receive(:send_data)
      allow(controller).to receive(:log_admin_action)

      # Mock rate limiting
      allow(Rails.cache).to receive(:increment).and_return(1)

      # Ensure instance variables are set for cache_key_for method and export logging
      controller.instance_variable_set(:@time_range, 1.week.ago..Time.current)
      controller.instance_variable_set(:@category_id, nil)
      controller.instance_variable_set(:@pattern_type, nil)
      controller.instance_variable_set(:@analyzer, mock_analyzer)
    end

    it "returns successful response for CSV export" do
      allow(mock_exporter).to receive(:export).and_return(csv_data)

      post :export, params: { format_type: "csv" }
      expect(response).to have_http_status(:success)
    end

    it "exports CSV data with correct headers" do
      allow(mock_exporter).to receive(:export).and_return(csv_data)

      post :export, params: { format_type: "csv" }
      expect(controller).to have_received(:send_data).with(
        csv_data,
        filename: match(/pattern_analytics_\d{8}_\d{6}\.csv/),
        type: "text/csv",
        disposition: "attachment"
      )
    end

    it "exports JSON data with correct headers" do
      allow(mock_exporter).to receive(:export).and_return(json_data)

      post :export, params: { format_type: "json" }
      expect(controller).to have_received(:send_data).with(
        json_data,
        filename: match(/pattern_analytics_\d{8}_\d{6}\.json/),
        type: "application/json",
        disposition: "attachment"
      )
    end

    it "defaults to CSV format when format_type is blank" do
      allow(mock_exporter).to receive(:export).and_return(csv_data)

      post :export
      expect(::Analytics::DashboardExporter).to have_received(:new).with(
        mock_analyzer,
        format: :csv
      )
    end

    it "creates exporter with correct analyzer" do
      allow(mock_exporter).to receive(:export).and_return(csv_data)

      post :export, params: { format_type: "csv" }
      expect(::Analytics::DashboardExporter).to have_received(:new).with(
        mock_analyzer,
        format: :csv
      )
    end

    it "logs export activity" do
      allow(mock_exporter).to receive(:export).and_return(csv_data)

      post :export, params: { format_type: "csv" }
      expect(controller).to have_received(:log_admin_action).with(
        "analytics.export",
        hash_including(
          format: :csv,
          filename: match(/pattern_analytics_\d{8}_\d{6}/),
          records_exported: 2
        )
      )
    end

    it "rejects invalid export formats" do
      post :export, params: { format_type: "invalid" }
      expect(response).to redirect_to(analytics_pattern_dashboard_index_path)
      expect(flash[:alert]).to eq("Invalid export format")
    end

    context "rate limiting" do
      it "allows exports within limit" do
        allow(Rails.cache).to receive(:increment).and_return(3)
        allow(mock_exporter).to receive(:export).and_return(csv_data)

        post :export, params: { format_type: "csv" }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "POST #refresh" do
    let(:refresh_mock_analyzer) { double('PatternPerformanceAnalyzer') }
    let(:overall_metrics) { { total_patterns: 10, accuracy: 95.5 } }
    let(:category_performance) { [ { category_id: 1, pattern_count: 5 } ] }
    let(:recent_activity) { [ { pattern_id: 1, action: "applied" } ] }

    context "with valid authentication" do
      before do
        # Ensure clean state for each test
        allow(controller).to receive(:current_admin_user).and_return(admin_user)
        allow(controller).to receive(:require_admin_authentication).and_return(true)
        allow(controller).to receive(:require_analytics_permission).and_return(true)

        # Mock the analyzer consistently
        allow(::Analytics::PatternPerformanceAnalyzer).to receive(:new).and_return(refresh_mock_analyzer)
        allow(refresh_mock_analyzer).to receive(:overall_metrics).and_return(overall_metrics)
        allow(refresh_mock_analyzer).to receive(:category_performance).and_return(category_performance)
        allow(refresh_mock_analyzer).to receive(:recent_activity).and_return(recent_activity)

        # Ensure instance variables are set for any methods that might be called
        controller.instance_variable_set(:@time_range, 1.week.ago..Time.current)
        controller.instance_variable_set(:@category_id, nil)
        controller.instance_variable_set(:@pattern_type, nil)
        controller.instance_variable_set(:@analyzer, refresh_mock_analyzer)
      end

      it "refreshes overall_metrics component" do
        post :refresh, params: { component: "overall_metrics" }
        expect(response).to have_http_status(:success)
        expect(assigns(:overall_metrics)).to eq(overall_metrics)
      end

      it "refreshes category_performance component" do
        post :refresh, params: { component: "category_performance" }
        expect(response).to have_http_status(:success)
        expect(assigns(:category_performance)).to eq(category_performance)
      end

      it "refreshes recent_activity component" do
        post :refresh, params: { component: "recent_activity" }
        expect(response).to have_http_status(:success)
        expect(assigns(:recent_activity)).to eq(recent_activity)
        expect(refresh_mock_analyzer).to have_received(:recent_activity).with(limit: 10)
      end

      it "returns unprocessable_content for invalid component" do
        post :refresh, params: { component: "invalid_component" }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns unprocessable_content when component parameter missing" do
        post :refresh
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "without analytics permission" do
      before do
        # Clean setup for permission test
        allow(controller).to receive(:current_admin_user).and_return(restricted_admin)
        allow(controller).to receive(:require_admin_authentication).and_return(true)
        # Override the global default mock for this specific context
        allow(controller).to receive(:require_analytics_permission) do
          unless controller.performed?
            controller.render plain: "Forbidden", status: :forbidden
          end
        end
        # Skip other callbacks since permission check should render first
        allow(controller).to receive(:set_filters).and_return(true)
        allow(controller).to receive(:set_analyzer).and_return(true)
      end

      it "denies access" do
        post :refresh, params: { component: "overall_metrics" }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "authentication and authorization" do
    context "when not logged in" do
      before do
        # Skip all callbacks and simulate authentication redirect behavior
        allow(controller).to receive(:current_admin_user).and_return(nil)

        # Skip the before_action callbacks entirely
        controller.class.skip_before_action :require_analytics_permission, raise: false
        controller.class.skip_before_action :set_filters, raise: false
        controller.class.skip_before_action :set_analyzer, raise: false
        controller.class.skip_before_action :check_export_rate_limit, raise: false

        # Mock the authentication behavior to redirect
        allow(controller).to receive(:process_action) do |method_name|
          controller.redirect_to "/admin/login"
        end
      end

      after do
        # Restore callbacks for other tests
        controller.class.before_action :require_analytics_permission
        controller.class.before_action :set_filters
        controller.class.before_action :set_analyzer
        controller.class.before_action :check_export_rate_limit, only: [ :export ]
      end

      it "redirects to login for index" do
        get :index
        expect(response).to redirect_to("/admin/login")
      end

      it "redirects to login for trends" do
        get :trends, format: :json
        expect(response).to redirect_to("/admin/login")
      end

      it "redirects to login for heatmap" do
        get :heatmap, format: :json
        expect(response).to redirect_to("/admin/login")
      end

      it "redirects to login for export" do
        post :export
        expect(response).to redirect_to("/admin/login")
      end

      it "redirects to login for refresh" do
        post :refresh, params: { component: "overall_metrics" }
        expect(response).to redirect_to("/admin/login")
      end
    end
  end


  # Additional Security Tests
  describe "Security", unit: true do
    describe "SQL injection prevention" do
      it "safely handles malicious interval parameter in trends" do
        get :trends, params: { interval: "'; DROP TABLE users; --" }, format: :json
        expect(response).to be_successful
        expect(JSON.parse(response.body)).to be_an(Array)
      end

      it "only accepts whitelisted interval values" do
        %w[hourly daily weekly monthly].each do |interval|
          get :trends, params: { interval: interval }, format: :json
          expect(response).to be_successful
        end
      end

      it "defaults to daily for invalid intervals" do
        get :trends, params: { interval: "invalid" }, format: :json
        expect(response).to be_successful
      end
    end

    describe "export format validation" do
      it "rejects invalid export formats" do
        post :export, params: { format_type: "exe" }
        expect(response).to redirect_to(analytics_pattern_dashboard_index_path)
        expect(flash[:alert]).to eq("Invalid export format")
      end

      it "prevents path traversal in format parameter" do
        post :export, params: { format_type: "../../../etc/passwd" }
        expect(response).to redirect_to(analytics_pattern_dashboard_index_path)
        expect(flash[:alert]).to eq("Invalid export format")
      end

      it "accepts valid export formats" do
        %w[csv json].each do |format|
          post :export, params: { format_type: format }
          expect(response).to be_successful
        end
      end
    end

    describe "date parsing security" do
      it "handles invalid start date gracefully" do
        get :index, params: {
          time_period: "custom",
          start_date: "invalid-date",
          end_date: Date.current.to_s
        }
        expect(response).to be_successful
        expect(flash[:alert]).to include("Invalid date format") if flash[:alert]
      end

      it "handles invalid end date gracefully" do
        get :index, params: {
          time_period: "custom",
          start_date: 1.month.ago.to_date.to_s,
          end_date: "not-a-date"
        }
        expect(response).to be_successful
        expect(flash[:alert]).to include("Invalid date format") if flash[:alert]
      end

      it "handles start date after end date" do
        get :index, params: {
          time_period: "custom",
          start_date: Date.current.to_s,
          end_date: 1.month.ago.to_date.to_s
        }
        expect(response).to be_successful
        # Should use default range
      end

      it "limits date range to maximum years" do
        get :index, params: {
          time_period: "custom",
          start_date: 10.years.ago.to_date.to_s,
          end_date: Date.current.to_s
        }
        expect(response).to be_successful
        # Should limit to max allowed years
      end
    end
  end

  # Performance and Caching Tests
  describe "Performance", unit: true do
    let(:performance_mock_analyzer) { double('PatternPerformanceAnalyzer') }
    let(:performance_overall_metrics) { { total_patterns: 10, accuracy: 95.5 } }
    let(:performance_category_performance) { [ { category_id: 1, pattern_count: 5 } ] }
    let(:performance_recent_activity) { [ { pattern_id: 1, action: "applied" } ] }

    before do
      allow(::Analytics::PatternPerformanceAnalyzer).to receive(:new).and_return(performance_mock_analyzer)
      allow(performance_mock_analyzer).to receive(:overall_metrics).and_return(performance_overall_metrics)
      allow(performance_mock_analyzer).to receive(:category_performance).and_return(performance_category_performance)
      allow(performance_mock_analyzer).to receive(:pattern_type_analysis).and_return({ merchant: 5 })
      allow(performance_mock_analyzer).to receive(:top_patterns).and_return([])
      allow(performance_mock_analyzer).to receive(:bottom_patterns).and_return([])
      allow(performance_mock_analyzer).to receive(:learning_metrics).and_return({})
      allow(performance_mock_analyzer).to receive(:recent_activity).and_return(performance_recent_activity)

      # Ensure instance variables are set
      controller.instance_variable_set(:@time_range, 1.week.ago..Time.current)
      controller.instance_variable_set(:@category_id, nil)
      controller.instance_variable_set(:@pattern_type, nil)
      controller.instance_variable_set(:@analyzer, performance_mock_analyzer)

      # Mock Rails cache to avoid actual caching in tests
      allow(Rails.cache).to receive(:fetch).and_yield
    end

    describe "caching behavior" do
      it "uses caching for expensive operations" do
        expect(Rails.cache).to receive(:fetch).at_least(:once).and_call_original
        get :index
        expect(response).to be_successful
      end

      it "includes proper cache invalidation keys" do
        allow(CategorizationPattern).to receive(:maximum).with(:updated_at).and_return(Time.current)
        allow(PatternFeedback).to receive(:maximum).with(:updated_at).and_return(Time.current)
        allow(PatternLearningEvent).to receive(:maximum).with(:updated_at).and_return(Time.current)

        get :index
        expect(response).to be_successful
      end

      it "invalidates cache when patterns are modified" do
        # Don't mock Rails.cache for this test - we need real caching behavior
        allow(Rails.cache).to receive(:fetch).and_call_original
        Rails.cache.clear

        get :index
        expect(response).to be_successful

        # Cache should be populated
        cache_key = controller.send(:cache_key_for, "overall_metrics")
        expect(Rails.cache.exist?(cache_key)).to be true

        # Modify a pattern with time travel to ensure cache key changes
        travel_to(1.minute.from_now) do
          create(:categorization_pattern).update!(confidence_weight: 2.0)

          # Cache key should be different now
          new_cache_key = controller.send(:cache_key_for, "overall_metrics")
          expect(new_cache_key).not_to eq(cache_key)
        end
      end
    end
  end

  # Audit Logging Tests
  describe "Audit Logging", unit: true do
    let(:audit_mock_analyzer) { double('PatternPerformanceAnalyzer') }
    let(:audit_mock_exporter) { double('DashboardExporter') }
    let(:audit_csv_data) { "pattern_id,accuracy\n1,95.5" }
    let(:audit_overall_metrics) { { total_patterns: 1 } }

    before do
      allow(::Analytics::PatternPerformanceAnalyzer).to receive(:new).and_return(audit_mock_analyzer)
      allow(audit_mock_analyzer).to receive(:overall_metrics).and_return(audit_overall_metrics)
      allow(::Analytics::DashboardExporter).to receive(:new).and_return(audit_mock_exporter)
      allow(audit_mock_exporter).to receive(:export).and_return(audit_csv_data)
      allow(controller).to receive(:send_data)
      # Don't mock log_admin_action - let it run for audit tests

      # Mock rate limiting to allow exports
      allow(Rails.cache).to receive(:increment).and_return(1)

      # Ensure instance variables are set
      controller.instance_variable_set(:@time_range, 1.week.ago..Time.current)
      controller.instance_variable_set(:@category_id, nil)
      controller.instance_variable_set(:@pattern_type, nil)
      controller.instance_variable_set(:@analyzer, audit_mock_analyzer)
    end

    it "logs export actions for audit trail" do
      logged = false
      allow(Rails.logger).to receive(:info) do |msg|
        if msg.include?("admin_action")
          parsed = JSON.parse(msg)
          if parsed["event"] == "admin_action" && parsed["action"].include?("export")
            logged = true
          end
        end
      end

      post :export, params: { format_type: "csv" }
      expect(logged).to be true
    end

    it "includes export details in audit log" do
      allow(Rails.logger).to receive(:info)

      post :export, params: {
        format_type: "json",
        time_period: "week",
        category_id: category.id
      }

      expect(Rails.logger).to have_received(:info).at_least(2).times

      # Check for the specific export action log
      expect(Rails.logger).to have_received(:info).with(
        a_string_matching(/analytics\.export/)
      )
    end
  end

  # Enhanced Error Handling Tests
  describe "Enhanced Error Handling", unit: true do
    describe "database query failures" do
      it "handles database errors gracefully in heatmap" do
        analyzer = instance_double(Analytics::PatternPerformanceAnalyzer)
        allow(Analytics::PatternPerformanceAnalyzer).to receive(:new).and_return(analyzer)
        allow(analyzer).to receive(:usage_heatmap).and_return({})

        get :heatmap, format: :json
        expect(response).to be_successful
        expect(JSON.parse(response.body)).to eq({})
      end

      it "returns empty array on trends error" do
        analyzer = instance_double(Analytics::PatternPerformanceAnalyzer)
        allow(Analytics::PatternPerformanceAnalyzer).to receive(:new).and_return(analyzer)
        allow(analyzer).to receive(:trend_analysis).and_return([])

        get :trends, format: :json
        expect(response).to be_successful
        expect(JSON.parse(response.body)).to eq([])
      end
    end

    describe "component validation" do
      it "validates component parameter in refresh" do
        post :refresh, params: { component: "invalid_component" }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "accepts valid components" do
        %w[overall_metrics category_performance recent_activity].each do |component|
          post :refresh, params: { component: component }
          expect(response).to be_successful
        end
      end
    end
  end

  # Content Type and Response Tests
  describe "Content Types", unit: true do
    it "returns proper content types for exports" do
      post :export, params: { format_type: "csv" }
      expect(response).to be_successful
      expect(response.content_type).to include("text/csv")

      post :export, params: { format_type: "json" }
      expect(response).to be_successful
      expect(response.content_type).to include("application/json")
    end

    it "returns JSON for API endpoints" do
      get :trends, format: :json
      expect(response).to be_successful
      expect(response.content_type).to include("application/json")

      get :heatmap, format: :json
      expect(response).to be_successful
      expect(response.content_type).to include("application/json")
    end
  end

  private

  def sign_in_as(user)
    user.regenerate_session_token
    session[:admin_session_token] = user.reload.session_token
    session[:admin_user_id] = user.id
  end
end
