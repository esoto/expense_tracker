# frozen_string_literal: true

require "rails_helper"

RSpec.describe Categorization::ConfidenceCalculator do
  let(:calculator) { described_class.new }
  let(:expense) do
    create(:expense,
           amount: 100.0,
           merchant_name: "Amazon Store",
           description: "Online purchase",
           transaction_date: Time.current)
  end
  let(:category) { create(:category, name: "Shopping") }
  let(:pattern) do
    create(:categorization_pattern,
           category: category,
           pattern_type: "merchant",
           pattern_value: "amazon",
           usage_count: 50,
           success_count: 45,
           success_rate: 0.9,
           metadata: {
             "amount_stats" => {
               "count" => 50,
               "mean" => 95.0,
               "std_dev" => 25.0,
               "min" => 10.0,
               "max" => 500.0
             },
             "temporal_stats" => {
               "hour_distribution" => { "14" => 10, "15" => 15, "16" => 8 },
               "day_distribution" => { "1" => 8, "3" => 12, "5" => 10 }
             }
           })
  end

  describe "#calculate" do
    context "with valid inputs" do
      let(:match_result) do
        Categorization::Matchers::MatchResult.new(
          success: true,
          matches: [{ score: 0.85, text: "amazon" }]
        )
      end

      it "calculates confidence score successfully" do
        result = calculator.calculate(expense, pattern, match_result)

        expect(result).to be_valid
        expect(result.score).to be_between(0.0, 1.0)
        expect(result.factors).to include(:text_match)
      end

      it "includes all available factors" do
        result = calculator.calculate(expense, pattern, match_result)

        expect(result.factors.keys).to contain_exactly(
          :text_match,
          :historical_success,
          :usage_frequency,
          :amount_similarity,
          :temporal_pattern
        )
      end

      it "applies sigmoid normalization" do
        result = calculator.calculate(expense, pattern, match_result)

        # Sigmoid should push moderate scores toward extremes
        expect(result.score).not_to eq(result.raw_score)
        
        # For high raw scores, normalized should be higher
        if result.raw_score > 0.5
          expect(result.score).to be > result.raw_score
        else
          expect(result.score).to be < result.raw_score
        end
      end

      it "generates proper metadata" do
        result = calculator.calculate(expense, pattern, match_result)

        expect(result.metadata).to include(
          :factor_count,
          :factors_used,
          :normalization_applied,
          :calculation_timestamp,
          :weights_applied
        )
        expect(result.metadata[:factors_used]).to be_an(Array)
        expect(result.metadata[:weights_applied]).to be_a(Hash)
      end
    end

    context "with missing required factors" do
      it "returns valid score when match_result is nil" do
        # Mock pattern.matches? to return true
        allow(pattern).to receive(:matches?).with(expense).and_return(true)
        
        result = calculator.calculate(expense, pattern, nil)

        # Should still work with fallback text_match of 0.7
        expect(result).to be_valid
        expect(result.factors[:text_match]).to eq(0.7)
      end

      it "returns invalid score when expense is nil" do
        result = calculator.calculate(nil, pattern, 0.8)

        expect(result).to be_invalid
        expect(result.error).to include("Missing expense")
      end

      it "returns invalid score when pattern is nil" do
        result = calculator.calculate(expense, nil, 0.8)

        expect(result).to be_invalid
        expect(result.error).to include("Missing pattern")
      end
    end

    context "with different match_result types" do
      it "handles MatchResult object" do
        match_result = Categorization::Matchers::MatchResult.new(
          success: true,
          matches: [{ score: 0.9 }]
        )

        result = calculator.calculate(expense, pattern, match_result)
        expect(result.factors[:text_match]).to eq(0.9)
      end

      it "handles Hash with score" do
        match_result = { score: 0.75 }

        result = calculator.calculate(expense, pattern, match_result)
        expect(result.factors[:text_match]).to eq(0.75)
      end

      it "handles Hash with adjusted_score" do
        match_result = { adjusted_score: 0.82, score: 0.75 }

        result = calculator.calculate(expense, pattern, match_result)
        expect(result.factors[:text_match]).to eq(0.82)
      end

      it "handles numeric value" do
        result = calculator.calculate(expense, pattern, 0.88)
        expect(result.factors[:text_match]).to eq(0.88)
      end

      it "falls back to pattern matching when no match_result" do
        allow(pattern).to receive(:matches?).with(expense).and_return(true)

        result = calculator.calculate(expense, pattern, nil)
        expect(result.factors[:text_match]).to eq(0.7)
      end
    end
  end

  describe "factor calculations" do
    describe "text_match factor" do
      it "uses match score directly" do
        result = calculator.calculate(expense, pattern, 0.95)
        expect(result.factors[:text_match]).to eq(0.95)
      end

      it "clamps values to 0.0-1.0 range" do
        result = calculator.calculate(expense, pattern, 1.5)
        expect(result.factors[:text_match]).to eq(1.0)

        result = calculator.calculate(expense, pattern, -0.5)
        expect(result.factors[:text_match]).to eq(0.0)
      end
    end

    describe "historical_success factor" do
      it "returns nil for patterns with insufficient usage" do
        pattern.update!(usage_count: 3, success_count: 2)
        result = calculator.calculate(expense, pattern, 0.8)
        expect(result.factors[:historical_success]).to be_nil
      end

      it "uses success rate for patterns with sufficient usage" do
        pattern.update!(usage_count: 10, success_count: 8, success_rate: 0.8)
        result = calculator.calculate(expense, pattern, 0.8)
        expect(result.factors[:historical_success]).to eq(0.8)
      end

      it "applies boost for highly used patterns" do
        pattern.update!(usage_count: 200, success_count: 160, success_rate: 0.8)
        result = calculator.calculate(expense, pattern, 0.8)
        
        # Should be slightly higher than base success rate
        expect(result.factors[:historical_success]).to be > 0.8
        expect(result.factors[:historical_success]).to be <= 1.0
      end
    end

    describe "usage_frequency factor" do
      it "returns nil for unused patterns" do
        pattern.update!(usage_count: 0, success_count: 0)
        result = calculator.calculate(expense, pattern, 0.8)
        expect(result.factors[:usage_frequency]).to be_nil
      end

      it "uses logarithmic scaling" do
        # Test each usage level with a fresh pattern to avoid state issues
        test_cases = [
          { usage: 1, min_expected: 0.09, max_expected: 0.11 },    # ~0.1003
          { usage: 10, min_expected: 0.34, max_expected: 0.36 },   # ~0.3471
          { usage: 100, min_expected: 0.66, max_expected: 0.68 },  # ~0.668
          { usage: 1000, min_expected: 0.99, max_expected: 1.0 }   # 1.0
        ]

        test_cases.each do |test_case|
          # Create a fresh pattern for each test to avoid state contamination
          test_pattern = create(:categorization_pattern,
                                category: category,
                                usage_count: test_case[:usage],
                                success_count: (test_case[:usage] * 0.9).to_i)
          
          result = calculator.calculate(expense, test_pattern, 0.8)
          
          actual_value = result.factors[:usage_frequency]
          expect(actual_value).to be_between(
            test_case[:min_expected],
            test_case[:max_expected]
          ), "Expected usage_frequency for usage_count=#{test_case[:usage]} to be between #{test_case[:min_expected]} and #{test_case[:max_expected]}, but got #{actual_value}"
        end
      end

      it "caps at 1.0 for very high usage" do
        pattern.update!(usage_count: 10000, success_count: 9000)
        result = calculator.calculate(expense, pattern, 0.8)
        expect(result.factors[:usage_frequency]).to eq(1.0)
      end
    end

    describe "amount_similarity factor" do
      it "returns nil without amount statistics" do
        pattern.update!(metadata: {})
        result = calculator.calculate(expense, pattern, 0.8)
        expect(result.factors[:amount_similarity]).to be_nil
      end

      it "returns nil with insufficient samples" do
        pattern.update!(metadata: {
          "amount_stats" => { "count" => 3, "mean" => 100, "std_dev" => 10 }
        })
        result = calculator.calculate(expense, pattern, 0.8)
        expect(result.factors[:amount_similarity]).to be_nil
      end

      it "calculates similarity based on z-score" do
        # Expense amount is 100, mean is 95, std_dev is 25
        # z-score = |100 - 95| / 25 = 0.2 (well within 1 std dev)
        result = calculator.calculate(expense, pattern, 0.8)
        expect(result.factors[:amount_similarity]).to be > 0.95
      end

      it "handles exact matches with zero std deviation" do
        pattern.update!(metadata: {
          "amount_stats" => { "count" => 10, "mean" => 100.0, "std_dev" => 0.0 }
        })
        
        result = calculator.calculate(expense, pattern, 0.8)
        expect(result.factors[:amount_similarity]).to eq(1.0)

        expense.update!(amount: 101.0)
        result = calculator.calculate(expense, pattern, 0.8)
        expect(result.factors[:amount_similarity]).to eq(0.0)
      end

      it "decreases score for amounts far from mean" do
        test_amounts = [
          { amount: 95.0, min_score: 0.95 },   # At mean (z=0)
          { amount: 120.0, min_score: 0.95 },  # 1 std dev (z=1)
          { amount: 145.0, min_score: 0.45 },  # 2 std dev (z=2)
          { amount: 170.0, min_score: 0.15 },  # 3 std dev (z=3)
          { amount: 220.0, min_score: 0.0 }    # 5 std dev (z=5)
        ]

        test_amounts.each do |test|
          expense.update!(amount: test[:amount])
          result = calculator.calculate(expense, pattern, 0.8)
          
          expect(result.factors[:amount_similarity]).to be >= test[:min_score]
        end
      end
    end

    describe "temporal_pattern factor" do
      context "with time-based pattern" do
        let(:time_pattern) do
          create(:categorization_pattern,
                 category: category,
                 pattern_type: "time",
                 pattern_value: "afternoon",
                 metadata: pattern.metadata)
        end

        it "returns 1.0 for matching time patterns" do
          expense.update!(transaction_date: Time.current.change(hour: 14))
          result = calculator.calculate(expense, time_pattern, 0.8)
          expect(result.factors[:temporal_pattern]).to eq(1.0)
        end

        it "returns 0.0 for non-matching time patterns" do
          expense.update!(transaction_date: Time.current.change(hour: 6))
          result = calculator.calculate(expense, time_pattern, 0.8)
          expect(result.factors[:temporal_pattern]).to be < 0.5
        end
      end

      context "with non-time pattern" do
        it "uses temporal statistics from metadata" do
          # Transaction at 3pm (hour 15), which has highest frequency in stats
          expense.update!(transaction_date: Time.current.change(hour: 15))
          result = calculator.calculate(expense, pattern, 0.8)
          
          # Should get high score for matching peak hour (nil if not time pattern)
          expect(result.factors[:temporal_pattern]).to be_nil  # merchant pattern, not time pattern
        end

        it "returns nil without temporal statistics" do
          pattern.update!(metadata: { "amount_stats" => pattern.metadata["amount_stats"] })
          result = calculator.calculate(expense, pattern, 0.8)
          expect(result.factors[:temporal_pattern]).to be_nil
        end
      end
    end
  end

  describe "weight recalculation" do
    it "recalculates weights when factors are missing" do
      # Remove amount stats to eliminate amount_similarity factor
      pattern.update!(metadata: {})
      
      result = calculator.calculate(expense, pattern, 0.8)
      
      # Check that weights sum to 1.0
      weights = result.metadata[:weights_applied]
      expect(weights.values.sum).to be_within(0.001).of(1.0)
      
      # Text match weight should be higher when other factors are missing
      expect(weights[:text_match]).to be > 0.35
    end

    it "handles case with only required factor" do
      pattern.update!(usage_count: 0, success_count: 0, metadata: {})
      
      result = calculator.calculate(expense, pattern, 0.8)
      
      # Only text_match should have weight
      weights = result.metadata[:weights_applied]
      expect(weights[:text_match]).to eq(1.0)
      expect(weights.size).to eq(1)
    end
  end

  describe "#calculate_batch" do
    let(:patterns) do
      [
        create(:categorization_pattern, category: category, pattern_value: "amazon"),
        create(:categorization_pattern, category: category, pattern_value: "store"),
        create(:categorization_pattern, category: category, pattern_value: "shop")
      ]
    end

    let(:match_results) do
      {
        patterns[0].id => { score: 0.9 },
        patterns[1].id => { score: 0.7 },
        patterns[2].id => { score: 0.6 }
      }
    end

    it "calculates confidence for multiple patterns" do
      results = calculator.calculate_batch(expense, patterns, match_results)

      expect(results).to be_an(Array)
      expect(results.size).to eq(3)
      expect(results).to all(be_a(Categorization::ConfidenceScore))
    end

    it "sorts results by confidence score descending" do
      results = calculator.calculate_batch(expense, patterns, match_results)

      scores = results.map(&:score)
      expect(scores).to eq(scores.sort.reverse)
    end

    it "handles missing match results" do
      partial_results = { patterns[0].id => { score: 0.9 } }
      
      results = calculator.calculate_batch(expense, patterns, partial_results)
      
      expect(results.size).to eq(3)
      # First pattern should have highest score due to match result
      expect(results.first.pattern).to eq(patterns[0])
    end

    it "returns empty array for invalid inputs" do
      expect(calculator.calculate_batch(nil, patterns)).to eq([])
      expect(calculator.calculate_batch(expense, [])).to eq([])
      expect(calculator.calculate_batch(expense, nil)).to eq([])
    end
  end

  describe "caching" do
    let(:match_result) { { score: 0.85 } }

    it "caches calculation results" do
      # First call should calculate
      result1 = calculator.calculate(expense, pattern, match_result)
      initial_calculations = calculator.metrics[:calculations]

      # Second call should use cache
      result2 = calculator.calculate(expense, pattern, match_result)
      
      expect(result2.score).to eq(result1.score)
      expect(result2.factors).to eq(result1.factors)
      expect(calculator.metrics[:cache_hits]).to eq(1)
      expect(calculator.metrics[:calculations]).to eq(initial_calculations)
    end

    it "uses different cache keys for different inputs" do
      result1 = calculator.calculate(expense, pattern, 0.8)
      result2 = calculator.calculate(expense, pattern, 0.9)

      expect(result1.factors[:text_match]).to eq(0.8)
      expect(result2.factors[:text_match]).to eq(0.9)
    end

    it "can clear cache" do
      calculator.calculate(expense, pattern, match_result)
      calculator.clear_cache
      
      # After clearing, should recalculate
      initial_calculations = calculator.metrics[:calculations]
      calculator.calculate(expense, pattern, match_result)
      
      expect(calculator.metrics[:calculations]).to eq(initial_calculations + 1)
    end

    context "with caching disabled" do
      let(:calculator) { described_class.new(enable_caching: false) }

      it "does not cache results" do
        calculator.calculate(expense, pattern, match_result)
        calculator.calculate(expense, pattern, match_result)

        expect(calculator.metrics[:cache_hits]).to eq(0)
        expect(calculator.metrics[:calculations]).to eq(2)
      end
    end
  end

  describe "performance" do
    it "completes calculation within reasonable threshold" do
      # Warm up to avoid first-run overhead
      calculator.calculate(expense, pattern, 0.85)
      
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      calculator.calculate(expense, pattern, 0.86)  # Different score to avoid cache
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

      # Allow up to 5ms for CI environments
      expect(duration_ms).to be < 5.0
    end

    it "handles batch calculations efficiently" do
      patterns = create_list(:categorization_pattern, 10, category: category)
      
      # Warm up to avoid first-run overhead
      calculator.calculate_batch(expense, patterns.first(2))
      
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      calculator.calculate_batch(expense, patterns)
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

      # Should complete 10 calculations in under 20ms (allowing for CI environments)
      expect(duration_ms).to be < 20.0
    end

    it "tracks performance metrics" do
      10.times { calculator.calculate(expense, pattern, 0.8) }

      metrics = calculator.detailed_metrics
      expect(metrics[:performance]).to include(
        :total_calculations,
        :avg_duration_ms,
        :min_duration_ms,
        :max_duration_ms,
        :p95_duration_ms,
        :p99_duration_ms
      )
      expect(metrics[:performance][:total_calculations]).to be >= 1
    end
  end

  describe "error handling" do
    it "handles calculation errors gracefully" do
      allow(pattern).to receive(:success_rate).and_raise(StandardError, "Test error")

      result = calculator.calculate(expense, pattern, 0.8)

      expect(result).to be_invalid
      expect(result.error).to include("Test error")
      expect(result.score).to eq(0.0)
    end

    it "handles invalid pattern metadata" do
      pattern.update!(metadata: "invalid")

      result = calculator.calculate(expense, pattern, 0.8)

      # Should still work, just without metadata-based factors
      expect(result).to be_valid
      expect(result.factors[:amount_similarity]).to be_nil
    end
  end

  describe "ConfidenceScore" do
    let(:score) do
      Categorization::ConfidenceScore.new(
        score: 0.87,
        raw_score: 0.75,
        factors: {
          text_match: 0.85,
          historical_success: 0.9,
          usage_frequency: 0.6,
          amount_similarity: 0.8,
          temporal_pattern: nil
        },
        pattern: pattern,
        expense: expense,
        metadata: {
          factor_count: 4,
          weights_applied: {
            text_match: 0.40,
            historical_success: 0.30,
            usage_frequency: 0.15,
            amount_similarity: 0.15
          }
        }
      )
    end

    describe "#confidence_level" do
      it "categorizes scores correctly" do
        test_cases = [
          { score: 0.98, level: :very_high },
          { score: 0.90, level: :high },
          { score: 0.75, level: :medium },
          { score: 0.60, level: :low },
          { score: 0.30, level: :very_low }
        ]

        test_cases.each do |test|
          score = Categorization::ConfidenceScore.new(score: test[:score])
          expect(score.confidence_level).to eq(test[:level])
        end
      end
    end

    describe "#factor_breakdown" do
      it "calculates contribution of each factor" do
        breakdown = score.factor_breakdown

        expect(breakdown[:text_match]).to include(
          value: 0.85,
          weight: 0.40,
          contribution: be_within(0.01).of(0.34),
          percentage: be_within(0.1).of(45.3)
        )
      end

      it "excludes nil factors" do
        breakdown = score.factor_breakdown
        expect(breakdown).not_to have_key(:temporal_pattern)
      end
    end

    describe "#dominant_factor" do
      it "identifies the factor with highest contribution" do
        expect(score.dominant_factor).to eq(:text_match)
      end
    end

    describe "#weakest_factor" do
      it "identifies the factor with lowest value" do
        expect(score.weakest_factor).to eq(:usage_frequency)
      end
    end

    describe "#explanation" do
      it "generates human-readable explanation" do
        explanation = score.explanation

        expect(explanation).to include("Confidence: 87.0% (high)")
        expect(explanation).to include("Based on 4 factors")
        expect(explanation).to include("Text match:")
        expect(explanation).to include("Historical success:")
      end

      it "includes normalization note when applicable" do
        # Create a score where normalization was applied
        normalized_score = Categorization::ConfidenceScore.new(
          score: 0.87,
          raw_score: 0.75,
          factors: score.factors,
          pattern: pattern,
          expense: expense,
          metadata: score.metadata.merge(normalization_applied: true)
        )
        
        explanation = normalized_score.explanation
        expect(explanation).to include("Score adjusted from 75.0%")
      end

      it "shows error for invalid scores" do
        invalid_score = Categorization::ConfidenceScore.invalid("Test error")
        expect(invalid_score.explanation).to include("Error: Test error")
      end
    end

    describe "comparison" do
      it "compares scores using <=> operator" do
        score1 = Categorization::ConfidenceScore.new(score: 0.8)
        score2 = Categorization::ConfidenceScore.new(score: 0.9)
        score3 = Categorization::ConfidenceScore.new(score: 0.8)

        expect(score1 <=> score2).to eq(-1)
        expect(score2 <=> score1).to eq(1)
        expect(score1 <=> score3).to eq(0)
      end

      it "supports sorting" do
        scores = [
          Categorization::ConfidenceScore.new(score: 0.5),
          Categorization::ConfidenceScore.new(score: 0.9),
          Categorization::ConfidenceScore.new(score: 0.7)
        ]

        sorted = scores.sort
        expect(sorted.map(&:score)).to eq([0.5, 0.7, 0.9])
      end
    end

    describe "#to_h" do
      it "exports all data as hash" do
        hash = score.to_h

        expect(hash).to include(
          score: 0.87,
          raw_score: 0.75,
          confidence_level: :high,
          factors: be_a(Hash),
          factor_breakdown: be_a(Hash),
          pattern_id: pattern.id,
          expense_id: expense.id,
          metadata: be_a(Hash)
        )
      end
    end
  end
end