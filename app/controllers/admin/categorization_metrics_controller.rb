# frozen_string_literal: true

module Admin
  # Displays categorization system performance metrics.
  class CategorizationMetricsController < BaseController
    def index
      service = Services::Categorization::Monitoring::MetricsDashboardService.new
      @overview = service.overview
      @layer_performance = service.layer_performance
      @problem_merchants = service.problem_merchants
    end
  end
end
