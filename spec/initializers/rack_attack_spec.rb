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

  describe "admin state-changing throttle (PER-507)" do
    # PER-507: centralize admin rate-limiting in Rack::Attack, replacing the
    # no-op `check_rate_limit` placeholder on Admin::BaseController. Read
    # the initializer source + verify the throttle rule is present with the
    # expected shape: limit 60/min/IP, POST/PATCH/PUT/DELETE to /admin/*.
    let(:initializer_content) { File.read(Rails.root.join("config/initializers/rack_attack.rb")) }
    let(:throttle_block) do
      initializer_content[/throttle\("admin\/state-changing\/ip".*?end\s*end/m]
    end

    it "registers a throttle named 'admin/state-changing/ip'" do
      expect(throttle_block).to be_present,
        "expected a Rack::Attack throttle for admin state-changing requests"
    end

    it "limits to 60 requests per minute per IP" do
      expect(throttle_block).to include("limit: 60")
      expect(throttle_block).to include("period: 1.minute")
    end

    it "scopes to /admin paths with a path anchor (not /admins or /admin_foo)" do
      # Check both forms: exact /admin OR /admin/ prefix.
      expect(throttle_block).to include('req.path == "/admin"')
      expect(throttle_block).to include('req.path.start_with?("/admin/")')
    end

    it "matches every state-changing HTTP method (POST, PATCH, PUT, DELETE)" do
      # Assert each verb individually — a single regex alternation would
      # silently pass if someone refactored to just `req.post?`, losing
      # coverage for the other three verbs.
      expect(throttle_block).to include("req.post?")
      expect(throttle_block).to include("req.patch?")
      expect(throttle_block).to include("req.put?")
      expect(throttle_block).to include("req.delete?")
    end

    it "documents PER-507 context in the initializer comments" do
      # Comment lives just above the throttle block (not captured by the
      # `throttle(...) do...end` regex) — assert anywhere in the file.
      expect(initializer_content).to match(/PER-507/)
    end
  end

  describe "blocklisted_responder" do
    # Rack::Attack hands the responder a Rack::Attack::Request, not a Rack
    # env hash. Treating it like a hash (e.g. env['HTTP_X_FORWARDED_FOR'])
    # raises NoMethodError on every blocked request, swallowing the intended
    # 403 with a 500. Lock the request-object API in.
    let(:initializer_content) { File.read(Rails.root.join("config/initializers/rack_attack.rb")) }
    # Anchor on the comment-section header below the lambda. The previous
    # `.*?end$` pattern truncated at the first inner `end` if the lambda
    # ever grew an `if/end` or `begin/rescue/end`, which would silently let
    # a regression past the negative assertions.
    let(:responder_block) do
      initializer_content[/self\.blocklisted_responder = lambda do.*?(?=^\s*# ===|\Z)/m]
    end

    it "is defined" do
      expect(responder_block).to be_present
    end

    it "uses the request object's API (req.ip, req.path), not env hash access" do
      # Word-boundary anchors so a typo like `req.ip_address` (which
      # doesn't exist on Rack::Request and would 500 in production) can't
      # silently pass a substring match.
      expect(responder_block).to match(/\breq\.ip\b/)
      expect(responder_block).to match(/\breq\.path\b/)
      expect(responder_block).not_to match(/env\[['"]HTTP_X_FORWARDED_FOR['"]\]/)
      expect(responder_block).not_to match(/env\[['"]REMOTE_ADDR['"]\]/)
      expect(responder_block).not_to match(/env\[['"]PATH_INFO['"]\]/)
    end

    it "returns 403 with a forbidden message" do
      expect(responder_block).to include("403")
      expect(responder_block).to include("Forbidden")
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
