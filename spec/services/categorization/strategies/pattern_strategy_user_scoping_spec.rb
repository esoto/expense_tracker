# frozen_string_literal: true

require "rails_helper"

# PR 9 integration: verifies the pattern matcher only considers patterns
# on categories the expense's owner can see. Lives as a focused spec so
# the main pattern_strategy_spec's existing fixtures don't interfere.
RSpec.describe Services::Categorization::Strategies::PatternStrategy,
               :unit,
               type: :service do
  let(:pattern_cache_service) { Services::Categorization::PatternCache.new }
  let(:fuzzy_matcher)         { Services::Categorization::Matchers::FuzzyMatcher.new }
  let(:confidence_calculator) { Services::Categorization::ConfidenceCalculator.new }
  let(:strategy) do
    described_class.new(
      pattern_cache_service: pattern_cache_service,
      fuzzy_matcher: fuzzy_matcher,
      confidence_calculator: confidence_calculator
    )
  end

  describe "user-scoped pattern matching" do
    let(:alice) { create(:user, email: "scoping_alice@example.com") }
    let(:bob)   { create(:user, email: "scoping_bob@example.com") }

    let(:alice_personal_cat) {
      create(:category, name: "Alice Personal Food #{SecureRandom.hex(3)}", user: alice)
    }
    let(:bob_personal_cat) {
      create(:category, name: "Bob Personal Food #{SecureRandom.hex(3)}", user: bob)
    }

    # A merchant pattern on Alice's personal category. Bob's expenses
    # must never match this — that's the isolation invariant.
    before do
      CategorizationPattern.create!(
        category: alice_personal_cat,
        pattern_type: "merchant",
        pattern_value: "secretstore",
        confidence_weight: 3.0,
        user_created: true
      )
      CategorizationPattern.create!(
        category: bob_personal_cat,
        pattern_type: "merchant",
        pattern_value: "secretstore",
        confidence_weight: 3.0,
        user_created: true
      )
    end

    let(:alice_email_account) { create(:email_account, user: alice) }
    let(:bob_email_account)   { create(:email_account, user: bob) }

    let(:alice_expense) do
      create(:expense,
             user: alice,
             email_account: alice_email_account,
             merchant_name: "SecretStore Downtown",
             description: "purchase",
             amount: 15.00,
             transaction_date: Time.current)
    end

    let(:bob_expense) do
      create(:expense,
             user: bob,
             email_account: bob_email_account,
             merchant_name: "SecretStore Downtown",
             description: "purchase",
             amount: 15.00,
             transaction_date: Time.current)
    end

    it "categorizes Alice's expense into Alice's personal category" do
      result = strategy.call(alice_expense, min_confidence: 0.1, check_user_preferences: false)
      expect(result.successful?).to be true
      expect(result.category&.id).to eq(alice_personal_cat.id)
    end

    it "does NOT route Bob's identical-looking expense to Alice's category" do
      result = strategy.call(bob_expense, min_confidence: 0.1, check_user_preferences: false)
      if result.successful?
        expect(result.category&.id).not_to eq(alice_personal_cat.id)
        expect(result.category&.id).to eq(bob_personal_cat.id)
      end
    end
  end
end
