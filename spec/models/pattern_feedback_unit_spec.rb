# frozen_string_literal: true

require "rails_helper"

RSpec.describe PatternFeedback, type: :model, unit: true do
  describe "associations" do
    it { should belong_to(:categorization_pattern).optional }
    it { should belong_to(:expense) }
    it { should belong_to(:category) }
  end

  describe "validations" do
    describe "feedback_type validation" do
      it { should validate_presence_of(:feedback_type) }
      
      it "validates inclusion of feedback_type" do
        should validate_inclusion_of(:feedback_type)
          .in_array(%w[accepted rejected corrected correction])
      end

      it "rejects invalid feedback types" do
        feedback = build_stubbed(:pattern_feedback, feedback_type: "invalid_type")
        expect(feedback).not_to be_valid
        expect(feedback.errors[:feedback_type]).to include("is not included in the list")
      end
    end
  end

  describe "callbacks" do
    describe "before_validation :set_default_feedback_type" do
      context "when feedback_type is nil" do
        it "sets to 'accepted' when was_correct is true" do
          feedback = build_stubbed(:pattern_feedback, feedback_type: nil, was_correct: true)
          feedback.send(:set_default_feedback_type)
          expect(feedback.feedback_type).to eq("accepted")
        end

        it "sets to 'rejected' when was_correct is false" do
          feedback = build_stubbed(:pattern_feedback, feedback_type: nil, was_correct: false)
          feedback.send(:set_default_feedback_type)
          expect(feedback.feedback_type).to eq("rejected")
        end

        it "sets to 'rejected' when was_correct is nil" do
          feedback = build_stubbed(:pattern_feedback, feedback_type: nil, was_correct: nil)
          feedback.send(:set_default_feedback_type)
          expect(feedback.feedback_type).to eq("rejected")
        end
      end

      context "when feedback_type is already set" do
        it "preserves existing feedback_type" do
          feedback = build_stubbed(:pattern_feedback, feedback_type: "correction", was_correct: true)
          feedback.send(:set_default_feedback_type)
          expect(feedback.feedback_type).to eq("correction")
        end
      end
    end

    describe "after_create :update_pattern_performance" do
      let(:pattern) { double("categorization_pattern") }
      let(:feedback) { build_stubbed(:pattern_feedback, categorization_pattern: pattern) }

      context "with accepted feedback" do
        it "records successful usage" do
          feedback.feedback_type = "accepted"
          expect(pattern).to receive(:record_usage).with(true)
          feedback.send(:update_pattern_performance)
        end
      end

      context "with rejected feedback" do
        it "records unsuccessful usage" do
          feedback.feedback_type = "rejected"
          expect(pattern).to receive(:record_usage).with(false)
          feedback.send(:update_pattern_performance)
        end
      end

      context "with corrected feedback" do
        it "records unsuccessful usage" do
          feedback.feedback_type = "corrected"
          expect(pattern).to receive(:record_usage).with(false)
          feedback.send(:update_pattern_performance)
        end
      end

      context "with correction feedback" do
        it "records unsuccessful usage" do
          feedback.feedback_type = "correction"
          expect(pattern).to receive(:record_usage).with(false)
          feedback.send(:update_pattern_performance)
        end
      end

      context "without categorization pattern" do
        it "doesn't attempt to update performance" do
          feedback.categorization_pattern = nil
          expect { feedback.send(:update_pattern_performance) }.not_to raise_error
        end
      end
    end

    describe "after_create :create_pattern_from_correction" do
      let(:category) { build_stubbed(:category, id: 1) }
      let(:expense) { build_stubbed(:expense, id: 2, merchant_name: "Test Store", description: "Test purchase") }
      let(:feedback) { build_stubbed(:pattern_feedback, 
        id: 3,
        feedback_type: "correction",
        category: category,
        expense: expense,
        expense_id: expense.id
      ) }

      context "when feedback is correction type" do
        it "creates new pattern from merchant name" do
          allow(feedback).to receive(:improvement_suggestion).and_return({
            pattern_type: "merchant",
            pattern_value: "Test Store"
          })

          expect(CategorizationPattern).to receive(:find_by).with(
            category: category,
            pattern_type: "merchant",
            pattern_value: "test store"
          ).and_return(nil)

          expect(CategorizationPattern).to receive(:create!).with(
            category: category,
            pattern_type: "merchant",
            pattern_value: "Test Store",
            confidence_weight: 1.2,
            user_created: true,
            metadata: {
              created_from_feedback: true,
              feedback_id: 3,
              expense_id: 2
            }
          )

          feedback.send(:create_pattern_from_correction)
        end

        it "normalizes pattern values before checking existence" do
          allow(feedback).to receive(:improvement_suggestion).and_return({
            pattern_type: "keyword",
            pattern_value: "  UPPERCASE  "
          })

          expect(CategorizationPattern).to receive(:find_by).with(
            category: category,
            pattern_type: "keyword",
            pattern_value: "uppercase"
          ).and_return(nil)

          expect(CategorizationPattern).to receive(:create!)

          feedback.send(:create_pattern_from_correction)
        end

        it "doesn't create pattern if it already exists" do
          existing_pattern = double("existing_pattern")
          
          allow(feedback).to receive(:improvement_suggestion).and_return({
            pattern_type: "merchant",
            pattern_value: "Existing Store"
          })

          expect(CategorizationPattern).to receive(:find_by).with(
            category: category,
            pattern_type: "merchant",
            pattern_value: "existing store"
          ).and_return(existing_pattern)

          expect(CategorizationPattern).not_to receive(:create!)

          feedback.send(:create_pattern_from_correction)
        end

        it "doesn't create pattern if suggestion is incomplete" do
          allow(feedback).to receive(:improvement_suggestion).and_return({
            pattern_type: nil,
            pattern_value: "Value"
          })

          expect(CategorizationPattern).not_to receive(:create!)

          feedback.send(:create_pattern_from_correction)
        end
      end

      context "when feedback is not correction type" do
        it "doesn't create pattern" do
          feedback.feedback_type = "accepted"
          expect(CategorizationPattern).not_to receive(:create!)
          feedback.send(:create_pattern_from_correction)
        end
      end
    end

    describe "after_commit :invalidate_analytics_cache" do
      it "invalidates pattern analytics cache" do
        feedback = build_stubbed(:pattern_feedback)
        cache = double("cache")
        
        allow(Rails).to receive(:cache).and_return(cache)
        expect(cache).to receive(:respond_to?).with(:delete_matched).and_return(true)
        expect(cache).to receive(:delete_matched).with("pattern_analytics/*")
        
        feedback.send(:invalidate_analytics_cache)
      end

      it "handles cache without delete_matched method" do
        feedback = build_stubbed(:pattern_feedback)
        cache = double("cache")
        
        allow(Rails).to receive(:cache).and_return(cache)
        expect(cache).to receive(:respond_to?).with(:delete_matched).and_return(false)
        expect(cache).not_to receive(:delete_matched)
        
        feedback.send(:invalidate_analytics_cache)
      end

      it "handles cache invalidation errors gracefully" do
        feedback = build_stubbed(:pattern_feedback)
        cache = double("cache")
        
        allow(Rails).to receive(:cache).and_return(cache)
        expect(cache).to receive(:respond_to?).with(:delete_matched).and_return(true)
        expect(cache).to receive(:delete_matched).and_raise(StandardError.new("Cache error"))
        expect(Rails.logger).to receive(:error).with(match(/Analytics cache invalidation failed/))
        
        expect { feedback.send(:invalidate_analytics_cache) }.not_to raise_error
      end
    end
  end

  describe "scopes" do
    describe ".accepted" do
      it "returns accepted feedback" do
        relation = double("relation")
        expect(PatternFeedback).to receive(:where).with(feedback_type: "accepted").and_return(relation)
        expect(PatternFeedback.accepted).to eq(relation)
      end
    end

    describe ".rejected" do
      it "returns rejected feedback" do
        relation = double("relation")
        expect(PatternFeedback).to receive(:where).with(feedback_type: "rejected").and_return(relation)
        expect(PatternFeedback.rejected).to eq(relation)
      end
    end

    describe ".corrected" do
      it "returns corrected feedback" do
        relation = double("relation")
        expect(PatternFeedback).to receive(:where).with(feedback_type: "corrected").and_return(relation)
        expect(PatternFeedback.corrected).to eq(relation)
      end
    end

    describe ".correction" do
      it "returns correction feedback" do
        relation = double("relation")
        expect(PatternFeedback).to receive(:where).with(feedback_type: "correction").and_return(relation)
        expect(PatternFeedback.correction).to eq(relation)
      end
    end

    describe ".recent" do
      it "orders by created_at descending" do
        relation = double("relation")
        expect(PatternFeedback).to receive(:order).with(created_at: :desc).and_return(relation)
        expect(PatternFeedback.recent).to eq(relation)
      end
    end
  end

  describe "class methods" do
    describe ".record_feedback" do
      let(:expense) { build_stubbed(:expense) }
      let(:category) { build_stubbed(:category) }
      let(:pattern) { build_stubbed(:categorization_pattern) }

      it "creates feedback with all parameters" do
        expect(PatternFeedback).to receive(:create!).with(
          expense: expense,
          category: category,
          categorization_pattern: pattern,
          was_correct: true,
          confidence_score: 0.95,
          feedback_type: "accepted"
        )

        PatternFeedback.record_feedback(
          expense: expense,
          correct_category: category,
          pattern: pattern,
          was_correct: true,
          confidence: 0.95,
          type: "accepted"
        )
      end

      it "validates feedback type" do
        expect(PatternFeedback).to receive(:create!).with(
          hash_including(feedback_type: "correction")
        )

        PatternFeedback.record_feedback(
          expense: expense,
          correct_category: category,
          pattern: pattern,
          was_correct: false,
          type: "correction"
        )
      end

      it "defaults to accepted for invalid feedback types" do
        expect(PatternFeedback).to receive(:create!).with(
          hash_including(feedback_type: "accepted")
        )

        PatternFeedback.record_feedback(
          expense: expense,
          correct_category: category,
          pattern: nil,
          was_correct: true,
          type: "invalid_type"
        )
      end

      it "handles nil pattern" do
        expect(PatternFeedback).to receive(:create!).with(
          hash_including(categorization_pattern: nil)
        )

        PatternFeedback.record_feedback(
          expense: expense,
          correct_category: category,
          pattern: nil,
          was_correct: false
        )
      end

      it "handles nil confidence" do
        expect(PatternFeedback).to receive(:create!).with(
          hash_including(confidence_score: nil)
        )

        PatternFeedback.record_feedback(
          expense: expense,
          correct_category: category,
          pattern: pattern,
          was_correct: true,
          confidence: nil
        )
      end
    end
  end

  describe "instance methods" do
    describe "#successful?" do
      it "returns true when was_correct is true" do
        feedback = build_stubbed(:pattern_feedback, was_correct: true)
        expect(feedback.successful?).to be true
      end

      it "returns false when was_correct is false" do
        feedback = build_stubbed(:pattern_feedback, was_correct: false)
        expect(feedback.successful?).to be false
      end

      it "returns false when was_correct is nil" do
        feedback = build_stubbed(:pattern_feedback, was_correct: nil)
        expect(feedback.successful?).to be false
      end
    end

    describe "#improvement_suggestion" do
      let(:expense) { build_stubbed(:expense, 
        merchant_name: "Test Store",
        description: "Purchase at store",
        amount: 100,
        transaction_date: Time.current
      ) }
      let(:category) { build_stubbed(:category, id: 1) }
      let(:pattern) { build_stubbed(:categorization_pattern, 
        pattern_type: "merchant",
        pattern_value: "old_store"
      ) }
      let(:feedback) { build_stubbed(:pattern_feedback, 
        expense: expense,
        category: category,
        categorization_pattern: pattern
      ) }

      context "with correction feedback" do
        before { feedback.feedback_type = "correction" }

        it "suggests creating new merchant pattern" do
          suggestion = feedback.improvement_suggestion
          
          expect(suggestion[:suggested_action]).to eq("create_new_pattern")
          expect(suggestion[:category_id]).to eq(1)
          expect(suggestion[:pattern_type]).to eq("merchant")
          expect(suggestion[:pattern_value]).to eq("Test Store")
          expect(suggestion[:confidence_adjustment]).to eq(0.2)
        end

        it "includes context information" do
          suggestion = feedback.improvement_suggestion
          
          expect(suggestion[:context]).to include(
            expense_merchant: "Test Store",
            expense_amount: 100,
            expense_date: expense.transaction_date,
            original_pattern_type: "merchant",
            original_pattern_value: "old_store"
          )
        end
      end

      context "with rejected feedback" do
        before { feedback.feedback_type = "rejected" }

        it "suggests adjusting pattern" do
          suggestion = feedback.improvement_suggestion
          
          expect(suggestion[:suggested_action]).to eq("adjust_pattern")
          expect(suggestion[:confidence_adjustment]).to eq(-0.1)
        end
      end

      context "with corrected feedback" do
        before { feedback.feedback_type = "corrected" }

        it "suggests adjusting pattern" do
          suggestion = feedback.improvement_suggestion
          
          expect(suggestion[:suggested_action]).to eq("adjust_pattern")
          expect(suggestion[:confidence_adjustment]).to eq(-0.1)
        end
      end

      context "with accepted feedback" do
        before { feedback.feedback_type = "accepted" }

        it "returns nil" do
          expect(feedback.improvement_suggestion).to be_nil
        end
      end

      context "pattern type determination" do
        it "suggests merchant pattern when merchant name exists" do
          expense.merchant_name = "Store Name"
          feedback.feedback_type = "correction"
          
          suggestion = feedback.improvement_suggestion
          expect(suggestion[:pattern_type]).to eq("merchant")
          expect(suggestion[:pattern_value]).to eq("Store Name")
        end

        it "suggests description pattern when no merchant but has description" do
          expense.merchant_name = nil
          expense.description = "Description text"
          feedback.feedback_type = "correction"
          
          suggestion = feedback.improvement_suggestion
          expect(suggestion[:pattern_type]).to eq("description")
          expect(suggestion[:pattern_value]).to eq("Description text")
        end

        it "suggests keyword pattern when no merchant or description" do
          expense.merchant_name = nil
          expense.description = nil
          feedback.feedback_type = "correction"
          
          suggestion = feedback.improvement_suggestion
          expect(suggestion[:pattern_type]).to eq("keyword")
          expect(suggestion[:pattern_value]).to be_nil
        end
      end

      context "with nil associations" do
        it "handles nil expense" do
          feedback.expense = nil
          feedback.feedback_type = "correction"
          
          suggestion = feedback.improvement_suggestion
          expect(suggestion[:pattern_value]).to be_nil
          expect(suggestion[:context][:expense_merchant]).to be_nil
        end

        it "handles nil category" do
          feedback.category = nil
          feedback.feedback_type = "correction"
          
          suggestion = feedback.improvement_suggestion
          expect(suggestion[:category_id]).to be_nil
        end

        it "handles nil pattern" do
          feedback.categorization_pattern = nil
          feedback.feedback_type = "correction"
          
          suggestion = feedback.improvement_suggestion
          expect(suggestion[:context][:original_pattern_type]).to be_nil
          expect(suggestion[:context][:original_pattern_value]).to be_nil
        end
      end
    end

    describe "#correction_feedback? (private)" do
      it "returns true for correction feedback" do
        feedback = build_stubbed(:pattern_feedback, feedback_type: "correction")
        expect(feedback.send(:correction_feedback?)).to be true
      end

      it "returns false for other feedback types" do
        %w[accepted rejected corrected].each do |type|
          feedback = build_stubbed(:pattern_feedback, feedback_type: type)
          expect(feedback.send(:correction_feedback?)).to be false
        end
      end
    end
  end

  describe "edge cases" do
    describe "pattern creation edge cases" do
      let(:category) { build_stubbed(:category) }
      let(:expense) { build_stubbed(:expense, merchant_name: "Test") }
      let(:feedback) { build_stubbed(:pattern_feedback, 
        feedback_type: "correction",
        category: category,
        expense: expense
      ) }

      it "handles pattern creation failures gracefully" do
        allow(feedback).to receive(:improvement_suggestion).and_return({
          pattern_type: "merchant",
          pattern_value: "Test"
        })

        expect(CategorizationPattern).to receive(:find_by).and_return(nil)
        expect(CategorizationPattern).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(build_stubbed(:categorization_pattern)))

        expect { feedback.send(:create_pattern_from_correction) }.to raise_error(ActiveRecord::RecordInvalid)
      end

      it "handles special characters in pattern values" do
        special_value = "Test & Co. #123"
        allow(feedback).to receive(:improvement_suggestion).and_return({
          pattern_type: "merchant",
          pattern_value: special_value
        })

        expect(CategorizationPattern).to receive(:find_by).with(
          hash_including(pattern_value: "test & co. #123")
        ).and_return(nil)

        expect(CategorizationPattern).to receive(:create!).with(
          hash_including(pattern_value: special_value)
        )

        feedback.send(:create_pattern_from_correction)
      end
    end

    describe "concurrent feedback handling" do
      it "handles multiple feedback records for same expense" do
        expense = build_stubbed(:expense, id: 1)
        category1 = build_stubbed(:category, id: 1)
        category2 = build_stubbed(:category, id: 2)

        feedback1 = build_stubbed(:pattern_feedback, expense: expense, category: category1)
        feedback2 = build_stubbed(:pattern_feedback, expense: expense, category: category2)

        expect(feedback1).to be_valid
        expect(feedback2).to be_valid
      end
    end

    describe "confidence score edge cases" do
      it "handles confidence score of exactly 0" do
        feedback = build_stubbed(:pattern_feedback, confidence_score: 0.0)
        expect(feedback).to be_valid
      end

      it "handles confidence score of exactly 1" do
        feedback = build_stubbed(:pattern_feedback, confidence_score: 1.0)
        expect(feedback).to be_valid
      end

      it "handles nil confidence score" do
        feedback = build_stubbed(:pattern_feedback, confidence_score: nil)
        expect(feedback).to be_valid
      end
    end
  end
end