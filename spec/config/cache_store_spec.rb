# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cache store configuration", :unit do
  describe "initializers do not override cache_store" do
    let(:initializer_files) do
      Dir[Rails.root.join("config", "initializers", "*.rb")]
    end

    it "no initializer sets config.cache_store" do
      offending_files = initializer_files.select do |file|
        content = File.read(file)
        content.match?(/config\.cache_store\s*=/)
      end

      expect(offending_files).to be_empty,
        "These initializers override config.cache_store (should only be set in config/environments/*.rb): " \
        "#{offending_files.map { |f| File.basename(f) }.join(', ')}"
    end
  end

  describe "environment config sets cache_store" do
    it "production.rb configures solid_cache_store" do
      content = File.read(Rails.root.join("config", "environments", "production.rb"))
      expect(content).to include("solid_cache_store"),
        "production.rb should configure :solid_cache_store as the authoritative cache store"
    end
  end

  describe "redis.rb removed (PER-315)" do
    it "redis.rb initializer no longer exists" do
      expect(File.exist?(Rails.root.join("config", "initializers", "redis.rb"))).to be false
    end
  end

  describe "performance_optimizations.rb does not override Rails.cache" do
    it "does not set cache_store" do
      content = File.read(Rails.root.join("config", "initializers", "performance_optimizations.rb"))

      expect(content).not_to match(/config\.cache_store\s*=/),
        "performance_optimizations.rb should not set config.cache_store"
    end
  end
end
