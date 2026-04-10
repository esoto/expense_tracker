# frozen_string_literal: true

namespace :categorization do
  desc "Print categorization metrics summary report for the past 7 days"
  task metrics_report: :environment do
    CategorizationMetricsSummaryJob.perform_now
  end
end
