# frozen_string_literal: true

# Load categorization configuration
Rails.application.configure do
  categorization_config = Rails.application.config_for(:categorization)

  config.x.categorization = (categorization_config || {}).deep_symbolize_keys
end

# Initialize monitoring if in production or explicitly enabled.
#
# Must defer to `after_initialize` for two reasons:
# 1. The `Services::` prefix is required (set up by
#    `config/initializers/autoloading.rb`, which registers the namespace
#    with Zeitwerk). That registration is only effective for on-demand
#    autoloading AFTER the autoloader finishes booting — referencing the
#    constant during another initializer raises `uninitialized constant
#    Services::Categorization`.
# 2. `assets:precompile` loads the environment with
#    `Rails.env.production?` true but without a live database; touching
#    the MetricsCollector singleton at initializer time would fail the
#    Docker build. `after_initialize` runs after eager-load completes
#    but before the first request — and it is skipped entirely during
#    rake tasks that don't boot the full application (like
#    `assets:precompile`'s internal calls).
if Rails.env.production? || ENV["ENABLE_CATEGORIZATION_MONITORING"] == "true"
  Rails.application.config.after_initialize do
    Services::Categorization::Monitoring::MetricsCollector.instance
  end
end
