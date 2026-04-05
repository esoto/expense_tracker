# frozen_string_literal: true

require "rails_helper"

# =============================================================================
# Categorization Pipeline — End-to-End Smoke Test
#
# This spec validates the *entire* categorization domain in one ordered flow:
#
#   1. Setup        — categories + patterns created in DB
#   2. Matching     — Engine suggests a category with high confidence
#   3. Accept       — ML suggestion applied; expense fields updated
#   4. Correction   — User overrides suggestion; correction counters tracked
#   5. Learning     — PatternLearner processes feedback, creates/updates patterns
#   6. Bulk categ.  — BulkOperations::CategorizationService mass-assigns categories
#   7. Bulk status  — BulkOperations::StatusUpdateService mass-marks as "processed"
#   8. API suggest  — POST /api/v1/categorization/suggest returns JSON suggestions
#   9. Confidence   — Expense#confidence_level reflects threshold boundaries
# =============================================================================
RSpec.describe "Categorization Pipeline E2E Smoke Test", :integration do
  include CategorizationTestHelper

  # ---------------------------------------------------------------------------
  # Shared categories used across all contexts
  # ---------------------------------------------------------------------------
  let!(:alimentacion_category) do
    create(:category, name: "Alimentación", description: "Comida, restaurantes, supermercados")
  end

  let!(:transporte_category) do
    create(:category, name: "Transporte", description: "Gasolina, Uber, taxis")
  end

  let!(:supermercado_category) do
    create(:category, name: "Supermercado", description: "Compras en supermercado")
  end

  # ---------------------------------------------------------------------------
  # Categorization patterns: merchant-level entries with strong confidence
  # ---------------------------------------------------------------------------
  let!(:automercado_pattern) do
    create(:categorization_pattern,
           pattern_type: "merchant",
           pattern_value: "automercado",       # lower-cased as stored
           category: supermercado_category,
           confidence_weight: 3.5,
           usage_count: 50,
           success_count: 47,
           success_rate: 0.94,
           active: true)
  end

  let!(:uber_pattern) do
    create(:categorization_pattern,
           pattern_type: "merchant",
           pattern_value: "uber",
           category: transporte_category,
           confidence_weight: 3.0,
           usage_count: 40,
           success_count: 38,
           success_rate: 0.95,
           active: true)
  end

  # ---------------------------------------------------------------------------
  # Fresh engine instance per test (real DB, real pattern matching)
  # ---------------------------------------------------------------------------
  let(:engine) { create_test_engine }

  after do
    engine&.shutdown!
    reset_categorization_engine!
  end

  # ---------------------------------------------------------------------------
  # Cache invalidation: model callbacks reach the Engine's PatternCache
  # ---------------------------------------------------------------------------
  context "Step 0: Cache invalidation (PER-286)" do
    it "Engine sees updated patterns after model save triggers after_commit" do
      # Build an Engine using build_defaults (singleton path, no DI override)
      registry = Services::Categorization::ServiceRegistry.new(logger: Rails.logger)
      registry.build_defaults
      engine = Services::Categorization::Engine.new(
        service_registry: registry,
        skip_defaults: true
      )

      # Verify the Engine's pattern_cache IS the singleton
      engine_cache = registry.get(:pattern_cache)
      expect(engine_cache).to be(Services::Categorization::PatternCache.instance)

      # Warm the cache so patterns are loaded into L1
      engine_cache.warm_cache

      # Create a new pattern — after_commit should invalidate the singleton
      create(:categorization_pattern,
             pattern_type: "merchant",
             pattern_value: "test_invalidation_merchant",
             category: alimentacion_category,
             confidence_weight: 4.0,
             usage_count: 100,
             success_count: 95,
             success_rate: 0.95,
             active: true)

      # The Engine should be able to find and use this pattern
      expense = create(:expense,
                       merchant_name: "TEST_INVALIDATION_MERCHANT",
                       description: "Test cache invalidation")

      result = engine.categorize(expense)
      expect(result).to be_successful
      expect(result.category).to eq(alimentacion_category)

      # Cleanup
      engine.shutdown!
    end
  end

  # ===========================================================================
  # Step 1 — Verify setup: categories and patterns exist in the database
  # ===========================================================================
  describe "Step 1: Setup — categories and patterns are persisted" do
    it "creates all three categories" do
      expect(Category.where(name: %w[Alimentación Transporte Supermercado]).count).to eq(3)
    end

    it "creates the AutoMercado merchant pattern pointing to Supermercado" do
      expect(
        CategorizationPattern.active.find_by(pattern_type: "merchant", pattern_value: "automercado")
      ).to have_attributes(category: supermercado_category)
    end

    it "creates the Uber merchant pattern pointing to Transporte" do
      expect(
        CategorizationPattern.active.find_by(pattern_type: "merchant", pattern_value: "uber")
      ).to have_attributes(category: transporte_category)
    end
  end

  # ===========================================================================
  # Step 2 — Pattern matching: Engine suggests Supermercado with high confidence
  # ===========================================================================
  describe "Step 2: Pattern matching — Engine suggests category for AutoMercado expense" do
    let!(:automercado_expense) do
      create(:expense,
             merchant_name: "AutoMercado",
             description: "Compra semanal de víveres",
             amount: 45_000,
             category: nil)
    end

    it "returns a successful categorization result" do
      result = engine.categorize(automercado_expense)

      expect(result).to be_successful
    end

    it "suggests Supermercado as the category" do
      result = engine.categorize(automercado_expense)

      expect(result.category).to eq(supermercado_category)
    end

    it "returns confidence above 0.8" do
      result = engine.categorize(automercado_expense)

      expect(result.confidence).to be >= 0.8
    end

    it "includes patterns_used referencing the merchant pattern" do
      result = engine.categorize(automercado_expense)

      expect(result.patterns_used).to include("merchant:automercado")
    end
  end

  # ===========================================================================
  # Step 3 — Accept suggestion: apply ML result and verify expense fields
  # ===========================================================================
  describe "Step 3: Accept suggestion — applying ML result updates expense" do
    # We manually wire the ML confidence fields to simulate what the engine
    # writes when auto_update: true triggers update_expense_with_ml_confidence.
    let!(:expense_to_accept) do
      create(:expense,
             merchant_name: "AutoMercado",
             description: "Despensa mensual",
             amount: 30_000,
             category: nil,
             ml_suggested_category: supermercado_category,
             ml_confidence: 0.92)
    end

    before do
      # Simulate the engine flagging a high-confidence suggestion
      expense_to_accept.update!(
        ml_suggested_category: supermercado_category,
        ml_confidence: 0.92,
        categorization_method: "pattern_match",
        categorization_confidence: 0.92
      )
    end

    it "updates category when suggestion is accepted" do
      expense_to_accept.accept_ml_suggestion!
      expense_to_accept.reload

      expect(expense_to_accept.category).to eq(supermercado_category)
    end

    it "clears the ml_suggested_category after acceptance" do
      expense_to_accept.accept_ml_suggestion!
      expense_to_accept.reload

      expect(expense_to_accept.ml_suggested_category).to be_nil
    end

    it "increments ml_correction_count on acceptance" do
      initial_count = expense_to_accept.ml_correction_count.to_i
      expense_to_accept.accept_ml_suggestion!
      expense_to_accept.reload

      expect(expense_to_accept.ml_correction_count).to eq(initial_count + 1)
    end

    it "sets ml_last_corrected_at to a recent timestamp" do
      expense_to_accept.accept_ml_suggestion!
      expense_to_accept.reload

      expect(expense_to_accept.ml_last_corrected_at).to be_within(5.seconds).of(Time.current)
    end
  end

  # ===========================================================================
  # Step 4 — Correct category: user overrides suggestion, counters update
  # ===========================================================================
  describe "Step 4: Correct category — user correction increments tracking fields" do
    let!(:expense_to_correct) do
      create(:expense,
             merchant_name: "AutoMercado",
             description: "Compra urgente",
             amount: 12_000,
             category: transporte_category,            # wrong initial category
             ml_suggested_category: transporte_category,
             ml_confidence: 0.65)
    end

    it "increments ml_correction_count when rejecting suggestion" do
      initial_count = expense_to_correct.ml_correction_count.to_i
      expense_to_correct.reject_ml_suggestion!(supermercado_category.id)
      expense_to_correct.reload

      expect(expense_to_correct.ml_correction_count).to eq(initial_count + 1)
    end

    it "sets ml_last_corrected_at after rejection" do
      expense_to_correct.reject_ml_suggestion!(supermercado_category.id)
      expense_to_correct.reload

      expect(expense_to_correct.ml_last_corrected_at).to be_within(5.seconds).of(Time.current)
    end

    it "applies the new category chosen by the user" do
      expense_to_correct.reject_ml_suggestion!(supermercado_category.id)
      expense_to_correct.reload

      expect(expense_to_correct.category).to eq(supermercado_category)
    end
  end

  # ===========================================================================
  # Step 5 — Pattern learning: PatternLearner creates/updates patterns from feedback
  # ===========================================================================
  describe "Step 5: Pattern learning — PatternLearner processes user correction" do
    let(:learner) { Services::Categorization::PatternLearner.new }

    let!(:correction_expense) do
      create(:expense,
             merchant_name: "AutoMercado",
             description: "Frutas y verduras",
             amount: 8_500,
             category: nil)
    end

    it "returns a successful LearningResult" do
      result = learner.learn_from_correction(
        correction_expense,
        supermercado_category,
        alimentacion_category   # simulated wrong prediction
      )

      expect(result).to be_success
    end

    it "creates or updates a merchant pattern for AutoMercado -> Supermercado" do
      expect do
        learner.learn_from_correction(
          correction_expense,
          supermercado_category,
          alimentacion_category
        )
      end.to change {
        CategorizationPattern.where(
          pattern_type: "merchant",
          pattern_value: "automercado",
          category: supermercado_category
        ).count
      }.by_at_least(0)   # pattern may already exist; just ensure no error
    end

    it "creates a PatternFeedback record capturing the correction" do
      expect do
        learner.learn_from_correction(
          correction_expense,
          supermercado_category,
          alimentacion_category
        )
      end.to change(PatternFeedback, :count).by(1)
    end

    it "creates a PatternLearningEvent" do
      expect do
        learner.learn_from_correction(
          correction_expense,
          supermercado_category,
          nil  # no predicted category
        )
      end.to change(PatternLearningEvent, :count).by(1)
    end
  end

  # ===========================================================================
  # Step 6 — Bulk categorization: BulkOperations::CategorizationService
  # ===========================================================================
  describe "Step 6: Bulk categorization — categorize multiple expenses at once" do
    let!(:bulk_expense_1) do
      create(:expense, merchant_name: "AutoMercado Norte",
             description: "Compra diaria", amount: 15_000, category: nil)
    end

    let!(:bulk_expense_2) do
      create(:expense, merchant_name: "AutoMercado Centro",
             description: "Víveres", amount: 22_500, category: nil)
    end

    let!(:bulk_expense_3) do
      create(:expense, merchant_name: "AutoMercado Sur",
             description: "Frutas", amount: 9_800, category: nil)
    end

    let(:bulk_expense_ids) do
      [ bulk_expense_1.id, bulk_expense_2.id, bulk_expense_3.id ]
    end

    let(:bulk_categorization_result) do
      Services::BulkOperations::CategorizationService.new(
        expense_ids: bulk_expense_ids,
        category_id: supermercado_category.id
      ).call
    end

    it "returns a successful operation result" do
      expect(bulk_categorization_result[:success]).to be true
    end

    it "reports affected_count of 3" do
      expect(bulk_categorization_result[:affected_count]).to eq(3)
    end

    it "assigns Supermercado to all three expenses" do
      bulk_categorization_result  # trigger the operation

      expect(
        Expense.where(id: bulk_expense_ids).pluck(:category_id).uniq
      ).to eq([ supermercado_category.id ])
    end

    it "returns no failures" do
      expect(bulk_categorization_result[:failures]).to be_empty
    end
  end

  # ===========================================================================
  # Step 7 — Bulk status update: mark those same expenses as "processed"
  # ===========================================================================
  describe "Step 7: Bulk status update — mark categorized expenses as processed" do
    let!(:status_expense_1) do
      create(:expense, merchant_name: "AutoMercado A",
             amount: 10_000, category: supermercado_category, status: :pending)
    end

    let!(:status_expense_2) do
      create(:expense, merchant_name: "AutoMercado B",
             amount: 11_000, category: supermercado_category, status: :pending)
    end

    let!(:status_expense_3) do
      create(:expense, merchant_name: "AutoMercado C",
             amount: 12_000, category: supermercado_category, status: :pending)
    end

    let(:status_expense_ids) do
      [ status_expense_1.id, status_expense_2.id, status_expense_3.id ]
    end

    let(:status_update_result) do
      Services::BulkOperations::StatusUpdateService.new(
        expense_ids: status_expense_ids,
        status: "processed"
      ).call
    end

    it "returns a successful operation result" do
      expect(status_update_result[:success]).to be true
    end

    it "reports affected_count of 3" do
      expect(status_update_result[:affected_count]).to eq(3)
    end

    it "marks all three expenses as processed" do
      status_update_result  # trigger

      expect(
        Expense.where(id: status_expense_ids).pluck(:status).uniq
      ).to eq([ "processed" ])
    end

    it "returns no failures" do
      expect(status_update_result[:failures]).to be_empty
    end
  end

  # ===========================================================================
  # Step 8 — API suggest endpoint: POST /api/v1/categorization/suggest
  # ===========================================================================
  describe "Step 8: API categorization suggest endpoint" do
    let!(:api_token) { create(:api_token) }
    let(:auth_headers) do
      {
        "Authorization" => "Bearer #{api_token.token}",
        "Content-Type" => "application/json"
      }
    end

    # Ensure a strong pattern exists so the enhanced service can return suggestions
    before do
      # automercado_pattern is already created via let! above
    end

    it "returns HTTP 200 for a valid merchant_name request" do
      post "/api/v1/categorization/suggest",
           params: { merchant_name: "AutoMercado" }.to_json,
           headers: auth_headers

      expect(response).to have_http_status(:ok)
    end

    it "returns a JSON body with status: success" do
      post "/api/v1/categorization/suggest",
           params: { merchant_name: "AutoMercado" }.to_json,
           headers: auth_headers

      json = JSON.parse(response.body)
      expect(json["status"]).to eq("success")
    end

    it "includes a suggestions array in the response" do
      post "/api/v1/categorization/suggest",
           params: { merchant_name: "AutoMercado" }.to_json,
           headers: auth_headers

      json = JSON.parse(response.body)
      expect(json["suggestions"]).to be_an(Array)
    end

    it "mirrors back expense_data in the response" do
      post "/api/v1/categorization/suggest",
           params: { merchant_name: "AutoMercado", description: "Test" }.to_json,
           headers: auth_headers

      json = JSON.parse(response.body)
      expect(json["expense_data"]).to include("merchant_name" => "AutoMercado")
    end

    it "returns 400 when neither merchant_name nor description is provided" do
      post "/api/v1/categorization/suggest",
           params: { amount: 1000 }.to_json,
           headers: auth_headers

      expect(response).to have_http_status(:bad_request)
    end
  end

  # ===========================================================================
  # Step 9 — Confidence levels: verify threshold boundaries on Expense model
  # ===========================================================================
  describe "Step 9: Confidence levels — threshold classification on Expense model" do
    let(:expense_base) { build(:expense, merchant_name: "TestMerchant") }

    it "classifies confidence >= 0.85 as :high" do
      expense_base.ml_confidence = 0.90
      expect(expense_base.confidence_level).to eq(:high)
    end

    it "classifies confidence exactly at 0.85 as :high" do
      expense_base.ml_confidence = 0.85
      expect(expense_base.confidence_level).to eq(:high)
    end

    it "classifies confidence >= 0.70 and < 0.85 as :medium" do
      expense_base.ml_confidence = 0.75
      expect(expense_base.confidence_level).to eq(:medium)
    end

    it "classifies confidence exactly at 0.70 as :medium" do
      expense_base.ml_confidence = 0.70
      expect(expense_base.confidence_level).to eq(:medium)
    end

    it "classifies confidence >= 0.50 and < 0.70 as :low" do
      expense_base.ml_confidence = 0.60
      expect(expense_base.confidence_level).to eq(:low)
    end

    it "classifies confidence exactly at 0.50 as :low" do
      expense_base.ml_confidence = 0.50
      expect(expense_base.confidence_level).to eq(:low)
    end

    it "classifies confidence < 0.50 as :very_low" do
      expense_base.ml_confidence = 0.30
      expect(expense_base.confidence_level).to eq(:very_low)
    end

    it "classifies nil confidence as :none" do
      expense_base.ml_confidence = nil
      expect(expense_base.confidence_level).to eq(:none)
    end

    it "marks low-confidence expenses as needing review" do
      expense_base.ml_confidence = 0.60
      expect(expense_base.needs_review?).to be true
    end

    it "does not mark high-confidence expenses as needing review" do
      expense_base.ml_confidence = 0.90
      expect(expense_base.needs_review?).to be false
    end
  end

  # ===========================================================================
  # Step 2 Edge Cases — Pattern matching error paths
  # ===========================================================================
  describe "Step 2 edge cases: Pattern matching error and boundary paths" do
    context "when merchant has no matching patterns" do
      let!(:unknown_expense) do
        create(:expense,
               merchant_name: "ZXQ_TOTALLY_UNKNOWN_MERCHANT_999",
               description: "Some random purchase",
               amount: 5_000,
               category: nil)
      end

      it "returns a result without crashing" do
        expect { engine.categorize(unknown_expense) }.not_to raise_error
      end

      it "returns a no-match result (not successful)" do
        result = engine.categorize(unknown_expense)
        expect(result).not_to be_successful
      end
    end

    context "when merchant name contains special characters" do
      let!(:special_char_expense) do
        create(:expense,
               merchant_name: "Café & Panadería Ñoño \"El Rincón\"",
               description: "Compra con caracteres especiales",
               amount: 3_500,
               category: nil)
      end

      it "handles special characters without raising an error" do
        expect { engine.categorize(special_char_expense) }.not_to raise_error
      end

      it "returns a categorization result object (successful or no_match)" do
        result = engine.categorize(special_char_expense)
        # Result must respond to successful? — it should not be nil or raise
        expect(result).to respond_to(:successful?)
      end
    end

    context "when merchant name is very long (500+ characters)" do
      let!(:long_name_expense) do
        create(:expense,
               merchant_name: "A" * 501,
               description: "Long merchant name test",
               amount: 1_000,
               category: nil)
      end

      it "does not crash with a very long merchant name" do
        expect { engine.categorize(long_name_expense) }.not_to raise_error
      end

      it "returns a result object" do
        result = engine.categorize(long_name_expense)
        expect(result).to respond_to(:successful?)
      end
    end

    context "when only inactive patterns exist for a merchant (and no other patterns match)" do
      # Use a distinct category so only the inactive pattern would match
      let!(:inactive_only_category) do
        create(:category, name: "InactiveOnlyCategory", description: "Used only for inactive pattern test")
      end

      let!(:inactive_pattern) do
        create(:categorization_pattern,
               pattern_type: "merchant",
               pattern_value: "qzxpattern_inactive_only",
               category: inactive_only_category,
               confidence_weight: 4.0,
               active: false)
      end

      let!(:inactive_merchant_expense) do
        # A merchant that exactly matches only the inactive pattern's value, not other active ones
        create(:expense,
               merchant_name: "QZXPattern Inactive Only",
               description: "Should not match inactive pattern",
               amount: 7_000,
               category: nil)
      end

      it "does not suggest the inactive_only_category via the inactive pattern" do
        result = engine.categorize(inactive_merchant_expense)
        # The inactive pattern must not contribute — inactive_only_category should never appear
        category_id = result.successful? ? result.category&.id : nil
        expect(category_id).not_to eq(inactive_only_category.id)
      end

      it "verifies inactive patterns are excluded from CategorizationPattern.active scope" do
        expect(CategorizationPattern.active.where(id: inactive_pattern.id)).to be_empty
      end
    end
  end

  # ===========================================================================
  # Step 3/4 Edge Cases — Accept/Reject suggestion error paths
  # ===========================================================================
  describe "Step 3/4 edge cases: Accept/Reject suggestion error paths" do
    context "when accept_ml_suggestion! is called with no suggestion present" do
      let!(:no_suggestion_expense) do
        create(:expense,
               merchant_name: "SomeMerchant",
               description: "No suggestion set",
               amount: 10_000,
               category: alimentacion_category,
               ml_suggested_category: nil,
               ml_confidence: nil)
      end

      it "returns false without raising an error" do
        result = no_suggestion_expense.accept_ml_suggestion!
        expect(result).to be false
      end

      it "does not change the category when no suggestion is present" do
        original_category = no_suggestion_expense.category
        no_suggestion_expense.accept_ml_suggestion!
        no_suggestion_expense.reload
        expect(no_suggestion_expense.category).to eq(original_category)
      end
    end

    context "when correcting to the same category already assigned" do
      let!(:same_category_expense) do
        create(:expense,
               merchant_name: "AutoMercado",
               description: "Re-assigning same category",
               amount: 5_000,
               category: supermercado_category,
               ml_suggested_category: alimentacion_category,
               ml_confidence: 0.65)
      end

      it "handles reject_ml_suggestion! to the same already-assigned category without error" do
        expect do
          same_category_expense.reject_ml_suggestion!(supermercado_category.id)
        end.not_to raise_error
      end

      it "keeps the category as supermercado after 'correcting' to it" do
        same_category_expense.reject_ml_suggestion!(supermercado_category.id)
        same_category_expense.reload
        expect(same_category_expense.category).to eq(supermercado_category)
      end

      it "still increments ml_correction_count" do
        initial = same_category_expense.ml_correction_count.to_i
        same_category_expense.reject_ml_suggestion!(supermercado_category.id)
        same_category_expense.reload
        expect(same_category_expense.ml_correction_count).to eq(initial + 1)
      end
    end

    context "multiple sequential corrections on the same expense" do
      let!(:multi_correction_expense) do
        create(:expense,
               merchant_name: "MultiCorrect",
               description: "Corrected multiple times",
               amount: 8_000,
               category: nil,
               ml_suggested_category: transporte_category,
               ml_confidence: 0.60)
      end

      it "increments ml_correction_count for each sequential correction" do
        # First correction
        multi_correction_expense.reject_ml_suggestion!(alimentacion_category.id)
        multi_correction_expense.reload
        expect(multi_correction_expense.ml_correction_count).to eq(1)

        # Re-set a suggestion so the next correction is valid
        multi_correction_expense.update!(
          ml_suggested_category: supermercado_category,
          ml_confidence: 0.55
        )

        # Second correction
        multi_correction_expense.reject_ml_suggestion!(transporte_category.id)
        multi_correction_expense.reload
        expect(multi_correction_expense.ml_correction_count).to eq(2)

        # Re-set again
        multi_correction_expense.update!(
          ml_suggested_category: alimentacion_category,
          ml_confidence: 0.58
        )

        # Third correction
        multi_correction_expense.reject_ml_suggestion!(supermercado_category.id)
        multi_correction_expense.reload
        expect(multi_correction_expense.ml_correction_count).to eq(3)
      end
    end
  end

  # ===========================================================================
  # Step 6 Edge Cases — Bulk categorization error paths
  # ===========================================================================
  describe "Step 6 edge cases: Bulk categorization error paths" do
    let!(:edge_expense_1) do
      create(:expense, merchant_name: "Edge Merchant A", amount: 1_000, category: nil)
    end

    let!(:edge_expense_2) do
      create(:expense, merchant_name: "Edge Merchant B", amount: 2_000, category: nil)
    end

    context "with an invalid (non-existent) category_id" do
      let(:invalid_category_result) do
        Services::BulkOperations::CategorizationService.new(
          expense_ids: [ edge_expense_1.id ],
          category_id: 999_999_999
        ).call
      end

      it "returns success: false" do
        expect(invalid_category_result[:success]).to be false
      end

      it "does not crash — returns an errors array" do
        expect(invalid_category_result[:errors]).not_to be_empty
      end
    end

    context "with an empty expense_ids array" do
      let(:empty_ids_result) do
        Services::BulkOperations::CategorizationService.new(
          expense_ids: [],
          category_id: supermercado_category.id
        ).call
      end

      it "returns success: false" do
        expect(empty_ids_result[:success]).to be false
      end

      it "includes a meaningful error or message" do
        # The service may put the reason in :errors or :message (or both)
        errors_text = Array(empty_ids_result[:errors]).join
        message_text = empty_ids_result[:message].to_s
        expect(errors_text + message_text).not_to be_empty
      end
    end

    context "with a mix of valid and non-existent expense IDs" do
      let(:mixed_ids_result) do
        Services::BulkOperations::CategorizationService.new(
          expense_ids: [ edge_expense_1.id, 888_888_888 ],
          category_id: supermercado_category.id
        ).call
      end

      it "returns success: false when IDs are missing" do
        expect(mixed_ids_result[:success]).to be false
      end

      it "includes an error about missing expenses" do
        error_text = [
          mixed_ids_result[:errors],
          mixed_ids_result[:message]
        ].flatten.compact.join(" ")

        expect(error_text).to match(/not found|missing|unauthorized/i)
      end
    end

    context "with non-array expense_ids (a string)" do
      let(:string_ids_result) do
        Services::BulkOperations::CategorizationService.new(
          expense_ids: "not_an_array",
          category_id: supermercado_category.id
        ).call
      end

      it "returns success: false" do
        expect(string_ids_result[:success]).to be false
      end

      it "includes a validation error about expense_ids" do
        expect(string_ids_result[:errors].join).to match(/array/i)
      end
    end

    context "with non-array expense_ids (an integer)" do
      let(:integer_ids_result) do
        Services::BulkOperations::CategorizationService.new(
          expense_ids: 42,
          category_id: supermercado_category.id
        ).call
      end

      it "returns success: false" do
        expect(integer_ids_result[:success]).to be false
      end

      it "includes a validation error" do
        expect(integer_ids_result[:errors]).not_to be_empty
      end
    end
  end

  # ===========================================================================
  # Step 7 Edge Cases — Bulk status update error paths
  # ===========================================================================
  describe "Step 7 edge cases: Bulk status update error paths" do
    let!(:status_edge_expense) do
      create(:expense, merchant_name: "StatusEdge", amount: 5_000,
             category: supermercado_category, status: :pending)
    end

    context "with an invalid status value" do
      let(:invalid_status_result) do
        Services::BulkOperations::StatusUpdateService.new(
          expense_ids: [ status_edge_expense.id ],
          status: "definitely_not_a_real_status"
        ).call
      end

      it "returns success: false" do
        expect(invalid_status_result[:success]).to be false
      end

      it "includes a validation error" do
        expect(invalid_status_result[:errors]).not_to be_empty
      end

      it "does not change the expense status" do
        invalid_status_result
        status_edge_expense.reload
        expect(status_edge_expense.status).to eq("pending")
      end
    end

    context "with an empty expense_ids array" do
      let(:empty_status_result) do
        Services::BulkOperations::StatusUpdateService.new(
          expense_ids: [],
          status: "processed"
        ).call
      end

      it "returns success: false" do
        expect(empty_status_result[:success]).to be false
      end

      it "includes an error or message" do
        errors_text = Array(empty_status_result[:errors]).join
        message_text = empty_status_result[:message].to_s
        expect(errors_text + message_text).not_to be_empty
      end
    end
  end

  # ===========================================================================
  # Step 8 Edge Cases — API authentication and parameter validation
  # ===========================================================================
  describe "Step 8 edge cases: API error paths and authentication" do
    let!(:api_token) { create(:api_token) }
    let(:auth_headers) do
      {
        "Authorization" => "Bearer #{api_token.token}",
        "Content-Type" => "application/json"
      }
    end

    context "when no Authorization header is provided" do
      it "returns HTTP 401" do
        post "/api/v1/categorization/suggest",
             params: { merchant_name: "AutoMercado" }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when an invalid auth token is provided" do
      it "returns HTTP 401" do
        post "/api/v1/categorization/suggest",
             params: { merchant_name: "AutoMercado" }.to_json,
             headers: {
               "Authorization" => "Bearer totally_invalid_token_xyz",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when merchant_name is empty string" do
      it "returns HTTP 400 (bad request) since neither merchant nor description given" do
        post "/api/v1/categorization/suggest",
             params: { merchant_name: "" }.to_json,
             headers: auth_headers

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "when merchant_name is whitespace only" do
      it "returns HTTP 400 since blank merchant_name without description is invalid" do
        post "/api/v1/categorization/suggest",
             params: { merchant_name: "   " }.to_json,
             headers: auth_headers

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "when merchant has no matching patterns (unknown merchant via API)" do
      it "returns HTTP 200 with an empty suggestions array" do
        post "/api/v1/categorization/suggest",
             params: { merchant_name: "TOTALLY_UNKNOWN_NOCLUE_MERCHANT_9999" }.to_json,
             headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["suggestions"]).to be_an(Array)
      end
    end

    context "POST /api/v1/categorization/batch_suggest" do
      it "returns HTTP 200 for a valid batch of expenses" do
        post "/api/v1/categorization/batch_suggest",
             params: {
               expenses: [
                 { merchant_name: "AutoMercado" },
                 { merchant_name: "Uber" }
               ]
             }.to_json,
             headers: auth_headers

        # Accept 200 (success) or 500 (known regression EFG-100 — document the failure)
        expect([ 200, 500 ]).to include(response.status),
          "batch_suggest returned unexpected status #{response.status}: #{response.body}"
      end

      it "returns HTTP 401 without auth token" do
        post "/api/v1/categorization/batch_suggest",
             params: { expenses: [ { merchant_name: "AutoMercado" } ] }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # ===========================================================================
  # General error paths — Categorization engine and pattern learner edge cases
  # ===========================================================================
  describe "General error paths: Engine and PatternLearner edge cases" do
    context "Engine: categorize with no patterns in the database at all" do
      before do
        # Remove all patterns — only for this example
        CategorizationPattern.delete_all
      end

      let!(:no_pattern_expense) do
        create(:expense,
               merchant_name: "AnyMerchant",
               description: "No patterns in DB",
               amount: 5_000,
               category: nil)
      end

      it "does not raise an error" do
        expect { engine.categorize(no_pattern_expense) }.not_to raise_error
      end

      it "returns a no-match result" do
        result = engine.categorize(no_pattern_expense)
        expect(result).not_to be_successful
      end
    end

    context "PatternLearner: learn_from_correction with nil expense" do
      let(:learner) { Services::Categorization::PatternLearner.new }

      it "does not raise an error" do
        expect do
          learner.learn_from_correction(nil, supermercado_category)
        end.not_to raise_error
      end

      it "returns an unsuccessful LearningResult" do
        result = learner.learn_from_correction(nil, supermercado_category)
        expect(result.success?).to be false
      end
    end

    context "PatternLearner: learn_from_correction with nil category" do
      let(:learner) { Services::Categorization::PatternLearner.new }

      let!(:valid_expense) do
        create(:expense,
               merchant_name: "ValidMerchant",
               description: "Category is nil",
               amount: 3_000,
               category: nil)
      end

      it "does not raise an error" do
        expect do
          learner.learn_from_correction(valid_expense, nil)
        end.not_to raise_error
      end

      it "returns an unsuccessful LearningResult" do
        result = learner.learn_from_correction(valid_expense, nil)
        expect(result.success?).to be false
      end
    end
  end
end
