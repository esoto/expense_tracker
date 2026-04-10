# frozen_string_literal: true

# Weekly background job that computes categorization performance summaries
# and tracks ONNX evaluation trigger warnings.
#
# Computes per-layer accuracy, LLM fallback rate, user correction rate,
# total API spend, and average confidence for the past 7 days.
#
# Tracks consecutive weeks of poor performance and logs warnings when
# thresholds are sustained, recommending ONNX model evaluation.
#
# Runs weekly via Solid Queue recurring schedule (Sundays at 6am).
#
# Usage:
#   CategorizationMetricsSummaryJob.perform_now   # Run immediately
#   CategorizationMetricsSummaryJob.perform_later  # Enqueue for background execution
class CategorizationMetricsSummaryJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  REPORT_PERIOD = 7.days
  FALLBACK_RATE_THRESHOLD = 0.15
  CORRECTION_RATE_THRESHOLD = 0.10
  WARNING_WEEKS = 3
  STRONG_RECOMMENDATION_WEEKS = 12
  COUNTER_TTL = 90.days

  FALLBACK_COUNTER_KEY = "onnx_trigger:fallback_weeks"
  CORRECTION_COUNTER_KEY = "onnx_trigger:correction_weeks"

  def perform
    metrics = CategorizationMetric.recent(REPORT_PERIOD)
    total = metrics.count

    if total.zero?
      Rails.logger.info "[MetricsSummary] No categorization metrics found for the past #{REPORT_PERIOD.in_days.to_i} days"
      return
    end

    summary = compute_summary(metrics, total)
    log_summary(summary)
    evaluate_onnx_triggers(summary)
  end

  private

  def compute_summary(metrics, total)
    corrections = metrics.corrected.count
    haiku_count = metrics.for_layer("haiku").count
    api_spend = metrics.sum(:api_cost)

    layer_stats = compute_layer_stats(metrics)

    {
      total: total,
      corrections: corrections,
      haiku_count: haiku_count,
      fallback_rate: haiku_count.to_f / total,
      correction_rate: corrections.to_f / total,
      api_spend: api_spend,
      layer_stats: layer_stats
    }
  end

  def compute_layer_stats(metrics)
    layers = metrics.group(:layer_used).count
    corrections_by_layer = metrics.corrected.group(:layer_used).count
    confidence_by_layer = metrics.group(:layer_used).average(:confidence)

    layers.each_with_object({}) do |(layer, count), stats|
      corrected = corrections_by_layer[layer] || 0
      accuracy = ((count - corrected).to_f / count * 100).round(1)
      avg_confidence = confidence_by_layer[layer]&.round(4) || 0.0

      stats[layer] = {
        total: count,
        corrected: corrected,
        accuracy: accuracy,
        avg_confidence: avg_confidence
      }
    end
  end

  def log_summary(summary)
    Rails.logger.info "[MetricsSummary] === Weekly Categorization Metrics Report ==="
    Rails.logger.info "[MetricsSummary] Period: past #{REPORT_PERIOD.in_days.to_i} days | Total: #{summary[:total]}"
    Rails.logger.info "[MetricsSummary] Fallback rate: #{format_pct(summary[:fallback_rate])} " \
                      "(#{summary[:haiku_count]} haiku / #{summary[:total]} total)"
    Rails.logger.info "[MetricsSummary] Correction rate: #{format_pct(summary[:correction_rate])} " \
                      "(#{summary[:corrections]} / #{summary[:total]} total)"
    Rails.logger.info "[MetricsSummary] API spend: #{summary[:api_spend]}"

    summary[:layer_stats].each do |layer, stats|
      Rails.logger.info "[MetricsSummary] Layer #{layer}: accuracy=#{stats[:accuracy]}% " \
                        "total=#{stats[:total]} corrected=#{stats[:corrected]} " \
                        "avg_confidence=#{stats[:avg_confidence]}"
    end
  end

  def evaluate_onnx_triggers(summary)
    evaluate_fallback_trigger(summary[:fallback_rate])
    evaluate_correction_trigger(summary[:correction_rate])
    check_strong_recommendation
  end

  def evaluate_fallback_trigger(fallback_rate)
    if fallback_rate > FALLBACK_RATE_THRESHOLD
      counter = increment_counter(FALLBACK_COUNTER_KEY)
      if counter >= WARNING_WEEKS
        Rails.logger.warn "[MetricsSummary] ONNX WARNING: High fallback rate sustained for " \
                          "#{counter} consecutive weeks. Consider evaluating ONNX model deployment."
      end
    else
      reset_counter(FALLBACK_COUNTER_KEY)
    end
  end

  def evaluate_correction_trigger(correction_rate)
    if correction_rate > CORRECTION_RATE_THRESHOLD
      counter = increment_counter(CORRECTION_COUNTER_KEY)
      if counter >= WARNING_WEEKS
        Rails.logger.warn "[MetricsSummary] ONNX WARNING: High correction rate sustained for " \
                          "#{counter} consecutive weeks. Consider evaluating ONNX model deployment."
      end
    else
      reset_counter(CORRECTION_COUNTER_KEY)
    end
  end

  def check_strong_recommendation
    fallback_weeks = Rails.cache.read(FALLBACK_COUNTER_KEY) || 0
    correction_weeks = Rails.cache.read(CORRECTION_COUNTER_KEY) || 0

    return unless fallback_weeks >= STRONG_RECOMMENDATION_WEEKS && correction_weeks >= STRONG_RECOMMENDATION_WEEKS

    Rails.logger.warn "[MetricsSummary] STRONG RECOMMENDATION: Both fallback and correction rates " \
                      "have been elevated for #{STRONG_RECOMMENDATION_WEEKS} weeks. " \
                      "Strongly recommend evaluating ONNX model deployment to reduce API costs and improve accuracy."
  end

  def increment_counter(key)
    current = Rails.cache.read(key) || 0
    new_value = current + 1
    Rails.cache.write(key, new_value, expires_in: COUNTER_TTL)
    new_value
  end

  def reset_counter(key)
    Rails.cache.write(key, 0, expires_in: COUNTER_TTL)
  end

  def format_pct(rate)
    "#{(rate * 100).round(1)}%"
  end
end
