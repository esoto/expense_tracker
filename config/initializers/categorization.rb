# frozen_string_literal: true

# Load categorization configuration
Rails.application.configure do
  categorization_config = Rails.application.config_for(:categorization)

  config.x.categorization = (categorization_config || {}).deep_symbolize_keys
end

# Initialize monitoring if in production or explicitly enabled
if Rails.env.production? || ENV["ENABLE_CATEGORIZATION_MONITORING"] == "true"
  require "categorization/monitoring/metrics_collector"
  require "categorization/monitoring/health_check"
  require "categorization/monitoring/structured_logger"

  # Initialize metrics collector on startup
  Categorization::Monitoring::MetricsCollector.instance
end
