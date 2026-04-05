# frozen_string_literal: true

# Background job for running a comprehensive data quality audit on categorization patterns.
# Results are cached for 24 hours and consumed by the admin dashboard.
#
# Usage:
#   DataQualityAuditJob.perform_now          # Run immediately in foreground
#   DataQualityAuditJob.perform_later        # Enqueue for background execution
#
# Read cached result:
#   Rails.cache.read("data_quality:latest_audit")
class DataQualityAuditJob < ApplicationJob
  queue_as :low

  CACHE_KEY = "data_quality:latest_audit"
  CACHE_EXPIRY = 24.hours

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform
    Rails.logger.info "[DataQuality] Starting audit..."

    checker = Services::Categorization::Monitoring::DataQualityChecker.new
    result = checker.audit

    Rails.cache.write(CACHE_KEY, result, expires_in: CACHE_EXPIRY)

    grade = result.dig(:quality_score, :grade)
    score = result.dig(:quality_score, :overall)
    recommendations = result[:recommendations]&.count || 0

    Rails.logger.info "[DataQuality] Audit complete: grade=#{grade}, score=#{score}, recommendations=#{recommendations}"
  rescue StandardError => e
    Rails.logger.error "[DataQuality] Audit failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
