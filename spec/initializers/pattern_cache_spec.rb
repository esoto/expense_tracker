# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PatternCache initializer", :unit do
  let(:initializer_path) { Rails.root.join("config/initializers/pattern_cache.rb") }
  let(:content) { File.read(initializer_path) }

  describe "namespace correctness" do
    it "references Services::Categorization::PatternCache (fully qualified)" do
      expect(content).to include("Services::Categorization::PatternCache")
    end

    it "does not reference bare Categorization::PatternCache without Services prefix" do
      # Find all namespace-qualified PatternCache references (e.g., Foo::PatternCache)
      # Exclude standalone PatternCache (in comments/strings) — only check qualified refs
      qualified_refs = content.scan(/(\w+(?:::\w+)*::PatternCache)/)
      qualified_refs.flatten.each do |ref|
        expect(ref).to start_with("Services::Categorization::PatternCache"),
          "Found bare qualified reference: #{ref}"
      end
    end

    it "resolves Services::Categorization::PatternCache at runtime" do
      expect(defined?(Services::Categorization::PatternCache)).to be_truthy
    end

    it "does not resolve bare Categorization::PatternCache at top level" do
      expect(defined?(::Categorization::PatternCache)).to be_falsy
    end
  end

  describe "TTL configuration defaults" do
    it "configures memory TTL with default of 5 minutes" do
      expect(content).to include('ENV.fetch("PATTERN_CACHE_MEMORY_TTL", 5)')
      expect(content).to include(".to_i.minutes")
    end

    it "configures redis TTL with default of 24 hours" do
      expect(content).to include('ENV.fetch("PATTERN_CACHE_REDIS_TTL", 24)')
      expect(content).to include(".to_i.hours")
    end

    it "sets pattern_cache_memory_ttl on app config" do
      expect(content).to include("config.pattern_cache_memory_ttl")
    end

    it "sets pattern_cache_redis_ttl on app config" do
      expect(content).to include("config.pattern_cache_redis_ttl")
    end

    context "runtime config values" do
      it "has memory_ttl set to 5 minutes by default" do
        expect(Rails.application.config.pattern_cache_memory_ttl).to eq(5.minutes)
      end

      it "has redis_ttl set to 24 hours by default" do
        expect(Rails.application.config.pattern_cache_redis_ttl).to eq(24.hours)
      end
    end
  end

  describe "cache warming in production" do
    it "guards cache warming with production or staging check" do
      expect(content).to include("if Rails.env.production? || Rails.env.staging?")
    end

    it "uses after_initialize callback for cache warming" do
      warming_section = content[/if Rails\.env\.production\?.*?^end/m]
      expect(warming_section).to include("config.after_initialize")
    end

    it "warms cache via Services::Categorization::PatternCache.instance.warm_cache" do
      expect(content).to include("Services::Categorization::PatternCache.instance.warm_cache")
    end

    it "runs cache warming in a background thread" do
      warming_section = content[/if Rails\.env\.production\?.*?^end/m]
      expect(warming_section).to include("Thread.new")
    end

    it "uses connection pool for database access during warming" do
      expect(content).to include("ActiveRecord::Base.connection_pool.with_connection")
    end
  end

  describe "cache warming skipped in test and development" do
    it "does not warm cache in test environment" do
      # The guard is `if Rails.env.production? || Rails.env.staging?`
      # which excludes test and development
      warming_guard = content[/if Rails\.env\.production\? \|\| Rails\.env\.staging\?/]
      expect(warming_guard).to be_present
      expect(warming_guard).not_to include("test")
      expect(warming_guard).not_to include("development")
    end
  end

  describe "error handling in warming thread" do
    it "rescues errors during cache warming" do
      warming_section = content[/Thread\.new.*?end\s*end\s*end/m]
      expect(warming_section).to include("rescue => e")
    end

    it "logs error message on failure" do
      expect(content).to include('[PatternCache] Cache warming failed: #{e.message}')
    end

    it "logs backtrace on failure" do
      expect(content).to include("e.backtrace.join")
    end

  end

  describe "config logging block" do
    it "skips logging in test environment" do
      expect(content).to include("unless Rails.env.test?")
    end

    it "checks defined?(Services::Categorization::PatternCache) before logging" do
      logging_section = content[/unless Rails\.env\.test\?.*\z/m]
      expect(logging_section).to include("if defined?(Services::Categorization::PatternCache)")
    end

    it "logs cache configuration including memory_ttl, redis_ttl, and redis_available" do
      expect(content).to include("memory_ttl:")
      expect(content).to include("redis_ttl:")
      expect(content).to include("redis_available:")
    end

    it "uses fully qualified namespace in defined? guard" do
      defined_checks = content.scan(/defined\?\(([^)]+)\)/)
      defined_checks.each do |match|
        expect(match.first).to eq("Services::Categorization::PatternCache"),
          "Expected defined? guard to use fully qualified namespace, got: #{match.first}"
      end
    end
  end

end
