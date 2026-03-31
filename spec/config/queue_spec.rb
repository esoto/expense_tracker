# frozen_string_literal: true

require "rails_helper"
require "yaml"
require "erb"

RSpec.describe "Queue configuration", :unit do
  let(:queue_config_path) { Rails.root.join("config", "queue.yml") }
  let(:raw_config) { File.read(queue_config_path) }
  let(:parsed_config) { YAML.safe_load(ERB.new(raw_config).result, permitted_classes: [Symbol], aliases: true) }
  let(:production_config) { parsed_config.fetch("production") }

  let(:production_worker_queues) do
    production_config.fetch("workers").flat_map { |w| w.fetch("queues") }.map(&:to_s)
  end

  let(:declared_queues) do
    job_files = Dir[Rails.root.join("app", "jobs", "**", "*.rb")]
    job_files.filter_map do |file|
      content = File.read(file)
      match = content.match(/queue_as\s+:(\w+)/)
      match[1] if match
    end.uniq.sort
  end

  describe "production workers" do
    it "has at least one worker block" do
      expect(production_config.fetch("workers")).not_to be_empty
    end

    it "covers all queues declared by application jobs" do
      missing = declared_queues - production_worker_queues

      expect(missing).to be_empty,
        "The following job queues have no matching worker in production queue.yml: #{missing.join(', ')}"
    end

    it "includes the bulk_operations queue" do
      expect(production_worker_queues).to include("bulk_operations")
    end

    it "includes the low queue" do
      expect(production_worker_queues).to include("low")
    end

    it "includes the low_priority queue" do
      expect(production_worker_queues).to include("low_priority")
    end
  end

  describe "worker configuration" do
    it "assigns priority to each worker block" do
      production_config.fetch("workers").each do |worker|
        expect(worker).to have_key("priority"),
          "Worker for queues #{worker['queues'].inspect} is missing a priority setting"
      end
    end

    it "assigns threads to each worker block" do
      production_config.fetch("workers").each do |worker|
        expect(worker).to have_key("threads"),
          "Worker for queues #{worker['queues'].inspect} is missing a threads setting"
      end
    end
  end
end
