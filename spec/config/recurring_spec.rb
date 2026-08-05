# frozen_string_literal: true

require "rails_helper"
require "yaml"
require "erb"

RSpec.describe "Recurring tasks configuration", :unit do
  let(:recurring_config_path) { Rails.root.join("config", "recurring.yml") }
  let(:raw_config) { File.read(recurring_config_path) }
  let(:parsed_config) { YAML.safe_load(ERB.new(raw_config).result, permitted_classes: [ Symbol ], aliases: true) }
  let(:production_recurring) { parsed_config.fetch("production") }

  describe "broadcast jobs" do
    it "schedules BroadcastAnalyticsCleanupJob hourly" do
      config = production_recurring.fetch("broadcast_analytics_cleanup")
      expect(config["class"]).to eq("BroadcastAnalyticsCleanupJob")
      expect(config["schedule"]).to match(/every.*hour/i)
      expect(config["queue"]).to eq("low")
      expect(config).not_to have_key("command"), "Use class: instead of command: for job-based tasks"
    end

    it "schedules FailedBroadcastRecoveryJob every 30 minutes" do
      config = production_recurring.fetch("failed_broadcast_recovery")
      expect(config["class"]).to eq("FailedBroadcastRecoveryJob")
      expect(config["schedule"]).to match(/every.*30.*minute/i)
      expect(config["queue"]).to eq("low")
      expect(config).not_to have_key("command"), "Use class: instead of command: for job-based tasks"
    end
  end

  describe "recurring task queues" do
    let(:queue_config_path) { Rails.root.join("config", "queue.yml") }
    let(:queue_raw) { File.read(queue_config_path) }
    let(:queue_parsed) { YAML.safe_load(ERB.new(queue_raw).result, permitted_classes: [ Symbol ], aliases: true) }
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

  describe "time zone pinning" do
    # solid_queue >= 1.5 added an engine initializer that defaults any entry
    # missing time_zone: to config.time_zone ("Central America", UTC-6) via
    # SolidQueue::RecurringTask. Before 1.5, unpinned schedules ran in
    # process-local time (UTC in the container). We assert PRESENCE of an
    # explicit time_zone rather than a specific value: a future job may
    # legitimately want a different zone (e.g. "America/Costa_Rica"), and
    # this guard only needs to catch entries that forgot to make that choice
    # deliberately, not enforce which zone they picked.
    it "declares an explicit time_zone for every production job entry" do
      missing = production_recurring.select { |_name, cfg| cfg.is_a?(Hash) }
        .reject { |_name, cfg| cfg.key?("time_zone") }
        .keys

      expect(missing).to be_empty,
        "Recurring task entries missing an explicit time_zone (solid_queue >= 1.5 " \
        "otherwise defaults to config.time_zone, silently shifting the schedule): " \
        "#{missing.join(', ')}"
    end

    it "declares a non-blank time_zone value for every production job entry" do
      blank = production_recurring.select { |_name, cfg| cfg.is_a?(Hash) && cfg.key?("time_zone") }
        .select { |_name, cfg| cfg["time_zone"].nil? || cfg["time_zone"].to_s.strip.empty? }
        .keys

      expect(blank).to be_empty,
        "Recurring task entries with a blank time_zone: #{blank.join(', ')}"
    end
  end

  describe "Solid Queue is the active scheduler" do
    it "recurring.yml exists with a production section" do
      expect(File.exist?(Rails.root.join("config", "recurring.yml"))).to be true
      expect(production_recurring).not_to be_empty
    end

    it "sidekiq.yml does not exist" do
      expect(File.exist?(Rails.root.join("config", "sidekiq.yml"))).to be false
    end
  end
end
