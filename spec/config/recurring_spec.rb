# frozen_string_literal: true

require "rails_helper"
require "yaml"
require "erb"

RSpec.describe "Recurring tasks configuration", :unit do
  let(:recurring_config_path) { Rails.root.join("config", "recurring.yml") }
  let(:raw_config) { File.read(recurring_config_path) }
  let(:parsed_config) { YAML.safe_load(ERB.new(raw_config).result, permitted_classes: [Symbol], aliases: true) }
  let(:production_recurring) { parsed_config.fetch("production") }

  describe "broadcast jobs" do
    it "schedules BroadcastAnalyticsCleanupJob hourly" do
      entry = production_recurring.find { |key, _| key == "broadcast_analytics_cleanup" }
      expect(entry).not_to be_nil, "Missing broadcast_analytics_cleanup in production recurring tasks"

      config = entry.last
      expect(config["class"]).to eq("BroadcastAnalyticsCleanupJob")
      expect(config["schedule"]).to match(/every.*hour/i)
      expect(config["queue"]).to eq("low")
    end

    it "schedules FailedBroadcastRecoveryJob every 30 minutes" do
      entry = production_recurring.find { |key, _| key == "failed_broadcast_recovery" }
      expect(entry).not_to be_nil, "Missing failed_broadcast_recovery in production recurring tasks"

      config = entry.last
      expect(config["class"]).to eq("FailedBroadcastRecoveryJob")
      expect(config["schedule"]).to match(/every.*30.*minute/i)
      expect(config["queue"]).to eq("low")
    end
  end

  describe "recurring task queues" do
    let(:queue_config_path) { Rails.root.join("config", "queue.yml") }
    let(:queue_raw) { File.read(queue_config_path) }
    let(:queue_parsed) { YAML.safe_load(ERB.new(queue_raw).result, permitted_classes: [Symbol], aliases: true) }
    let(:production_worker_queues) do
      queue_parsed.fetch("production").fetch("workers").flat_map { |w| w.fetch("queues") }.map(&:to_s)
    end

    it "all recurring task queues are covered by production workers" do
      recurring_queues = production_recurring.values
        .select { |v| v.is_a?(Hash) && v["queue"] }
        .map { |v| v["queue"] }
        .uniq

      missing = recurring_queues - production_worker_queues
      expect(missing).to be_empty,
        "Recurring task queues not covered by production workers: #{missing.join(', ')}"
    end
  end

  describe "no sidekiq scheduler" do
    it "sidekiq.yml does not exist" do
      expect(File.exist?(Rails.root.join("config", "sidekiq.yml"))).to be false
    end
  end
end
