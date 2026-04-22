# frozen_string_literal: true

require "rails_helper"

# PR 9 integration tests for the *bypass paths* Codex flagged:
#   - EnhancedCategorizationService (API surface)
#   - BulkCategorizationService#find_best_category_match
#   - UserCategoryPreference lookup in PatternStrategy
#
# Each test sets up two users with identical spending "signals" and
# verifies that one user's personal category/pattern/preference never
# leaks into the other user's categorization result.
RSpec.describe "PR 9 — user-scoped categorization bypass fixes", :unit, type: :service do
  let(:alice) { create(:user, email: "pr9_a@example.com") }
  let(:bob)   { create(:user, email: "pr9_b@example.com") }

  let(:alice_account) { create(:email_account, user: alice) }
  let(:bob_account)   { create(:email_account, user: bob) }

  let(:alice_private) {
    create(:category, name: "Alice Private #{SecureRandom.hex(3)}", user: alice)
  }
  let(:bob_private) {
    create(:category, name: "Bob Private #{SecureRandom.hex(3)}", user: bob)
  }

  describe "EnhancedCategorizationService" do
    let(:service) { Services::Categorization::EnhancedCategorizationService.new }

    before do
      CategorizationPattern.create!(
        category: alice_private,
        pattern_type: "merchant",
        pattern_value: "CrossUserMerchant",
        confidence_weight: 4.0,
        user_created: true
      )
    end

    it "does not surface Alice's personal category as a suggestion for Bob's expense" do
      bob_expense = create(:expense,
                           user: bob,
                           email_account: bob_account,
                           merchant_name: "CrossUserMerchant Branch",
                           description: "purchase",
                           amount: 10.0,
                           transaction_date: Time.current)

      suggestions = service.suggest_categories(bob_expense, 5)
      suggested_categories = suggestions.map { |s| s[:category] }
      expect(suggested_categories).not_to include(alice_private)
    end
  end

  describe "BulkCategorizationService#find_best_category_match" do
    before do
      CategorizationPattern.create!(
        category: alice_private,
        pattern_type: "merchant",
        pattern_value: "BulkCrossUserMerchant",
        confidence_weight: 4.0,
        user_created: true
      )
    end

    it "does not route Bob's expense into Alice's personal category" do
      bob_expense = create(:expense,
                           user: bob,
                           email_account: bob_account,
                           merchant_name: "BulkCrossUserMerchant Store",
                           description: "purchase",
                           amount: 20.0,
                           transaction_date: Time.current)

      bulk = Services::Categorization::BulkCategorizationService.new(user: bob)
      match = bulk.send(:find_best_category_match, bob_expense)

      if match
        expect(match[:category]).not_to eq(alice_private)
      end
    end
  end

  describe "PatternStrategy user-preference isolation" do
    let(:strategy) do
      Services::Categorization::Strategies::PatternStrategy.new(
        pattern_cache_service: Services::Categorization::PatternCache.new,
        fuzzy_matcher: Services::Categorization::Matchers::FuzzyMatcher.new,
        confidence_calculator: Services::Categorization::ConfidenceCalculator.new
      )
    end

    before do
      # Alice's preference for "SharedMerchant" maps to her private category.
      create(:user_category_preference,
             email_account: alice_account,
             user: alice,
             category: alice_private,
             context_type: "merchant",
             context_value: "sharedmerchant",
             preference_weight: 9.0,
             usage_count: 50)
    end

    it "Alice's merchant preference does not resolve when Bob looks up the same merchant" do
      bob_expense = create(:expense,
                           user: bob,
                           email_account: bob_account,
                           merchant_name: "SharedMerchant",
                           description: "purchase",
                           amount: 10.0,
                           transaction_date: Time.current)

      result = strategy.call(bob_expense, min_confidence: 0.1)
      # Bob has no personal preference for this merchant, so the user
      # preference path MUST NOT return Alice's category.
      if result.successful?
        expect(result.category).not_to eq(alice_private)
      end
    end

    it "the preference still resolves for Alice's own expense" do
      alice_expense = create(:expense,
                             user: alice,
                             email_account: alice_account,
                             merchant_name: "SharedMerchant",
                             description: "purchase",
                             amount: 10.0,
                             transaction_date: Time.current)

      result = strategy.call(alice_expense, min_confidence: 0.1)
      expect(result).to be_successful
      expect(result.category).to eq(alice_private)
    end
  end
end
