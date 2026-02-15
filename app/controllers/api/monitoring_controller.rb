# frozen_string_literal: true

module Api
  # API endpoint for monitoring and dashboard metrics
  class MonitoringController < ApplicationController
    skip_before_action :authenticate_user!
    before_action :authenticate_api_request, only: [ :metrics ]

    # GET /api/monitoring/metrics
    # Returns comprehensive dashboard metrics using the configured strategy
    def metrics
      adapter = Services::Categorization::Monitoring::DashboardAdapter.new

      render json: {
        status: "success",
        strategy: adapter.strategy_info,
        metrics: adapter.metrics_summary,
        timestamp: Time.current.iso8601
      }
    end

    # GET /api/monitoring/health
    # Simple health check endpoint
    def health
      render json: {
        status: "healthy",
        timestamp: Time.current.iso8601
      }
    end

    # GET /api/monitoring/strategy
    # Returns current dashboard strategy information
    def strategy
      adapter = Services::Categorization::Monitoring::DashboardAdapter.new

      render json: {
        current_strategy: adapter.strategy_name,
        strategy_info: adapter.strategy_info,
        available_strategies: Services::Categorization::Monitoring::DashboardAdapter::STRATEGIES.keys,
        configuration_source: adapter.strategy_info[:source]
      }
    end

    private

    def authenticate_api_request
      # Simple API token authentication
      api_token = request.headers["X-API-Token"] || params[:api_token]

      unless api_token.present? && ApiToken.active.where(token: api_token).exists?
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end
  end
end
