# frozen_string_literal: true

require "rails_helper"

# Note: Rack::Attack is disabled in the test environment via `return if Rails.env.test?`
# in the initializer. These specs verify the regex patterns and throttle configuration
# by testing path matching logic in isolation.
RSpec.describe "Rack::Attack throttle path matching", :unit do
  describe "pattern testing throttle regex" do
    # Covers all three actual routes:
    #   GET  /admin/patterns/test
    #   POST /admin/patterns/test_pattern
    #   GET  /admin/patterns/:id/test_single
    let(:pattern) { %r{/admin/patterns/(?:test(?:_pattern)?|[^/]+/test_single)} }

    context "GET /admin/patterns/test" do
      it "matches the test page route" do
        expect("/admin/patterns/test".match?(pattern)).to be true
      end
    end

    context "POST /admin/patterns/test_pattern" do
      it "matches the test_pattern route" do
        expect("/admin/patterns/test_pattern".match?(pattern)).to be true
      end
    end

    context "GET /admin/patterns/:id/test_single" do
      it "matches the test_single route" do
        expect("/admin/patterns/42/test_single".match?(pattern)).to be true
      end
    end

    context "unrelated paths" do
      it "does not match pattern export route" do
        expect("/admin/patterns/export".match?(pattern)).to be false
      end

      it "does not match pattern statistics route" do
        expect("/admin/patterns/statistics".match?(pattern)).to be false
      end
    end
  end

  describe "OLD broken pattern testing regex" do
    let(:broken_pattern) { %r{/admin/patterns/.*/test} }

    context "POST /admin/patterns/test_pattern" do
      it "does NOT match (this is the bug that PER-205 fixes)" do
        # The old regex required a segment BEFORE /test, but the actual POST
        # route is /admin/patterns/test_pattern which has no segment before /test
        expect("/admin/patterns/test_pattern".match?(broken_pattern)).to be false
      end
    end

    context "GET /admin/patterns/test" do
      it "does NOT match (this is the bug that PER-205 fixes)" do
        expect("/admin/patterns/test".match?(broken_pattern)).to be false
      end
    end
  end

  describe "export throttle path matching" do
    let(:csv_pattern) { /\.csv$/ }
    let(:export_pattern) { /\/export/ }

    context "analytics export route: GET /analytics/pattern_dashboard/export" do
      it "matches the export pattern" do
        path = "/analytics/pattern_dashboard/export"
        expect(path.match?(export_pattern)).to be true
      end
    end

    context "admin pattern export route: GET /admin/patterns/export" do
      it "matches the export pattern" do
        path = "/admin/patterns/export"
        expect(path.match?(export_pattern)).to be true
      end
    end

    context "CSV file requests" do
      it "matches .csv extension" do
        expect("/expenses.csv".match?(csv_pattern)).to be true
      end

      it "matches path with query params stripped (path only)" do
        expect("/reports/expenses.csv".match?(csv_pattern)).to be true
      end
    end

    context "unrelated paths" do
      it "does not match non-export routes" do
        expect("/admin/patterns/statistics".match?(export_pattern)).to be false
        expect("/admin/patterns/statistics".match?(csv_pattern)).to be false
      end
    end
  end

  describe "export throttle limit configuration" do
    # This test documents the expected limit value per ticket PER-205
    # The limit should be 5/hour, not 10/hour
    it "documents the correct limit as 5 per hour" do
      # Read the initializer source and verify the limit is set correctly
      initializer_path = Rails.root.join("config/initializers/rack_attack.rb")
      content = File.read(initializer_path)

      # Find the exports throttle block and verify it has limit: 5
      exports_section = content[/throttle\("exports\/ip".*?end/m]
      expect(exports_section).to be_present
      expect(exports_section).to include("limit: 5")
      expect(exports_section).not_to include("limit: 10")
    end
  end

  describe "cache store configuration" do
    it "uses Rails.cache unconditionally without Redis branching" do
      initializer_path = Rails.root.join("config/initializers/rack_attack.rb")
      content = File.read(initializer_path)

      # Must use Rails.cache directly, no Redis conditional
      expect(content).to include("Rack::Attack.cache.store = Rails.cache")
      expect(content).not_to include("RedisCacheStore")
      expect(content).not_to include('ENV["REDIS_URL"]')
    end
  end

  describe "middleware loading" do
    it "loads middleware in all non-test environments including development" do
      # In development, the middleware must be mounted so throttles can be
      # exercised without deploying to production/staging.
      # The safelist for localhost prevents actual rate limiting of local dev.
      initializer_path = Rails.root.join("config/initializers/rack_attack.rb")
      content = File.read(initializer_path)

      # Verify middleware is enabled via `unless Rails.env.test?` (covers dev + prod + staging)
      expect(content).to include("unless Rails.env.test?")
      # Must NOT use the old production/staging-only guard for middleware loading
      expect(content).not_to include("if Rails.env.production? || Rails.env.staging?\n  Rails.application.config.middleware.use Rack::Attack")
    end
  end
end
