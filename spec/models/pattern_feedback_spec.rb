# frozen_string_literal: true

require "rails_helper"

RSpec.describe PatternFeedback, type: :model, performance: true do
  let(:category) { Category.create!(name: "Food & Dining") }
  let(:email_account) { EmailAccount.create!(email: "test@example.com", provider: "gmail", bank_name: "Test Bank") }
  let(:expense) do
    Expense.create!(
      email_account: email_account,
      merchant_name: "Starbucks",
      description: "Coffee purchase",
      amount: 5.50,
      transaction_date: DateTime.now,
      category: category
    )
  end
  let(:pattern) do
    CategorizationPattern.create!(
      category: category,
      pattern_type: "merchant",
      pattern_value: "starbucks",
      confidence_weight: 1.5
    )
  end

  describe "associations", performance: true do
    it { should belong_to(:categorization_pattern).optional }
    it { should belong_to(:expense) }
    it { should belong_to(:category) }
  end

  describe "validations", performance: true do
    subject { described_class.new(expense: expense, category: category, feedback_type: "accepted") }

    # feedback_type has a before_validation callback that sets default value
    # so we can't use standard presence validation test
    it "validates presence of feedback_type" do
      feedback = described_class.new(expense: expense, category: category)
      feedback.feedback_type = ""
      expect(feedback).not_to be_valid
      expect(feedback.errors[:feedback_type]).to include("can't be blank")
    end

    it { should validate_inclusion_of(:feedback_type).in_array(%w[accepted rejected corrected correction]) }
  end

  describe "scopes", performance: true do
    let(:expense2) do
      Expense.create!(
        email_account: email_account,
        merchant_name: "McDonald's",
        description: "Fast food",
        amount: 8.50,
        transaction_date: DateTime.now,
        category: category
      )
    end
    let(:expense3) do
      Expense.create!(
        email_account: email_account,
        merchant_name: "Burger King",
        description: "Lunch",
        amount: 12.00,
        transaction_date: DateTime.now,
        category: category
      )
    end
    let(:expense4) do
      Expense.create!(
        email_account: email_account,
        merchant_name: "Pizza Hut",
        description: "Dinner",
        amount: 25.00,
        transaction_date: DateTime.now,
        category: category
      )
    end

    let!(:accepted_feedback) do
      described_class.create!(
        expense: expense,
        category: category,
        categorization_pattern: pattern,
        feedback_type: "accepted",
        was_correct: true
      )
    end

    let!(:rejected_feedback) do
      described_class.create!(
        expense: expense2,
        category: category,
        categorization_pattern: pattern,
        feedback_type: "rejected",
        was_correct: false
      )
    end

    let!(:corrected_feedback) do
      described_class.create!(
        expense: expense3,
        category: category,
        categorization_pattern: pattern,
        feedback_type: "corrected",
        was_correct: false
      )
    end

    let!(:correction_feedback) do
      described_class.create!(
        expense: expense4,
        category: category,
        feedback_type: "correction",
        was_correct: false
      )
    end

    it "filters accepted feedback" do
      expect(described_class.accepted).to include(accepted_feedback)
      expect(described_class.accepted).not_to include(rejected_feedback, corrected_feedback, correction_feedback)
    end

    it "filters rejected feedback" do
      expect(described_class.rejected).to include(rejected_feedback)
      expect(described_class.rejected).not_to include(accepted_feedback, corrected_feedback, correction_feedback)
    end

    it "filters corrected feedback" do
      expect(described_class.corrected).to include(corrected_feedback)
      expect(described_class.corrected).not_to include(accepted_feedback, rejected_feedback, correction_feedback)
    end

    it "filters correction feedback" do
      expect(described_class.correction).to include(correction_feedback)
      expect(described_class.correction).not_to include(accepted_feedback, rejected_feedback, corrected_feedback)
    end

    it "orders by recent first" do
      older_feedback = described_class.create!(
        expense: expense,
        category: category,
        feedback_type: "accepted",
        created_at: 1.day.ago
      )

      expect(described_class.recent.first).to eq(correction_feedback)
      expect(described_class.recent.last).to eq(older_feedback)
    end
  end

  describe "callbacks", performance: true do
    describe "set_default_feedback_type", performance: true do
      it "sets feedback_type to accepted when was_correct is true" do
        feedback = described_class.new(
          expense: expense,
          category: category,
          was_correct: true
        )
        feedback.valid?
        expect(feedback.feedback_type).to eq("accepted")
      end

      it "sets feedback_type to rejected when was_correct is false" do
        feedback = described_class.new(
          expense: expense,
          category: category,
          was_correct: false
        )
        feedback.valid?
        expect(feedback.feedback_type).to eq("rejected")
      end

      it "does not override explicitly set feedback_type" do
        feedback = described_class.new(
          expense: expense,
          category: category,
          feedback_type: "correction",
          was_correct: true
        )
        feedback.valid?
        expect(feedback.feedback_type).to eq("correction")
      end
    end

    describe "update_pattern_performance", performance: true do
      it "records successful usage for accepted feedback" do
        expect(pattern).to receive(:record_usage).with(true)

        described_class.create!(
          expense: expense,
          category: category,
          categorization_pattern: pattern,
          feedback_type: "accepted"
        )
      end

      it "records unsuccessful usage for rejected feedback" do
        expect(pattern).to receive(:record_usage).with(false)

        described_class.create!(
          expense: expense,
          category: category,
          categorization_pattern: pattern,
          feedback_type: "rejected"
        )
      end

      it "records unsuccessful usage for corrected feedback" do
        expect(pattern).to receive(:record_usage).with(false)

        described_class.create!(
          expense: expense,
          category: category,
          categorization_pattern: pattern,
          feedback_type: "corrected"
        )
      end

      it "does not update pattern performance when no pattern is associated" do
        described_class.create!(
          expense: expense,
          category: category,
          feedback_type: "correction"
        )
        # Should not raise any errors
      end
    end

    describe "create_pattern_from_correction", performance: true do
      let(:new_category) { Category.create!(name: "Transportation") }

      it "creates a new pattern from correction feedback" do
        expect {
          described_class.create!(
            expense: expense,
            category: new_category,
            feedback_type: "correction"
          )
        }.to change { CategorizationPattern.count }.by(1)

        new_pattern = CategorizationPattern.last
        expect(new_pattern.category).to eq(new_category)
        expect(new_pattern.pattern_type).to eq("merchant")
        expect(new_pattern.pattern_value).to eq("starbucks")
        expect(new_pattern.user_created).to be true
        expect(new_pattern.confidence_weight).to eq(1.2)
        expect(new_pattern.metadata["created_from_feedback"]).to be true
      end

      it "does not create duplicate patterns" do
        # Create existing pattern
        CategorizationPattern.create!(
          category: new_category,
          pattern_type: "merchant",
          pattern_value: "starbucks"
        )

        expect {
          described_class.create!(
            expense: expense,
            category: new_category,
            feedback_type: "correction"
          )
        }.not_to change { CategorizationPattern.count }
      end

      it "does not create pattern for non-correction feedback" do
        expect {
          described_class.create!(
            expense: expense,
            category: category,
            feedback_type: "accepted"
          )
        }.not_to change { CategorizationPattern.count }
      end
    end
  end

  describe ".record_feedback", performance: true do
    it "creates feedback record with provided parameters" do
      feedback = described_class.record_feedback(
        expense: expense,
        correct_category: category,
        pattern: pattern,
        was_correct: true,
        confidence: 0.85,
        type: "accepted"
      )

      expect(feedback).to be_persisted
      expect(feedback.expense).to eq(expense)
      expect(feedback.category).to eq(category)
      expect(feedback.categorization_pattern).to eq(pattern)
      expect(feedback.was_correct).to be true
      expect(feedback.confidence_score).to eq(0.85)
      expect(feedback.feedback_type).to eq("accepted")
    end

    it "defaults to accepted type for invalid type" do
      feedback = described_class.record_feedback(
        expense: expense,
        correct_category: category,
        pattern: nil,
        was_correct: true,
        type: "invalid"
      )

      expect(feedback.feedback_type).to eq("accepted")
    end
  end

  describe "#successful?", performance: true do
    it "returns true when was_correct is true" do
      feedback = described_class.new(was_correct: true)
      expect(feedback.successful?).to be true
    end

    it "returns false when was_correct is false" do
      feedback = described_class.new(was_correct: false)
      expect(feedback.successful?).to be false
    end

    it "returns false when was_correct is nil" do
      feedback = described_class.new(was_correct: nil)
      expect(feedback.successful?).to be false
    end
  end

  describe "#improvement_suggestion", performance: true do
    let(:feedback) do
      described_class.new(
        expense: expense,
        category: category,
        categorization_pattern: pattern,
        feedback_type: defined?(feedback_type) ? feedback_type : "correction"
      )
    end

    context "with correction feedback" do
      let(:feedback_type) { "correction" }

      it "suggests creating a new pattern" do
        suggestion = feedback.improvement_suggestion

        expect(suggestion[:suggested_action]).to eq("create_new_pattern")
        expect(suggestion[:category_id]).to eq(category.id)
        expect(suggestion[:pattern_type]).to eq("merchant")
        expect(suggestion[:pattern_value]).to eq("Starbucks")
        expect(suggestion[:confidence_adjustment]).to eq(0.2)
      end
    end

    context "with rejected feedback" do
      let(:feedback_type) { "rejected" }

      it "suggests adjusting existing pattern" do
        suggestion = feedback.improvement_suggestion

        expect(suggestion[:suggested_action]).to eq("adjust_pattern")
        expect(suggestion[:confidence_adjustment]).to eq(-0.1)
      end
    end

    context "with accepted feedback" do
      let(:feedback_type) { "accepted" }

      it "returns nil" do
        expect(feedback.improvement_suggestion).to be_nil
      end
    end

    context "with expense without merchant name" do
      let(:feedback_type) { "correction" }

      before do
        expense.update!(merchant_name: nil)
      end

      it "uses description as pattern value" do
        suggestion = feedback.improvement_suggestion

        expect(suggestion[:pattern_type]).to eq("description")
        expect(suggestion[:pattern_value]).to eq("Coffee purchase")
      end
    end

    context "with expense without merchant or description" do
      let(:feedback_type) { "correction" }

      before do
        expense.update!(merchant_name: nil, description: nil)
      end

      it "suggests keyword pattern type" do
        suggestion = feedback.improvement_suggestion

        expect(suggestion[:pattern_type]).to eq("keyword")
        expect(suggestion[:pattern_value]).to be_nil
      end
    end

    it "includes context information" do
      feedback.feedback_type = "correction"
      suggestion = feedback.improvement_suggestion

      expect(suggestion[:context]).to include(
        expense_merchant: "Starbucks",
        expense_amount: 5.50,
        expense_date: expense.transaction_date,
        original_pattern_type: "merchant",
        original_pattern_value: "starbucks"
      )
    end
  end
end
