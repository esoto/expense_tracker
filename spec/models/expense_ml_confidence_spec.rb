require 'rails_helper'

RSpec.describe Expense, type: :model, integration: true do
  describe "ML Confidence functionality", integration: true do
    let(:email_account) { create(:email_account) }
    let(:category) { create(:category, name: "Alimentación") }
    let(:suggested_category) { create(:category, name: "Transporte") }
    let(:expense) { create(:expense, email_account: email_account, category: category) }

    describe "associations", integration: true do
      it { should belong_to(:ml_suggested_category).class_name("Category").optional }
    end

    describe "#confidence_level", integration: true do
      context "when ml_confidence is nil" do
        before { expense.ml_confidence = nil }
        it { expect(expense.confidence_level).to eq(:none) }
      end

      context "when ml_confidence is >= 0.85" do
        before { expense.ml_confidence = 0.90 }
        it { expect(expense.confidence_level).to eq(:high) }
      end

      context "when ml_confidence is >= 0.70" do
        before { expense.ml_confidence = 0.75 }
        it { expect(expense.confidence_level).to eq(:medium) }
      end

      context "when ml_confidence is >= 0.50" do
        before { expense.ml_confidence = 0.60 }
        it { expect(expense.confidence_level).to eq(:low) }
      end

      context "when ml_confidence is < 0.50" do
        before { expense.ml_confidence = 0.30 }
        it { expect(expense.confidence_level).to eq(:very_low) }
      end
    end

    describe "#confidence_percentage", integration: true do
      context "when ml_confidence is nil" do
        before { expense.ml_confidence = nil }
        it { expect(expense.confidence_percentage).to eq(0) }
      end

      context "when ml_confidence is present" do
        before { expense.ml_confidence = 0.756 }
        it { expect(expense.confidence_percentage).to eq(76) }
      end
    end

    describe "#needs_review?", integration: true do
      context "when confidence level is low" do
        before { expense.ml_confidence = 0.55 }
        it { expect(expense.needs_review?).to be true }
      end

      context "when confidence level is very_low" do
        before { expense.ml_confidence = 0.30 }
        it { expect(expense.needs_review?).to be true }
      end

      context "when confidence level is medium or higher" do
        before { expense.ml_confidence = 0.75 }
        it { expect(expense.needs_review?).to be false }
      end
    end

    describe "#accept_ml_suggestion!", integration: true do
      context "when ml_suggested_category_id is present" do
        before do
          expense.ml_suggested_category_id = suggested_category.id
          expense.ml_confidence = 0.60
          expense.ml_correction_count = 1
        end

        it "applies the suggested category" do
          expect { expense.accept_ml_suggestion! }
            .to change { expense.category_id }
            .from(category.id)
            .to(suggested_category.id)
        end

        it "clears the ml_suggested_category_id" do
          expense.accept_ml_suggestion!
          expect(expense.ml_suggested_category_id).to be_nil
        end

        it "sets confidence to 1.0" do
          expense.accept_ml_suggestion!
          expect(expense.ml_confidence).to eq(1.0)
        end

        it "updates ml_confidence_explanation" do
          expense.accept_ml_suggestion!
          expect(expense.ml_confidence_explanation).to eq("Manually confirmed by user")
        end

        it "increments ml_correction_count" do
          expect { expense.accept_ml_suggestion! }
            .to change { expense.ml_correction_count }
            .from(1)
            .to(2)
        end

        it "updates ml_last_corrected_at" do
          freeze_time do
            expense.accept_ml_suggestion!
            expect(expense.ml_last_corrected_at).to eq(Time.current)
          end
        end
      end

      context "when ml_suggested_category_id is not present" do
        before { expense.ml_suggested_category_id = nil }

        it "returns false" do
          expect(expense.accept_ml_suggestion!).to be false
        end

        it "does not change the category" do
          expect { expense.accept_ml_suggestion! }
            .not_to change { expense.category_id }
        end
      end
    end

    describe "#reject_ml_suggestion!", integration: true do
      let(:new_category) { create(:category, name: "Servicios") }

      before do
        expense.ml_suggested_category_id = suggested_category.id
        expense.ml_confidence = 0.60
        expense.ml_correction_count = 0
      end

      it "applies the new category" do
        expect { expense.reject_ml_suggestion!(new_category.id) }
          .to change { expense.category_id }
          .from(category.id)
          .to(new_category.id)
      end

      it "clears the ml_suggested_category_id" do
        expense.reject_ml_suggestion!(new_category.id)
        expect(expense.ml_suggested_category_id).to be_nil
      end

      it "sets confidence to 1.0" do
        expense.reject_ml_suggestion!(new_category.id)
        expect(expense.ml_confidence).to eq(1.0)
      end

      it "updates ml_confidence_explanation" do
        expense.reject_ml_suggestion!(new_category.id)
        expect(expense.ml_confidence_explanation).to eq("Manually corrected by user")
      end

      it "increments ml_correction_count" do
        expect { expense.reject_ml_suggestion!(new_category.id) }
          .to change { expense.ml_correction_count }
          .from(0)
          .to(1)
      end

      it "updates ml_last_corrected_at" do
        freeze_time do
          expense.reject_ml_suggestion!(new_category.id)
          expect(expense.ml_last_corrected_at).to eq(Time.current)
        end
      end

      it "creates a pattern learning event" do
        expect { expense.reject_ml_suggestion!(new_category.id) }
          .to change { PatternLearningEvent.count }
          .by(1)
      end

      it "creates learning event with correct attributes" do
        expense.reject_ml_suggestion!(new_category.id)
        event = PatternLearningEvent.last

        expect(event.category_id).to eq(new_category.id)
        expect(event.pattern_used).to eq("manual_correction")
        expect(event.was_correct).to be true
        expect(event.confidence_score).to eq(1.0)
        expect(event.context_data["merchant"]).to eq(expense.merchant_name)
      end
    end
  end
end
