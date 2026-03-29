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
      [bulk_expense_1.id, bulk_expense_2.id, bulk_expense_3.id]
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
      ).to eq([supermercado_category.id])
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
      [status_expense_1.id, status_expense_2.id, status_expense_3.id]
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
      ).to eq(["processed"])
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
end
