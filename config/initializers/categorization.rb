# frozen_string_literal: true

# Load categorization configuration
Rails.application.configure do
  categorization_config = Rails.application.config_for(:categorization)

  config.x.categorization = (categorization_config || {}).deep_symbolize_keys
end

# Initialize monitoring if in production or explicitly enabled.
#
# The `.instance` call is deferred to `after_initialize` because
# `config/initializers/autoloading.rb` registers the `Services::`
# namespace with Zeitwerk during its own initializer run — that
# registration only takes effect for on-demand autoloading once the
# autoloader has finished booting. Referencing
# `Services::Categorization::…` from another initializer (same phase)
# raises `uninitialized constant Services::Categorization`. Waiting for
# `after_initialize` lets the autoloader settle first. The underlying
# `MetricsCollector#initialize` is DB-free, so this hook runs safely
# under `assets:precompile` with no database connection.
if Rails.env.production? || ENV["ENABLE_CATEGORIZATION_MONITORING"] == "true"
  Rails.application.config.after_initialize do
    Services::Categorization::Monitoring::MetricsCollector.instance
  end
end
