# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Matchers::MatchResult, performance: true do
  let(:matches) do
    [
      { id: 1, text: "Starbucks", score: 0.95 },
      { id: 2, text: "Coffee Shop", score: 0.75 },
      { id: 3, text: "Cafe", score: 0.60 }
    ]
  end

  let(:result) do
    described_class.new(
      success: true,
      matches: matches,
      query_text: "starbucks coffee",
      algorithm_used: [ :jaro_winkler, :trigram ]
    )
  end

  describe "factory methods", performance: true do
    describe ".empty", performance: true do
      it "creates an empty result" do
        result = described_class.empty

        expect(result).not_to be_success
        expect(result).to be_empty
        expect(result.matches).to eq([])
      end
    end

    describe ".timeout", performance: true do
      it "creates a timeout result" do
        result = described_class.timeout

        expect(result).not_to be_success
        expect(result).to be_timeout
        expect(result.error_message).to eq("Operation timed out")
      end
    end

    describe ".error", performance: true do
      it "creates an error result" do
        result = described_class.error("Something went wrong")

        expect(result).not_to be_success
        expect(result).to be_error
        expect(result.error_message).to eq("Something went wrong")
      end
    end
  end

  describe "query methods", performance: true do
    describe "#success?", performance: true do
      it "returns true for successful results" do
        expect(result).to be_success
      end

      it "returns false for failed results" do
        failed = described_class.empty
        expect(failed).not_to be_success
      end
    end

    describe "#failure?", performance: true do
      it "returns opposite of success?" do
        expect(result.failure?).to eq(!result.success?)
      end
    end

    describe "#empty?", performance: true do
      it "returns true when no matches" do
        empty_result = described_class.new(success: true, matches: [])
        expect(empty_result).to be_empty
      end

      it "returns false when matches exist" do
        expect(result).not_to be_empty
      end
    end

    describe "#present?", performance: true do
      it "returns true when matches exist" do
        expect(result).to be_present
      end

      it "returns false when no matches" do
        empty_result = described_class.new(success: true, matches: [])
        expect(empty_result).not_to be_present
      end
    end
  end

  describe "access methods", performance: true do
    describe "#best_match", performance: true do
      it "returns the first match" do
        expect(result.best_match).to eq(matches.first)
      end

      it "returns nil for empty results" do
        empty_result = described_class.empty
        expect(empty_result.best_match).to be_nil
      end
    end

    describe "#best_score", performance: true do
      it "returns the highest score" do
        expect(result.best_score).to eq(0.95)
      end

      it "returns 0.0 for empty results" do
        empty_result = described_class.empty
        expect(empty_result.best_score).to eq(0.0)
      end
    end

    describe "#count and #size", performance: true do
      it "returns the number of matches" do
        expect(result.count).to eq(3)
        expect(result.size).to eq(3)
      end
    end
  end

  describe "filter methods", performance: true do
    describe "#above_threshold", performance: true do
      it "filters matches above threshold" do
        filtered = result.above_threshold(0.70)

        expect(filtered.count).to eq(2)
        expect(filtered.matches.all? { |m| m[:score] >= 0.70 }).to be true
      end

      it "preserves metadata" do
        filtered = result.above_threshold(0.70)

        expect(filtered.query_text).to eq(result.query_text)
        expect(filtered.algorithm_used).to eq(result.algorithm_used)
      end
    end

    describe "#top", performance: true do
      it "returns top N matches" do
        top_2 = result.top(2)

        expect(top_2.count).to eq(2)
        expect(top_2.matches).to eq(matches.first(2))
      end

      it "handles N greater than match count" do
        top_10 = result.top(10)

        expect(top_10.count).to eq(3)
      end
    end
  end

  describe "confidence methods", performance: true do
    describe "#high_confidence_matches", performance: true do
      it "returns matches with score >= 0.85" do
        high = result.high_confidence_matches

        expect(high.matches.all? { |m| m[:score] >= 0.85 }).to be true
      end

      it "accepts custom threshold" do
        high = result.high_confidence_matches(0.90)

        expect(high.matches.all? { |m| m[:score] >= 0.90 }).to be true
      end
    end

    describe "#medium_confidence_matches", performance: true do
      it "returns matches with 0.70 <= score < 0.85" do
        medium = result.medium_confidence_matches

        expect(medium.all? { |m| m[:score] >= 0.70 && m[:score] < 0.85 }).to be true
      end
    end

    describe "#low_confidence_matches", performance: true do
      it "returns matches with 0.50 <= score < 0.70" do
        low = result.low_confidence_matches

        expect(low.all? { |m| m[:score] >= 0.50 && m[:score] < 0.70 }).to be true
      end
    end

    describe "#confidence_level", performance: true do
      it "returns :exact for scores >= 0.95" do
        expect(result.confidence_level).to eq(:exact)
      end

      it "returns :high for scores 0.85-0.95" do
        result = described_class.new(
          success: true,
          matches: [ { score: 0.88 } ]
        )
        expect(result.confidence_level).to eq(:high)
      end

      it "returns :medium for scores 0.70-0.85" do
        result = described_class.new(
          success: true,
          matches: [ { score: 0.75 } ]
        )
        expect(result.confidence_level).to eq(:medium)
      end

      it "returns :low for scores 0.50-0.70" do
        result = described_class.new(
          success: true,
          matches: [ { score: 0.55 } ]
        )
        expect(result.confidence_level).to eq(:low)
      end

      it "returns :very_low for scores < 0.50" do
        result = described_class.new(
          success: true,
          matches: [ { score: 0.40 } ]
        )
        expect(result.confidence_level).to eq(:very_low)
      end

      it "returns :none for empty results" do
        empty_result = described_class.empty
        expect(empty_result.confidence_level).to eq(:none)
      end
    end
  end

  describe "pattern-specific methods", performance: true do
    let(:pattern) { create(:categorization_pattern) }
    let(:pattern_matches) do
      [
        { id: 1, score: 0.9, pattern: pattern, category_id: pattern.category_id }
      ]
    end

    let(:pattern_result) do
      described_class.new(success: true, matches: pattern_matches)
    end

    describe "#best_pattern", performance: true do
      it "returns the pattern from best match" do
        expect(pattern_result.best_pattern).to eq(pattern)
      end
    end

    describe "#best_category_id", performance: true do
      it "returns category_id from best match" do
        expect(pattern_result.best_category_id).to eq(pattern.category_id)
      end
    end

    describe "#patterns", performance: true do
      it "returns all patterns from matches" do
        expect(pattern_result.patterns).to eq([ pattern ])
      end
    end

    describe "#category_ids", performance: true do
      it "returns unique category IDs" do
        expect(pattern_result.category_ids).to eq([ pattern.category_id ])
      end
    end
  end

  describe "transformation methods", performance: true do
    describe "#map", performance: true do
      it "maps over matches" do
        scores = result.map { |m| m[:score] }
        expect(scores).to eq([ 0.95, 0.75, 0.60 ])
      end
    end

    describe "#select", performance: true do
      it "filters matches and returns new MatchResult" do
        filtered = result.select { |m| m[:score] > 0.70 }

        expect(filtered).to be_a(described_class)
        expect(filtered.count).to eq(2)
      end
    end

    describe "#reject", performance: true do
      it "rejects matches and returns new MatchResult" do
        filtered = result.reject { |m| m[:score] < 0.70 }

        expect(filtered).to be_a(described_class)
        expect(filtered.count).to eq(2)
      end
    end
  end

  describe "#merge", performance: true do
    let(:other_matches) do
      [
        { id: 4, text: "Tea Shop", score: 0.85 },
        { id: 1, text: "Starbucks", score: 0.90 } # Duplicate ID
      ]
    end

    let(:other_result) do
      described_class.new(
        success: true,
        matches: other_matches,
        algorithm_used: [ :levenshtein ]
      )
    end

    it "combines matches from two results" do
      merged = result.merge(other_result)

      expect(merged.count).to eq(4) # 3 original + 1 new (duplicate removed)
    end

    it "removes duplicates based on ID" do
      merged = result.merge(other_result)

      ids = merged.matches.map { |m| m[:id] }
      expect(ids).to eq(ids.uniq)
    end

    it "re-sorts by score" do
      merged = result.merge(other_result)

      scores = merged.matches.map { |m| m[:score] }
      expect(scores).to eq(scores.sort.reverse)
    end

    it "combines algorithm information" do
      merged = result.merge(other_result)

      expect(merged.algorithm_used).to include(:jaro_winkler, :trigram, :levenshtein)
    end
  end

  describe "enumerable-like methods", performance: true do
    describe "#each", performance: true do
      it "iterates over matches" do
        texts = []
        result.each { |m| texts << m[:text] }

        expect(texts).to eq([ "Starbucks", "Coffee Shop", "Cafe" ])
      end
    end

    describe "#first", performance: true do
      it "returns first match" do
        expect(result.first).to eq(matches.first)
      end
    end

    describe "#last", performance: true do
      it "returns last match" do
        expect(result.last).to eq(matches.last)
      end
    end

    describe "#[]", performance: true do
      it "accesses matches by index" do
        expect(result[0]).to eq(matches[0])
        expect(result[1]).to eq(matches[1])
        expect(result[-1]).to eq(matches.last)
      end
    end
  end

  describe "export methods", performance: true do
    describe "#to_a", performance: true do
      it "returns matches array" do
        expect(result.to_a).to eq(matches)
      end
    end

    describe "#to_h", performance: true do
      it "returns hash representation" do
        hash = result.to_h

        expect(hash).to include(
          success: true,
          matches: matches,
          query_text: "starbucks coffee",
          algorithm_used: [ :jaro_winkler, :trigram ],
          confidence_level: :exact,
          best_score: 0.95,
          match_count: 3
        )
      end
    end

    describe "#to_json", performance: true do
      it "returns JSON representation" do
        json = result.to_json
        parsed = JSON.parse(json)

        expect(parsed["success"]).to be true
        expect(parsed["match_count"]).to eq(3)
      end
    end
  end

  describe "comparison operators", performance: true do
    describe "#==", performance: true do
      it "returns true for equal results" do
        other = described_class.new(
          success: true,
          matches: matches,
          query_text: "starbucks coffee"
        )

        expect(result == other).to be true
      end

      it "returns false for different results" do
        other = described_class.new(
          success: true,
          matches: [ { score: 0.5 } ],
          query_text: "different"
        )

        expect(result == other).to be false
      end
    end
  end

  describe "#match_details", performance: true do
    it "returns detailed match information" do
      details = result.match_details

      expect(details).to be_an(Array)
      expect(details.first).to include(
        text: "Starbucks",
        score: 0.95,
        confidence: "Exact Match",
        id: 1
      )
    end
  end

  describe "debugging methods", performance: true do
    describe "#inspect", performance: true do
      it "returns concise representation" do
        expect(result.inspect).to include("MatchResult")
        expect(result.inspect).to include("success=true")
        expect(result.inspect).to include("matches=3")
      end
    end

    describe "#to_s", performance: true do
      it "returns human-readable string for success" do
        expect(result.to_s).to include("3 match(es) found")
        expect(result.to_s).to include("best score: 0.95")
      end

      it "returns error message for failure" do
        error_result = described_class.error("Database error")
        expect(error_result.to_s).to include("Failed - Database error")
      end

      it "indicates no matches found" do
        empty_result = described_class.new(success: true, matches: [])
        expect(empty_result.to_s).to include("No matches found")
      end
    end
  end

  describe "performance metrics", performance: true do
    let(:result_with_metrics) do
      described_class.new(
        success: true,
        matches: matches,
        metadata: {
          processing_time_ms: 5.2,
          cache_hit: true
        }
      )
    end

    describe "#processing_time", performance: true do
      it "returns processing time from metadata" do
        expect(result_with_metrics.processing_time).to eq(5.2)
      end
    end

    describe "#cache_hit?", performance: true do
      it "returns true when cache was hit" do
        expect(result_with_metrics).to be_cache_hit
      end

      it "returns false when cache was not hit" do
        expect(result).not_to be_cache_hit
      end
    end
  end
end
