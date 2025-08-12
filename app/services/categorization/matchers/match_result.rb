# frozen_string_literal: true

module Categorization
  module Matchers
    # Value object representing the result of a fuzzy matching operation
    # Provides structured access to match results with confidence scores
    class MatchResult
      attr_reader :matches, :query_text, :algorithm_used, :metadata

      def initialize(success:, matches: [], query_text: nil, algorithm_used: nil, metadata: {})
        @success = success
        @matches = matches
        @query_text = query_text
        @algorithm_used = algorithm_used
        @metadata = metadata
        @created_at = Time.current
      end

      # Factory methods

      def self.empty
        new(success: false, matches: [])
      end

      def self.timeout
        new(
          success: false,
          matches: [],
          metadata: { error: "Operation timed out", error_type: :timeout }
        )
      end

      def self.error(message)
        new(
          success: false,
          matches: [],
          metadata: { error: message, error_type: :error }
        )
      end

      # Query methods

      def success?
        @success
      end

      def failure?
        !@success
      end

      def empty?
        @matches.empty?
      end

      def present?
        @matches.present?
      end

      def timeout?
        @metadata[:error_type] == :timeout
      end

      def error?
        @metadata[:error_type] == :error
      end

      def error_message
        @metadata[:error]
      end

      # Access methods

      def best_match
        @matches.first
      end

      def best_score
        best_match&.dig(:score) || 0.0
      end

      def count
        @matches.size
      end

      def size
        count
      end

      # Filter methods

      def above_threshold(threshold)
        filtered_matches = @matches.select { |m| m[:score] >= threshold }

        self.class.new(
          success: @success,
          matches: filtered_matches,
          query_text: @query_text,
          algorithm_used: @algorithm_used,
          metadata: @metadata
        )
      end

      def top(n)
        self.class.new(
          success: @success,
          matches: @matches.first(n),
          query_text: @query_text,
          algorithm_used: @algorithm_used,
          metadata: @metadata
        )
      end

      # Confidence methods

      def high_confidence_matches(threshold = 0.85)
        above_threshold(threshold)
      end

      def medium_confidence_matches
        above_threshold(0.70).matches.reject { |m| m[:score] >= 0.85 }
      end

      def low_confidence_matches
        above_threshold(0.50).matches.reject { |m| m[:score] >= 0.70 }
      end

      def confidence_level
        return :none if empty?

        case best_score
        when 0.95..1.0
          :exact
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

      # Pattern-specific methods

      def best_pattern
        best_match&.dig(:pattern)
      end

      def best_category_id
        best_match&.dig(:category_id) || best_pattern&.category_id
      end

      def patterns
        @matches.filter_map { |m| m[:pattern] }
      end

      def category_ids
        @matches.filter_map { |m| m[:category_id] || m.dig(:pattern, :category_id) }.uniq
      end

      # Merchant-specific methods

      def best_merchant_id
        best_match&.dig(:id)
      end

      def merchant_names
        @matches.filter_map { |m| m[:display_name] || m[:text] }
      end

      # Transformation methods

      def map(&block)
        @matches.map(&block)
      end

      def select(&block)
        filtered_matches = @matches.select(&block)

        self.class.new(
          success: @success,
          matches: filtered_matches,
          query_text: @query_text,
          algorithm_used: @algorithm_used,
          metadata: @metadata
        )
      end

      def reject(&block)
        filtered_matches = @matches.reject(&block)

        self.class.new(
          success: @success,
          matches: filtered_matches,
          query_text: @query_text,
          algorithm_used: @algorithm_used,
          metadata: @metadata
        )
      end

      # Merge results from multiple matching operations
      def merge(other_result)
        return self unless other_result.is_a?(MatchResult)

        # Combine matches, removing duplicates based on ID
        combined_matches = (@matches + other_result.matches).uniq do |match|
          match[:id] || match[:text]
        end

        # Re-sort by score
        combined_matches.sort_by! { |m| -m[:score] }

        self.class.new(
          success: @success || other_result.success?,
          matches: combined_matches,
          query_text: @query_text,
          algorithm_used: [ @algorithm_used, other_result.algorithm_used ].flatten.compact.uniq,
          metadata: @metadata.merge(other_result.metadata)
        )
      end

      # Comparison operators

      def ==(other)
        return false unless other.is_a?(MatchResult)

        @success == other.success? &&
          @matches == other.matches &&
          @query_text == other.query_text
      end

      def eql?(other)
        self == other
      end

      def hash
        [ @success, @matches, @query_text ].hash
      end

      # Enumerable-like methods

      def each(&block)
        @matches.each(&block)
      end

      def first
        @matches.first
      end

      def last
        @matches.last
      end

      def [](index)
        @matches[index]
      end

      # Export methods

      def to_a
        @matches
      end

      def to_h
        {
          success: @success,
          matches: @matches,
          query_text: @query_text,
          algorithm_used: @algorithm_used,
          metadata: @metadata,
          confidence_level: confidence_level,
          best_score: best_score,
          match_count: count
        }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      # Debugging and inspection

      def inspect
        "#<MatchResult success=#{@success} matches=#{count} best_score=#{best_score.round(3)} confidence=#{confidence_level}>"
      end

      def to_s
        if success?
          if present?
            "MatchResult: #{count} match(es) found, best score: #{best_score.round(3)} (#{confidence_level})"
          else
            "MatchResult: No matches found"
          end
        else
          "MatchResult: Failed - #{error_message}"
        end
      end

      # Performance metrics

      def processing_time
        @metadata[:processing_time_ms]
      end

      def cache_hit?
        @metadata[:cache_hit] == true
      end

      # Detailed match information

      def match_details
        @matches.map do |match|
          {
            text: match[:text] || match[:name],
            score: match[:score],
            confidence: score_to_confidence_label(match[:score]),
            algorithm_scores: match[:algorithm_scores],
            adjusted_score: match[:adjusted_score],
            id: match[:id],
            metadata: match.except(:text, :score, :algorithm_scores, :adjusted_score, :id, :pattern, :object)
          }
        end
      end

      private

      def score_to_confidence_label(score)
        case score
        when 0.95..1.0
          "Exact Match"
        when 0.85...0.95
          "High Confidence"
        when 0.70...0.85
          "Medium Confidence"
        when 0.50...0.70
          "Low Confidence"
        else
          "Very Low Confidence"
        end
      end
    end
  end
end
