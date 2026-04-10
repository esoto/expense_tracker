# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "categorization:metrics_report", :unit, type: :task do
  let(:rake) { Rake::Application.new }

  before do
    Rake.application = rake
    Rake::Task.define_task(:environment)
    load Rails.root.join("lib/tasks/categorization_metrics.rake")
  end

  it "invokes CategorizationMetricsSummaryJob.perform_now" do
    allow(CategorizationMetricsSummaryJob).to receive(:perform_now)

    Rake::Task["categorization:metrics_report"].invoke

    expect(CategorizationMetricsSummaryJob).to have_received(:perform_now)
  end
end
