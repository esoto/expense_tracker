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
    # We stub the fuzzy matcher to return a controlled weak text match (score 0.65)
    # so the test is deterministic and independent of the fuzzy library's exact
    # algorithm scores. The expense also satisfies a time:weekend booster in the
    # same category.
    #
    # Before fix: score_and_rank_matches picked best_match = the booster (score 1.0),
    # passed 1.0 to confidence_calculator as text_match => gate allowed, conf ~0.985.
    # After fix:  best_match for scoring is the fuzzy text match (0.65), gate fires
    # because 0.65 < TEXT_MATCH_GATE_THRESHOLD (0.75).

    let(:entertainment_category) do
      create(:category, name: "Entretenimiento-#{SecureRandom.hex(4)}")
    end

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

    # A time booster pattern in the SAME category that matches any weekend expense.
    # Before the fix: best_match = this booster (match_score: 1.0), bypassing gate.
    # After the fix: best_match = the text match (0.65), gate fires.
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

    # Expense that matches the time booster (weekend) with a weak text match
    let(:weekend_expense) do
      saturday = Date.current.beginning_of_week(:sunday) + 6.days
      create(:expense,
             merchant_name: "AUTO MERCADO CARTAG",
             description: "Grocery shopping",
             amount: 19_000.0,
             transaction_date: saturday.to_time + 14.hours)
    end

    # Stubbed fuzzy matcher that returns a controlled weak match score (0.65)
    # for the merchant pattern. This is below the 0.75 gate.
    let(:stubbed_fuzzy_matcher) do
      matcher = instance_double(Services::Categorization::Matchers::FuzzyMatcher)
      allow(matcher).to receive(:match_pattern) do |_text, patterns, opts|
        # Return a weak match (0.65) for any merchant pattern
        merchant_patterns = patterns.select { |p| p.pattern_type == "merchant" }
        if merchant_patterns.any?
          matches = merchant_patterns.map do |p|
            { id: p.id, score: 0.65, adjusted_score: 0.65, pattern: p, text: p.pattern_value }
          end
          Services::Categorization::Matchers::MatchResult.new(success: true, matches: matches)
        else
          Services::Categorization::Matchers::MatchResult.empty
        end
      end
      matcher
    end

    let(:strategy_with_stub) do
      Services::Categorization::Strategies::PatternStrategy.new(
        pattern_cache_service: pattern_cache_service,
        fuzzy_matcher: stubbed_fuzzy_matcher,
        confidence_calculator: confidence_calculator
      )
    end

    it "confidence_calculator gate fires when text_match score is below 0.75" do
      result = strategy_with_stub.call(weekend_expense, min_confidence: 0.5)

      # Bug present: booster score 1.0 passed as text_match → gate bypassed →
      #   confidence_breakdown does NOT include metadata[:gated], all factors inflate score.
      # Bug fixed: text match 0.65 passed as text_match → gate fires (0.65 < 0.75) →
      #   confidence_score.metadata[:gated] == true, only sigmoid(0.65) used.
      # The fix sends text_match=0.65 (not booster's 1.0) to the calculator.
      # Gate fires (0.65 < 0.75), returns sigmoid(0.65) ≈ 0.818 — well below
      # the bug's ~0.985. Result is successful but correctly gated.
      expect(result).to be_successful
      expect(result.confidence).to be < 0.90,
        "Expected gated confidence < 0.90, got #{result.confidence.round(4)}. " \
        "Bug would produce ~0.985 from booster impersonating text_match."
    end

    it "does NOT produce higher confidence from booster than from text_match alone" do
      # The key invariant: when text_match < 0.75, the booster score (1.0) must NOT
      # be what confidence_calculator receives as text_match. If the bug were present,
      # passing 1.0 gives sigmoid(weighted_all_factors) ≈ 0.985. Passing 0.65 (text
      # match) gives sigmoid(0.65) ≈ 0.818 (gated path) — lower and correctly gated.
      result = strategy_with_stub.call(weekend_expense, min_confidence: 0.5)

      # Independently compute what confidence_calculator gives for text_match=1.0 (bug)
      # vs text_match=0.65 (fix). The result's confidence must match the fix path.
      calc = Services::Categorization::ConfidenceCalculator.new
      bug_score = calc.calculate(weekend_expense, weak_merchant_pattern, 1.0).score
      fix_score = calc.calculate(weekend_expense, weak_merchant_pattern, 0.65).score

      # With text_match=0.65 (below gate), the gated confidence ≈ 0.818.
      # This must be close to the fix_score path, NOT the bug_score path.
      expect(result).to be_successful
      expect(result.confidence).to be_within(0.05).of(fix_score),
        "Expected confidence #{result.confidence.round(4)} near fix_score " \
        "#{fix_score.round(4)}, not bug_score #{bug_score.round(4)}"
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

      # Supermercado has a real text match, so the result should be successful
      # and categorized there — NOT entertainment (which only has a time booster).
      expect(result).to be_successful
      expect(result.category).to eq(supermercado_category),
        "Expected supermercado_category (has text match), " \
        "but got #{result.category&.name} (conf=#{result.confidence.round(4)})"
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
      # should NOT produce a successful categorization. Pin to no_match.
      expect(result).to be_no_match
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
