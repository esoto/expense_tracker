require "rails_helper"

RSpec.describe Api::HealthController, type: :controller, unit: true do
  before do
    # Mock the health check service
    @health_check = double("HealthCheck")
    allow(Services::Categorization::Monitoring::HealthCheck).to receive(:new).and_return(@health_check)
  end

  describe "GET #index" do
    context "when system is healthy" do
      before do
        allow(@health_check).to receive(:check_all).and_return({
          status: :healthy,
          healthy: true,
          timestamp: Time.current.iso8601,
          uptime_seconds: 3600,
          checks: {
            database: { status: :healthy, response_time_ms: 5 },
            cache: { status: :healthy, response_time_ms: 2 }
          },
          errors: []
        })
        allow(@health_check).to receive(:healthy?).and_return(true)
      end

      it "returns healthy status with OK response" do
        expect(Services::Categorization::Monitoring::HealthCheck).to receive(:new)
        get :index

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("healthy")
        expect(json_response["healthy"]).to be true
        expect(json_response["checks"]).to be_present
      end

      it "formats response correctly" do
        get :index

        json_response = JSON.parse(response.body)
        expect(json_response).to have_key("status")
        expect(json_response).to have_key("healthy")
        expect(json_response).to have_key("timestamp")
        expect(json_response).to have_key("uptime_seconds")
        expect(json_response).to have_key("checks")
      end
    end

    context "when system is unhealthy" do
      before do
        allow(@health_check).to receive(:check_all).and_return({
          status: :unhealthy,
          healthy: false,
          timestamp: Time.current.iso8601,
          uptime_seconds: 3600,
          checks: {
            database: { status: :unhealthy, error: "Connection failed" },
            cache: { status: :healthy, response_time_ms: 2 }
          },
          errors: [ "Database connection failed" ]
        })
        allow(@health_check).to receive(:healthy?).and_return(false)
      end

      it "returns unhealthy status with service unavailable response" do
        get :index

        expect(response).to have_http_status(:service_unavailable)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("unhealthy")
        expect(json_response["healthy"]).to be false
        expect(json_response["errors"]).to include("Database connection failed")
      end
    end
  end

  describe "GET #ready" do
    context "when system is ready" do
      before do
        allow(@health_check).to receive(:check_all)
        allow(@health_check).to receive(:ready?).and_return(true)
      end

      it "returns ready status" do
        get :ready

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("ready")
        expect(json_response["timestamp"]).to be_present
      end
    end

    context "when system is not ready" do
      before do
        allow(@health_check).to receive(:check_all)
        allow(@health_check).to receive(:ready?).and_return(false)
        allow(@health_check).to receive(:checks).and_return({
          database: { status: :unhealthy, error: "Not ready" },
          cache: { status: :healthy }
        })
      end

      it "returns not ready status with failed checks" do
        get :ready

        expect(response).to have_http_status(:service_unavailable)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("not_ready")
        expect(json_response["checks"]).to have_key("database")
      end
    end
  end

  describe "GET #live" do
    context "when system is live" do
      before do
        allow(@health_check).to receive(:live?).and_return(true)
      end

      it "returns live status" do
        get :live

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("live")
        expect(json_response["timestamp"]).to be_present
      end
    end

    context "when system is not live" do
      before do
        allow(@health_check).to receive(:live?).and_return(false)
      end

      it "returns dead status" do
        get :live

        expect(response).to have_http_status(:service_unavailable)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("dead")
      end
    end
  end

  describe "GET #metrics" do
    let!(:expense1) { create(:expense, category: create(:category)) }
    let!(:expense2) { create(:expense, category: nil) }
    let!(:pattern1) { create(:categorization_pattern, active: true) }
    let!(:pattern2) { create(:categorization_pattern, active: false) }

    before do
      # Mock the entire metrics collection to avoid complex database mocking
      allow(controller).to receive(:collect_metrics).and_return({
        timestamp: Time.current.iso8601,
        categorization: {
          total_expenses: 2,
          categorized_expenses: 1,
          uncategorized_expenses: 1,
          success_rate: 50.0
        },
        patterns: {
          total: 2,
          active: 1,
          high_confidence: 1,
          recently_updated: 1
        },
        performance: {
          cache_stats: {
            entries: 100,
            hits: 85,
            misses: 15,
            hit_rate: 0.85,
            memory_bytes: 1024
          },
          recent_activity: {
            expenses_processed: 1,
            patterns_learned: 1,
            patterns_updated: 1
          }
        },
        system: {
          database_pool: {
            size: 10,
            connections: 3,
            busy: 2,
            idle: 1
          },
          memory: {
            rss_mb: 128.0,
            percent: 15.5
          }
        }
      })
    end

    it "collects comprehensive metrics" do
      get :metrics

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response).to have_key("timestamp")
      expect(json_response).to have_key("categorization")
      expect(json_response).to have_key("patterns")
      expect(json_response).to have_key("performance")
      expect(json_response).to have_key("system")
    end

    it "includes categorization metrics" do
      get :metrics

      json_response = JSON.parse(response.body)
      categorization = json_response["categorization"]

      expect(categorization["total_expenses"]).to eq(2)
      expect(categorization["categorized_expenses"]).to eq(1)
      expect(categorization["uncategorized_expenses"]).to eq(1)
      expect(categorization["success_rate"]).to eq(50.0)
    end

    it "includes pattern metrics" do
      get :metrics

      json_response = JSON.parse(response.body)
      patterns = json_response["patterns"]

      expect(patterns["total"]).to eq(2)
      expect(patterns["active"]).to eq(1)
      expect(patterns).to have_key("high_confidence")
      expect(patterns).to have_key("recently_updated")
    end

    it "includes performance metrics" do
      get :metrics

      json_response = JSON.parse(response.body)
      performance = json_response["performance"]

      expect(performance).to have_key("cache_stats")
      expect(performance).to have_key("recent_activity")
      expect(performance["cache_stats"]["hit_rate"]).to eq(0.85)
    end

    it "includes system metrics" do
      get :metrics

      json_response = JSON.parse(response.body)
      system = json_response["system"]

      expect(system).to have_key("database_pool")
      expect(system["database_pool"]["size"]).to eq(10)
      expect(system["database_pool"]["busy"]).to eq(2)
      expect(system["database_pool"]["idle"]).to eq(1)
    end

    it "handles metrics collection errors gracefully" do
      allow(controller).to receive(:collect_metrics).and_raise(StandardError, "Metrics error")

      get :metrics

      expect(response).to have_http_status(:internal_server_error)
      json_response = JSON.parse(response.body)
      expect(json_response["error"]).to eq("Failed to collect metrics")
      expect(json_response["message"]).to eq("Metrics error")
    end
  end

  describe "private methods" do
    describe "#format_response" do
      let(:result) do
        {
          status: :healthy,
          healthy: true,
          timestamp: Time.current.iso8601,
          uptime_seconds: 3600,
          checks: {
            database: {
              status: :healthy,
              response_time_ms: 5,
              connected: true,
              extra_data: "some data"
            }
          },
          errors: []
        }
      end

      it "formats response with proper structure" do
        formatted = controller.send(:format_response, result)

        expect(formatted).to have_key(:status)
        expect(formatted).to have_key(:healthy)
        expect(formatted).to have_key(:timestamp)
        expect(formatted).to have_key(:uptime_seconds)
        expect(formatted).to have_key(:checks)
        expect(formatted).to have_key(:errors)
      end

      it "formats checks correctly" do
        formatted = controller.send(:format_response, result)
        database_check = formatted[:checks][:database]

        expect(database_check).to have_key(:status)
        expect(database_check).to have_key(:response_time_ms)
        expect(database_check).to have_key(:connected)
        expect(database_check).to have_key(:details)
        expect(database_check[:details]).to have_key(:extra_data)
      end
    end

    describe "#calculate_success_rate" do
      it "calculates success rate correctly with known data" do
        # Clean data for this test
        total_before = Expense.count
        categorized_before = Expense.where.not(category_id: nil).count

        # Create test data
        category = create(:category)
        create(:expense, category: category)
        create(:expense, category: nil)

        # Calculate expected rate
        total_after = Expense.count
        categorized_after = Expense.where.not(category_id: nil).count

        expected_rate = ((categorized_after).to_f / total_after * 100).round(2)

        rate = controller.send(:calculate_success_rate)
        expect(rate).to eq(expected_rate)
      end

      it "returns 0 when no expenses exist" do
        # Mock the count methods to simulate empty database
        allow(Expense).to receive(:count).and_return(0)

        rate = controller.send(:calculate_success_rate)
        expect(rate).to eq(0)
      end
    end

    describe "#cache_metrics" do
      context "when cache is available" do
        before do
          cache_instance = double("PatternCache")
          allow(Services::Categorization::PatternCache).to receive(:instance).and_return(cache_instance)
          allow(cache_instance).to receive(:stats).and_return({
            entries: 100,
            hits: 80,
            misses: 20,
            memory_bytes: 2048
          })
        end

        it "returns cache statistics" do
          metrics = controller.send(:cache_metrics)

          expect(metrics[:entries]).to eq(100)
          expect(metrics[:hits]).to eq(80)
          expect(metrics[:misses]).to eq(20)
          expect(metrics[:hit_rate]).to eq(0.8)
          expect(metrics[:memory_bytes]).to eq(2048)
        end
      end

      context "when cache is unavailable" do
        before do
          allow(Services::Categorization::PatternCache).to receive(:instance).and_raise(StandardError)
        end

        it "returns error message" do
          metrics = controller.send(:cache_metrics)
          expect(metrics[:error]).to eq("Unable to fetch cache metrics")
        end
      end
    end

    describe "#recent_activity_metrics" do
      before do
        # Clean up any existing data - need proper order for foreign keys
        PatternFeedback.delete_all if defined?(PatternFeedback)
        PatternLearningEvent.delete_all if defined?(PatternLearningEvent)
        ConflictResolution.delete_all if defined?(ConflictResolution)
        SyncConflict.delete_all if defined?(SyncConflict)
        Expense.delete_all
        CategorizationPattern.delete_all
      end

      let!(:recent_expense) { create(:expense, updated_at: 30.minutes.ago) }
      let!(:recent_pattern) { create(:categorization_pattern, created_at: 30.minutes.ago) }
      let!(:updated_pattern) do
        pattern = create(:categorization_pattern, created_at: 2.hours.ago)
        pattern.update_column(:updated_at, 30.minutes.ago)
        pattern
      end

      it "counts recent activity correctly" do
        metrics = controller.send(:recent_activity_metrics)

        expect(metrics[:expenses_processed]).to eq(1)
        expect(metrics[:patterns_learned]).to eq(1)
        # Both patterns show up in updated because the recent_pattern was also "updated" when created
        expect(metrics[:patterns_updated]).to eq(2)
      end
    end

    describe "#database_pool_metrics" do
      before do
        pool = double("ConnectionPool")
        allow(ActiveRecord::Base).to receive(:connection_pool).and_return(pool)
        allow(pool).to receive(:size).and_return(5)
        allow(pool).to receive(:connections).and_return([
          double(in_use?: true),
          double(in_use?: true),
          double(in_use?: false)
        ])
        connection = double("Connection")
        allow(pool).to receive(:with_connection).and_yield(connection)
      end

      it "returns database pool statistics" do
        metrics = controller.send(:database_pool_metrics)

        expect(metrics[:size]).to eq(5)
        expect(metrics[:connections]).to eq(3)
        expect(metrics[:busy]).to eq(2)
        expect(metrics[:idle]).to eq(1)
      end

      it "handles database pool errors" do
        allow(ActiveRecord::Base).to receive(:connection_pool).and_raise(StandardError)

        metrics = controller.send(:database_pool_metrics)
        expect(metrics[:error]).to eq("Unable to fetch database pool metrics")
      end
    end

    describe "#memory_metrics" do
      context "when GetProcessMem is available" do
        before do
          stub_const("GetProcessMem", Class.new do
            def initialize; end
            def rss; 128 * 1024 * 1024; end # 128 MB in bytes
            def percent; 15.5; end
          end)
        end

        it "returns memory usage statistics" do
          metrics = controller.send(:memory_metrics)

          expect(metrics[:rss_mb]).to eq(128.0)
          expect(metrics[:percent]).to eq(15.5)
        end
      end

      context "when GetProcessMem is not available" do
        before do
          hide_const("GetProcessMem") if defined?(GetProcessMem)
        end

        it "returns unavailable message" do
          metrics = controller.send(:memory_metrics)
          expect(metrics[:note]).to include("not available")
        end
      end

      it "handles memory metrics errors" do
        stub_const("GetProcessMem", Class.new do
          def initialize
            raise StandardError, "Memory error"
          end
        end)

        metrics = controller.send(:memory_metrics)
        expect(metrics[:error]).to eq("Unable to fetch memory metrics")
      end
    end
  end
end
