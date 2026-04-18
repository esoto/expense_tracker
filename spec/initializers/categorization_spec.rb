# frozen_string_literal: true

require "rails_helper"

# Regression spec for the categorization initializer. Rails evaluates
# initializers once at boot; any NameError there takes down the app AND
# `assets:precompile` during the production Docker build.
#
# Discovered 2026-04-17 during the first `kamal setup` attempt: the initializer
# referenced `Categorization::Monitoring::MetricsCollector.instance` — but
# `config/initializers/autoloading.rb` namespaces everything under
# `app/services/` with a `Services::` prefix (introduced in 9fb225f, after
# this initializer was originally written), so the unqualified constant does
# not exist and Zeitwerk raises `uninitialized constant Categorization`.
#
# The assets:precompile Docker layer is the earliest place that boots Rails
# with `Rails.env.production?`, which is what gates the `.instance` call.
# We test BEHAVIOR (can the initializer's expression resolve?) plus a
# source-level regression guard against the un-namespaced form.
RSpec.describe "config/initializers/categorization.rb", :unit do
  let(:initializer_source) { File.read(Rails.root.join("config/initializers/categorization.rb")) }

  describe "monitoring bootstrap reference" do
    it "resolves the fully-qualified Services::Categorization::Monitoring::MetricsCollector constant" do
      # If this raises NameError, the initializer is broken and production
      # boot will fail. The test loads the class via the same autoload path
      # the initializer uses.
      expect { Services::Categorization::Monitoring::MetricsCollector }.not_to raise_error
      expect(Services::Categorization::Monitoring::MetricsCollector).to respond_to(:instance)
    end

    it "references the Services::-prefixed form in the initializer source" do
      expect(initializer_source).to include("Services::Categorization::Monitoring::MetricsCollector")
    end

    it "does NOT reference the un-namespaced Categorization::Monitoring::MetricsCollector form" do
      # Guard against regression. Matches `Categorization::Monitoring` ONLY
      # when not preceded by `Services::` — the anchor `[^:]` prevents the
      # Services-prefixed string from matching.
      expect(initializer_source).not_to match(/(?<!Services::)\bCategorization::Monitoring::MetricsCollector/)
    end
  end

  describe "configuration loading" do
    it "exposes categorization config on config.x after initializer runs" do
      expect(Rails.application.config.x.categorization).to be_a(Hash)
    end
  end
end
