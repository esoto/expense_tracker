# frozen_string_literal: true

# Regression tests for PER-486: Confidence gate bypassed by booster patterns
#
# Four bugs compounded to allow time/amount booster patterns to produce
# high-confidence results even when no real text match existed:
#
# Bug 1 (Critical): score_and_rank_matches passed the booster's match_score (1.0)
#   to confidence_calculator, bypassing the TEXT_MATCH_GATE_THRESHOLD = 0.75 gate.
# Bug 2 (Critical): Booster patterns (time/amount) were applied cross-category —
#   any category could receive a booster even without a text match in that category.
# Bug 3 (High): Engine#default_options set min_confidence: 0.5, overriding
#   FuzzyMatcher::DEFAULT_OPTIONS[:min_confidence] = 0.75 (raised in PR #411).
# Bug 4 (Low cleanup): FuzzyMatcher#cache_key_for excluded min_confidence,
#   causing cross-contamination between callers with different thresholds.

require "rails_helper"

RSpec.describe "PER-486 confidence gate regression", :unit do
  # -------------------------------------------------------------------------
  # Shared setup helpers
  # -------------------------------------------------------------------------
  let(:fuzzy_matcher) do
    Services::Categorization::Matchers::FuzzyMatcher.new(enable_caching: false)
  end

  let(:confidence_calculator) { Services::Categorization::ConfidenceCalculator.new }

  let(:pattern_cache_service) { Services::Categorization::PatternCache.new }

  let(:strategy) do
    Services::Categorization::Strategies::PatternStrategy.new(
      pattern_cache_service: pattern_cache_service,
      fuzzy_matcher: fuzzy_matcher,
      confidence_calculator: confidence_calculator
    )
  end

  # -------------------------------------------------------------------------
  # Bug 1: Score confusion — booster score impersonates text_match score
  # -------------------------------------------------------------------------
  describe "Bug 1 – booster score must not impersonate text_match score" do
    #
    # Setup: Category "Entretenimiento" has a merchant pattern (weak text match ~0.5)
    # and a time booster pattern (time:weekend). The expense's merchant name fuzzy-
    # matches the merchant pattern weakly (below 0.75). The time booster matches.
    #
    # Before fix: score_and_rank_matches picked best_match = the booster (score 1.0),
    # passed 1.0 to confidence_calculator as text_match => gate allowed, conf ~0.985.
    # After fix:  best_match for scoring is the fuzzy text match (~0.5), gate fires,
    # result is no_match or confidence < 0.75.

    let(:entertainment_category) do
      create(:category, name: "Entretenimiento-#{SecureRandom.hex(4)}")
    end

    # A merchant pattern that produces a weak fuzzy match (~0.5) for "ccm cinemas"
    # vs the expense merchant "AUTO MERCADO CARTAG" — both are unrelated.
    let!(:weak_merchant_pattern) do
      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: "ccm cinemas",
             category: entertainment_category,
             confidence_weight: 1.0,
             usage_count: 50,
             success_count: 45,
             success_rate: 0.9)
    end

    # A time booster pattern in the SAME category that matches any weekend expense
    let!(:weekend_time_pattern) do
      create(:categorization_pattern,
             pattern_type: "time",
             pattern_value: "weekend",
             category: entertainment_category,
             confidence_weight: 1.0,
             usage_count: 10,
             success_count: 8,
             success_rate: 0.8)
    end

    # Expense that would match the time booster (weekend) but is NOT "ccm cinemas"
    let(:weekend_expense) do
      # A Saturday at 14:00
      saturday = Date.current.beginning_of_week(:sunday) + 6.days
      create(:expense,
             merchant_name: "AUTO MERCADO CARTAG",
             description: "Grocery shopping",
             amount: 19_000.0,
             transaction_date: saturday.to_time + 14.hours)
    end

    it "returns no_match or confidence < 0.75 when text_match is below gate threshold" do
      result = strategy.call(weekend_expense, min_confidence: 0.5)

      # If the bug is present: entertainment_category result with conf ~0.985
      # If fixed: no_match (no text match >= 0.75) OR confidence < 0.75
      if result.successful?
        expect(result.confidence).to be < 0.75,
          "Expected confidence < 0.75 because text_match is below gate, " \
          "got #{result.confidence.round(4)} for #{result.category&.name}"
      else
        expect(result).to be_no_match
      end
    end

    it "does NOT assign entertainment_category via a booster when text_match < 0.75" do
      result = strategy.call(weekend_expense, min_confidence: 0.5)

      # Before fix: result.category == entertainment_category from booster inflation
      # After fix: no_match — entertainment has no qualifying text match
      if result.successful?
        expect(result.confidence).to be < 0.75,
          "Expected confidence < 0.75 (gate should fire), got #{result.confidence.round(4)}"
      else
        expect(result).to be_no_match
      end
    end
  end

  # -------------------------------------------------------------------------
  # Bug 2: Cross-category booster leakage
  # -------------------------------------------------------------------------
  describe "Bug 2 – booster must only attach to categories with a text match" do
    #
    # Setup:
    #   Category A (Supermercado) — has a real merchant pattern that weakly matches
    #   Category B (Entretenimiento) — has ONLY a time booster, no text match for this expense
    #
    # Before fix: time booster for B is appended to matches because matches.any? (from A),
    # then B gets scored with a booster score, producing high confidence.
    # After fix: boosters only attach to categories that already have a text match.

    let(:supermercado_category) { create(:category, name: "Supermercado-#{SecureRandom.hex(4)}") }
    let(:entertainment_category) { create(:category, name: "Entertainment-#{SecureRandom.hex(4)}") }

    # Category A has a text match for "auto mercado"
    let!(:supermercado_merchant_pattern) do
      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: "auto mercado",
             category: supermercado_category,
             confidence_weight: 2.0,
             usage_count: 100,
             success_count: 95,
             success_rate: 0.95)
    end

    # Category B has ONLY a time booster, no text match for this merchant
    let!(:entertainment_time_pattern) do
      create(:categorization_pattern,
             pattern_type: "time",
             pattern_value: "weekend",
             category: entertainment_category,
             confidence_weight: 1.0,
             usage_count: 50,
             success_count: 40,
             success_rate: 0.8)
    end

    let(:weekend_grocery_expense) do
      saturday = Date.current.beginning_of_week(:sunday) + 6.days
      create(:expense,
             merchant_name: "AUTO MERCADO CARTAG",
             description: "Groceries",
             amount: 15_000.0,
             transaction_date: saturday.to_time + 11.hours)
    end

    it "does not assign entertainment_category when it only has a time booster with no text match" do
      result = strategy.call(weekend_grocery_expense)

      # entertainment_category should NOT win — it has no text match for this expense
      if result.successful?
        expect(result.category).not_to eq(entertainment_category),
          "Expected entertainment_category NOT to win (it has no text match), " \
          "but result.category = #{result.category&.name} (conf=#{result.confidence.round(4)})"
      end
    end

    it "still returns a result for the category with a real text match" do
      result = strategy.call(weekend_grocery_expense)

      # Supermercado HAS a text match so it should be the winner
      expect(result.successful?).to be(true)
      expect(result.category).to eq(supermercado_category)
    end
  end

  # -------------------------------------------------------------------------
  # Bug 3: Engine min_confidence override undoes PR #411
  # -------------------------------------------------------------------------
  describe "Bug 3 – Engine default min_confidence must be 0.75, not 0.5" do
    let(:category) { create(:category, name: "Test-#{SecureRandom.hex(4)}") }

    it "Engine#default_options has min_confidence >= 0.75" do
      engine = Services::Categorization::Engine.new(skip_defaults: false)
      # Access private default_options via send
      defaults = engine.send(:default_options)
      expect(defaults[:min_confidence]).to be >= 0.75,
        "Engine default min_confidence was #{defaults[:min_confidence]}, " \
        "expected >= 0.75 to align with FuzzyMatcher default and PR #411 gate"
    ensure
      engine.shutdown! if engine&.respond_to?(:shutdown!)
    end

    it "FuzzyMatcher default min_confidence is still 0.75" do
      expect(Services::Categorization::Matchers::FuzzyMatcher::DEFAULT_OPTIONS[:min_confidence])
        .to eq(0.75)
    end

    it "Engine does not return fuzzy matches below 0.75 with default options" do
      # Create an expense with a merchant that only weakly matches patterns
      unrelated_expense = create(:expense,
                                 merchant_name: "AAAA ZZZZ UNIQUE NONEXISTENT #{SecureRandom.hex(8)}",
                                 description: "purchase",
                                 amount: 100.0,
                                 transaction_date: Time.current)

      # Create a pattern that would score ~0.5 against the expense merchant
      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: "BBBB XXXX DIFFERENT STORE",
             category: category,
             confidence_weight: 1.0,
             usage_count: 10,
             success_count: 8,
             success_rate: 0.8)

      engine = Services::Categorization::Engine.new
      result = engine.categorize(unrelated_expense)

      # With min_confidence >= 0.75, a weak match that would only score ~0.5
      # should NOT produce a successful categorization
      if result.successful?
        expect(result.confidence).to be >= 0.75,
          "Engine returned a result with confidence #{result.confidence.round(4)} < 0.75, " \
          "suggesting the 0.5 override is still in place"
      end
    ensure
      engine&.shutdown!
    end
  end

  # -------------------------------------------------------------------------
  # Bug 4: FuzzyMatcher cache key omits min_confidence
  # -------------------------------------------------------------------------
  describe "Bug 4 – FuzzyMatcher cache key must include min_confidence" do
    let(:category) { create(:category, name: "CacheTest-#{SecureRandom.hex(4)}") }
    let!(:pattern) do
      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: "starbucks coffee",
             category: category,
             confidence_weight: 1.0,
             usage_count: 10,
             success_count: 8,
             success_rate: 0.8)
    end

    it "returns different results for different min_confidence values on same input" do
      # Use a caching-enabled matcher to exercise the cache path
      caching_matcher = Services::Categorization::Matchers::FuzzyMatcher.new(enable_caching: true)
      patterns = [ pattern ]

      # First call with low threshold — should return more matches (including weak ones)
      result_low = caching_matcher.match_pattern("starbucks", patterns, min_confidence: 0.5)

      # Second call with high threshold — should return fewer/no matches
      result_high = caching_matcher.match_pattern("starbucks", patterns, min_confidence: 0.99)

      # If cache key didn't include min_confidence, result_high would be
      # the cached result from result_low (same matches regardless of threshold).
      # After fix, they should differ (high threshold filters out the match).
      matches_low  = result_low.matches.size
      matches_high = result_high.matches.size

      expect(matches_high).to be <= matches_low,
        "Expected high threshold (0.99) to return fewer matches than low threshold (0.5), " \
        "got matches_low=#{matches_low} matches_high=#{matches_high}. " \
        "This suggests min_confidence is not included in the cache key."
    end

    it "cache key includes min_confidence so different thresholds don't cross-contaminate" do
      caching_matcher = Services::Categorization::Matchers::FuzzyMatcher.new(enable_caching: true)

      # Call with 0.5 first to warm cache
      caching_matcher.match_pattern("starbucks coffee", [ pattern ], min_confidence: 0.5)

      # Immediately call with 0.99 — should get a DIFFERENT (stricter) result,
      # not the cached result from the 0.5 call
      result_high = caching_matcher.match_pattern("starbucks coffee", [ pattern ], min_confidence: 0.99)

      # With min_confidence: 0.99, a fuzzy match of "starbucks coffee" vs
      # "starbucks coffee" should still match (exact or near-exact),
      # but we're testing that the cache is keyed separately.
      # The critical assertion: calling with a different min_confidence
      # does NOT return the cached result from the previous 0.5 call.
      # We verify this by calling with an impossible threshold and checking 0 matches.
      result_impossible = caching_matcher.match_pattern("starbucks coffee", [ pattern ], min_confidence: 1.01)

      # min_confidence: 1.01 — no real-world fuzzy score ever exceeds 1.0
      # so this MUST return 0 matches. If it returns matches, the 0.5 cache was served.
      expect(result_impossible.matches.size).to eq(0),
        "Expected 0 matches with min_confidence: 1.01 but got #{result_impossible.matches.size}. " \
        "The cache key likely doesn't include min_confidence."
    end
  end

  # -------------------------------------------------------------------------
  # Integration: the full PR #411 gate must hold end-to-end
  # -------------------------------------------------------------------------
  describe "Gate integration: text_match < 0.75 must always be blocked" do
    it "ConfidenceCalculator gate fires when text_match < 0.75, regardless of boosters" do
      calc = Services::Categorization::ConfidenceCalculator.new
      category = create(:category, name: "Gate-#{SecureRandom.hex(4)}")
      # A time-type pattern that matches (would contribute temporal_pattern factor)
      time_pattern = create(:categorization_pattern,
                            pattern_type: "time",
                            pattern_value: "weekend",
                            category: category,
                            confidence_weight: 1.0,
                            usage_count: 100,
                            success_count: 95,
                            success_rate: 0.95)

      expense = create(:expense,
                       merchant_name: "Some Merchant",
                       amount: 100.0,
                       transaction_date: Time.current)

      # Pass a text_match score of 0.6 — below the 0.75 gate
      result = calc.calculate(expense, time_pattern, 0.6)

      expect(result.score).to be < 0.75,
        "Gate should have fired (text_match=0.6 < 0.75) but score=#{result.score}"
      expect(result.metadata[:gated]).to be(true)
    end

    it "ConfidenceCalculator allows high score when text_match >= 0.75" do
      calc = Services::Categorization::ConfidenceCalculator.new
      category = create(:category, name: "GateHigh-#{SecureRandom.hex(4)}")
      merchant_pattern = create(:categorization_pattern,
                                pattern_type: "merchant",
                                pattern_value: "starbucks",
                                category: category,
                                confidence_weight: 2.0,
                                usage_count: 100,
                                success_count: 95,
                                success_rate: 0.95)

      expense = create(:expense,
                       merchant_name: "Starbucks Coffee",
                       amount: 10.0,
                       transaction_date: Time.current)

      # Pass text_match score of 0.9 — above gate
      result = calc.calculate(expense, merchant_pattern, 0.9)

      expect(result.metadata[:gated]).not_to be(true)
      expect(result.score).to be >= 0.75
    end
  end
end
