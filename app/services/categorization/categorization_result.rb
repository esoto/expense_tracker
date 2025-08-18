# frozen_string_literal: true

module Categorization
  # Value object representing the result of a categorization operation
  # Stores all relevant information about the categorization including
  # confidence breakdown, patterns used, and performance metrics
  class CategorizationResult
    attr_reader :category, :confidence, :patterns_used, :confidence_breakdown,
                :alternative_categories, :processing_time_ms, :cache_hits,
                :method, :error, :metadata

    def initialize(
      category: nil,
      confidence: 0.0,
      patterns_used: [],
      confidence_breakdown: {},
      alternative_categories: [],
      processing_time_ms: 0.0,
      cache_hits: 0,
      method: nil,
      error: nil,
      metadata: {}
    )
      @category = category
      @confidence = confidence
      @patterns_used = patterns_used
      @confidence_breakdown = confidence_breakdown
      @alternative_categories = alternative_categories
      @processing_time_ms = processing_time_ms
      @cache_hits = cache_hits
      @method = method
      @error = error
      @metadata = metadata
      @created_at = Time.current
    end

    # Factory methods

    def self.no_match(processing_time_ms: 0.0)
      new(
        method: "no_match",
        processing_time_ms: processing_time_ms,
        metadata: { reason: "No matching patterns found" }
      )
    end

    def self.from_user_preference(category, confidence, processing_time_ms: 0.0)
      new(
        category: category,
        confidence: confidence,
        method: "user_preference",
        patterns_used: [],
        processing_time_ms: processing_time_ms,
        metadata: { source: "user_preference" }
      )
    end

    def self.from_pattern_match(category, confidence_score, patterns, processing_time_ms: 0.0)
      new(
        category: category,
        confidence: confidence_score.score,
        method: "pattern_match",
        patterns_used: patterns.map { |p| pattern_description(p) },
        confidence_breakdown: confidence_score.factor_breakdown,
        processing_time_ms: processing_time_ms,
        metadata: confidence_score.metadata
      )
    end

    def self.error(message, processing_time_ms: 0.0)
      new(
        error: message,
        method: "error",
        processing_time_ms: processing_time_ms,
        metadata: { error: true }
      )
    end

    # Query methods

    def successful?
      @error.nil? && @category.present?
    end

    def failed?
      !successful?
    end

    def error?
      @error.present?
    end

    def high_confidence?
      @confidence >= 0.85
    end

    def medium_confidence?
      @confidence >= 0.70 && @confidence < 0.85
    end

    def low_confidence?
      @confidence < 0.70
    end

    def confidence_level
      case @confidence
      when 0.95..1.0
        :very_high
      when 0.85...0.95
        :high
      when 0.70...0.85
        :medium
      when 0.50...0.70
        :low
      else
        :very_low
      end
    end

    def user_preference?
      @method == "user_preference"
    end

    def pattern_match?
      @method == "pattern_match"
    end

    def no_match?
      @method == "no_match"
    end

    def performance_within_target?(target_ms = 10.0)
      @processing_time_ms <= target_ms
    end

    # Analysis methods

    def dominant_factor
      return nil unless @confidence_breakdown.present?

      @confidence_breakdown.max_by { |_, details| details[:contribution] }&.first
    end

    def explain
      parts = []

      if successful?
        parts << "Category: #{@category.name}"
        parts << "Confidence: #{(@confidence * 100).round(1)}% (#{confidence_level})"
        parts << "Method: #{@method.humanize}"

        if @patterns_used.any?
          parts << "Patterns used: #{@patterns_used.join(', ')}"
        end

        if @confidence_breakdown.present?
          parts << "Confidence factors:"
          @confidence_breakdown.each do |factor, details|
            parts << "  - #{factor.to_s.humanize}: #{(details[:value] * 100).round(1)}%"
          end
        end

        if @alternative_categories.any?
          parts << "Alternative categories:"
          @alternative_categories.each do |alt|
            parts << "  - #{alt[:category].name}: #{(alt[:confidence] * 100).round(1)}%"
          end
        end
      elsif no_match?
        parts << "No matching patterns found"
      elsif @error.present?
        parts << "Error: #{@error}"
      end

      parts << "Processing time: #{@processing_time_ms.round(2)}ms"
      parts << "Cache hits: #{@cache_hits}" if @cache_hits > 0

      parts.join("\n")
    end

    # Export methods

    def to_h
      {
        category_id: @category&.id,
        category_name: @category&.name,
        confidence: @confidence.round(4),
        confidence_level: confidence_level,
        method: @method,
        patterns_used: @patterns_used,
        confidence_breakdown: @confidence_breakdown,
        alternative_categories: @alternative_categories.map do |alt|
          {
            category_id: alt[:category].id,
            category_name: alt[:category].name,
            confidence: alt[:confidence].round(4)
          }
        end,
        processing_time_ms: @processing_time_ms.round(3),
        cache_hits: @cache_hits,
        error: @error,
        metadata: @metadata,
        created_at: @created_at
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    # Comparison methods

    def ==(other)
      return false unless other.is_a?(CategorizationResult)

      @category == other.category &&
        @confidence == other.confidence &&
        @method == other.method &&
        @patterns_used == other.patterns_used
    end

    def eql?(other)
      self == other
    end

    def hash
      [ @category&.id, @confidence, @method, @patterns_used ].hash
    end

    # Display methods

    def inspect
      "#<CategorizationResult category=#{@category&.name} confidence=#{@confidence.round(3)} " \
        "method=#{@method} patterns=#{@patterns_used.size} time=#{@processing_time_ms.round(2)}ms>"
    end

    def to_s
      if successful?
        "#{@category.name} (#{(@confidence * 100).round(1)}% confidence)"
      elsif no_match?
        "No match found"
      elsif @error.present?
        "Error: #{@error}"
      else
        "Unknown result"
      end
    end

    private

    def self.pattern_description(pattern)
      case pattern
      when CategorizationPattern
        "#{pattern.pattern_type}:#{pattern.pattern_value}"
      when CompositePattern
        "composite:#{pattern.name}"
      when String
        pattern
      else
        pattern.to_s
      end
    end
  end
end
