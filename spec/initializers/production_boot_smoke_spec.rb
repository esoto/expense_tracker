# frozen_string_literal: true

require "rails_helper"

# Production-boot smoke regression — catches initializer-time NameErrors
# and DB-dependent `after_initialize` blocks that fail during the Docker
# build's `SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile` step.
#
# Discovered 2026-04-17 during the first Hetzner `kamal setup` attempt:
# two latent bugs blocked asset compile and therefore the entire deploy.
# Source-level regression guards are the only cheap way to catch this in
# the test suite — booting Rails in production env from RSpec is too
# environment-sensitive. A future improvement would be a CI job that
# actually runs `assets:precompile` in a containerized production env.
RSpec.describe "production-boot safety of config/initializers", :unit do
  describe "config/initializers/categorization.rb" do
    let(:source) { File.read(Rails.root.join("config/initializers/categorization.rb")) }

    it "uses the Services::-prefixed constant (autoloading.rb registers the namespace)" do
      expect(source).to include("Services::Categorization::Monitoring::MetricsCollector")
    end

    it "does not reference the un-namespaced Categorization::Monitoring::MetricsCollector form" do
      expect(source).not_to match(/(?<!Services::)\bCategorization::Monitoring::MetricsCollector/)
    end

    it "defers the .instance call to after_initialize (not at initializer load time)" do
      # Referencing Services::Categorization during another initializer
      # races Zeitwerk namespace registration; deferring to
      # after_initialize lets the autoloader finish first.
      expect(source).to include("Rails.application.config.after_initialize")
    end
  end

  describe "config/initializers/performance_optimizations.rb" do
    let(:source) { File.read(Rails.root.join("config/initializers/performance_optimizations.rb")) }

    it "does NOT call SolidQueue::RecurringJob.create (the API does not exist)" do
      # SolidQueue::RecurringJob is an ActiveJob::Base subclass with no
      # .create method; the original code raised NoMethodError at boot.
      # Recurring work belongs in config/recurring.yml, not in an initializer.
      expect(source).not_to match(/SolidQueue::RecurringJob\.create/)
    end

    it "guards cache warm-up with a DB-connectivity check for build-time safety" do
      # The cache-warmup after_initialize must no-op during
      # assets:precompile (no DB). Any of: connection_pool check,
      # rescue on ConnectionNotEstablished, or equivalent is acceptable.
      expect(source).to match(/connection_pool\.active_connection\?|ConnectionNotEstablished|connected\?/)
    end
  end
end
