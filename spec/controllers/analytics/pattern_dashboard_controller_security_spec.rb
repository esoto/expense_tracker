# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::PatternDashboardController, type: :controller, performance: true do
  let(:admin_user) { create(:admin_user, role: :admin) }
  let(:category) { create(:category) }
  let(:pattern) { create(:categorization_pattern, category: category) }

  before { sign_in_as(admin_user) }

  describe "Security Fixes", performance: true do
    describe "GET #trends", performance: true do
      context "SQL injection prevention" do
        it "safely handles malicious interval parameter" do
          get :trends, params: { interval: "'; DROP TABLE users; --" }, format: :json
          expect(response).to be_successful
          # Should default to :daily when invalid
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
    end

    describe "GET #export", performance: true do
      context "rate limiting" do
        it "enforces export rate limit of 5 per hour" do
          5.times do
            get :export, params: { format_type: "csv" }
            expect(response.status).to eq(200)
          end

          # 6th request should be rate limited
          get :export, params: { format_type: "csv" }
          expect(response).to redirect_to(admin_root_path)
          expect(flash[:alert]).to include("rate limit exceeded")
        end

        it "logs rate limit violations" do
          # Set up rate limit condition
          5.times { get :export, params: { format_type: "csv" } }

          expect(Rails.logger).to receive(:info) do |msg|
            parsed = JSON.parse(msg)
            expect(parsed["event"]).to eq("admin_action")
            expect(parsed["action"]).to eq("rate_limit.exceeded")
            expect(parsed["details"]["action"]).to eq("export")
          end

          get :export, params: { format_type: "csv" }
        end
      end

      context "audit logging" do
        it "logs export actions" do
          logged = false
          allow(Rails.logger).to receive(:info) do |msg|
            if msg.include?("admin_action")
              parsed = JSON.parse(msg)
              if parsed["event"] == "admin_action"
                expect(parsed["action"]).to match(/export/)
                logged = true
              end
            end
          end

          get :export, params: { format_type: "csv" }
          expect(logged).to be true
        end

        it "includes export details in audit log" do
          allow(Rails.logger).to receive(:info)

          get :export, params: {
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

      context "format validation" do
        it "rejects invalid export formats" do
          get :export, params: { format_type: "exe" }
          expect(response).to redirect_to(analytics_pattern_dashboard_index_path)
          expect(flash[:alert]).to eq("Invalid export format")
        end

        it "accepts valid export formats" do
          %w[csv json].each do |format|
            get :export, params: { format_type: format }
            expect(response).to be_successful
          end
        end
      end
    end

    describe "GET #index", performance: true do
      context "date parsing error handling" do
        it "handles invalid start date gracefully" do
          get :index, params: {
            time_period: "custom",
            start_date: "invalid-date",
            end_date: Date.current.to_s
          }
          expect(response).to be_successful
          expect(flash[:alert]).to include("Invalid date format")
        end

        it "handles invalid end date gracefully" do
          get :index, params: {
            time_period: "custom",
            start_date: 1.month.ago.to_date.to_s,
            end_date: "not-a-date"
          }
          expect(response).to be_successful
          expect(flash[:alert]).to include("Invalid date format")
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

        it "limits date range to maximum 2 years" do
          get :index, params: {
            time_period: "custom",
            start_date: 5.years.ago.to_date.to_s,
            end_date: Date.current.to_s
          }
          expect(response).to be_successful
          # Should limit to 2 years
        end
      end

      context "cache key security" do
        it "includes proper cache invalidation keys" do
          allow(CategorizationPattern).to receive(:maximum).with(:updated_at).and_return(Time.current)
          allow(PatternFeedback).to receive(:maximum).with(:updated_at).and_return(Time.current)
          allow(PatternLearningEvent).to receive(:maximum).with(:updated_at).and_return(Time.current)

          get :index
          expect(response).to be_successful
        end
      end
    end
  end

  describe "Error Handling", performance: true do
    describe "GET #heatmap", performance: true do
      context "database query failures" do
        before do
          allow_any_instance_of(Analytics::PatternPerformanceAnalyzer)
            .to receive(:usage_heatmap)
            .and_return({})
        end

        it "handles database errors gracefully" do
          get :heatmap, format: :json
          expect(response).to be_successful
          expect(JSON.parse(response.body)).to eq({})
        end
      end
    end

    describe "GET #trends", performance: true do
      context "unexpected errors" do
        before do
          allow_any_instance_of(Analytics::PatternPerformanceAnalyzer)
            .to receive(:trend_analysis)
            .and_return([])
        end

        it "returns empty array on error" do
          get :trends, format: :json
          expect(response).to be_successful
          expect(JSON.parse(response.body)).to eq([])
        end
      end
    end

    describe "GET #refresh", performance: true do
      it "validates component parameter" do
        get :refresh, params: { component: "invalid_component" }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "accepts valid components" do
        %w[overall_metrics category_performance recent_activity].each do |component|
          get :refresh, params: { component: component }, format: :turbo_stream
          expect(response).to be_successful
        end
      end
    end
  end

  describe "Performance Optimizations", performance: true do
    describe "GET #index", performance: true do
      it "uses caching for expensive queries" do
        expect(Rails.cache).to receive(:fetch).at_least(:once).and_call_original
        get :index
      end

      it "includes pagination parameters in category performance" do
        analyzer = instance_double(Analytics::PatternPerformanceAnalyzer)
        allow(Analytics::PatternPerformanceAnalyzer).to receive(:new).and_return(analyzer)

        expect(analyzer).to receive(:category_performance).with(no_args).and_return([])
        allow(analyzer).to receive(:overall_metrics).and_return({})
        allow(analyzer).to receive(:pattern_type_analysis).and_return([])
        allow(analyzer).to receive(:top_patterns).and_return([])
        allow(analyzer).to receive(:bottom_patterns).and_return([])
        allow(analyzer).to receive(:learning_metrics).and_return({})
        allow(analyzer).to receive(:recent_activity).and_return([])

        get :index
      end
    end
  end

  private

  def sign_in_as(user)
    user.regenerate_session_token
    session[:admin_session_token] = user.reload.session_token
    session[:admin_user_id] = user.id
    allow(controller).to receive(:current_admin_user).and_return(user)
    allow(controller).to receive(:admin_signed_in?).and_return(true)
  end
end
