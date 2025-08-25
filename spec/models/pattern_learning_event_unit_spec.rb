# frozen_string_literal: true

require "rails_helper"

RSpec.describe PatternLearningEvent, type: :model, unit: true do
  describe "associations" do
    it { should belong_to(:expense) }
    it { should belong_to(:category) }
  end

  describe "validations" do
    describe "pattern_used validation" do
      it { should validate_presence_of(:pattern_used) }

      it "accepts any non-empty string" do
        event = build_stubbed(:pattern_learning_event, pattern_used: "merchant:store_name")
        expect(event).to be_valid
      end

      it "rejects empty string" do
        event = build_stubbed(:pattern_learning_event, pattern_used: "")
        expect(event).not_to be_valid
      end
    end

    describe "was_correct validation" do
      it "accepts true value" do
        event = build_stubbed(:pattern_learning_event, was_correct: true)
        expect(event).to be_valid
      end

      it "accepts false value" do
        event = build_stubbed(:pattern_learning_event, was_correct: false)
        expect(event).to be_valid
      end

      it "rejects nil value" do
        event = build_stubbed(:pattern_learning_event, was_correct: nil)
        expect(event).not_to be_valid
        expect(event.errors[:was_correct]).to include("is not included in the list")
      end
    end

    describe "confidence_score validation" do
      it { should validate_numericality_of(:confidence_score)
        .is_greater_than_or_equal_to(0.0)
        .is_less_than_or_equal_to(1.0)
        .allow_nil }

      it "accepts nil confidence score" do
        event = build_stubbed(:pattern_learning_event, confidence_score: nil)
        expect(event).to be_valid
      end

      it "accepts 0.0 confidence score" do
        event = build_stubbed(:pattern_learning_event, confidence_score: 0.0)
        expect(event).to be_valid
      end

      it "accepts 1.0 confidence score" do
        event = build_stubbed(:pattern_learning_event, confidence_score: 1.0)
        expect(event).to be_valid
      end

      it "accepts middle values" do
        event = build_stubbed(:pattern_learning_event, confidence_score: 0.75)
        expect(event).to be_valid
      end

      it "rejects values below 0" do
        event = build_stubbed(:pattern_learning_event, confidence_score: -0.1)
        expect(event).not_to be_valid
      end

      it "rejects values above 1" do
        event = build_stubbed(:pattern_learning_event, confidence_score: 1.1)
        expect(event).not_to be_valid
      end
    end
  end

  describe "scopes" do
    describe ".successful" do
    end

    describe ".unsuccessful" do
    end

    describe ".recent" do
    end
  end

  describe "callbacks" do
    describe "after_commit :invalidate_analytics_cache" do
      it "invalidates pattern analytics cache" do
        event = build_stubbed(:pattern_learning_event)
        cache = double("cache")
        
        allow(Rails).to receive(:cache).and_return(cache)
        expect(cache).to receive(:respond_to?).with(:delete_matched).and_return(true)
        expect(cache).to receive(:delete_matched).with("pattern_analytics/*")
        
        event.send(:invalidate_analytics_cache)
      end

      it "handles cache without delete_matched method" do
        event = build_stubbed(:pattern_learning_event)
        cache = double("cache")
        
        allow(Rails).to receive(:cache).and_return(cache)
        expect(cache).to receive(:respond_to?).with(:delete_matched).and_return(false)
        expect(cache).not_to receive(:delete_matched)
        
        event.send(:invalidate_analytics_cache)
      end

      it "handles cache invalidation errors gracefully" do
        event = build_stubbed(:pattern_learning_event)
        cache = double("cache")
        
        allow(Rails).to receive(:cache).and_return(cache)
        expect(cache).to receive(:respond_to?).with(:delete_matched).and_return(true)
        expect(cache).to receive(:delete_matched).and_raise(StandardError.new("Cache error"))
        expect(Rails.logger).to receive(:error).with(match(/Analytics cache invalidation failed/))
        
        expect { event.send(:invalidate_analytics_cache) }.not_to raise_error
      end
    end
  end

  describe "class methods" do
    describe ".record_event" do
      let(:expense) { build_stubbed(:expense, id: 1) }
      let(:category) { build_stubbed(:category, id: 2) }

      context "with CategorizationPattern" do
        it "creates event with pattern details" do
          pattern = build_stubbed(:categorization_pattern, 
            id: 10,
            pattern_type: "merchant",
            pattern_value: "Store Name"
          )

          expect(PatternLearningEvent).to receive(:create!).with(
            expense: expense,
            category: category,
            pattern_used: "merchant:Store Name",
            was_correct: true,
            confidence_score: 0.85,
            context_data: {
              pattern_id: 10,
              pattern_class: "CategorizationPattern"
            }
          )

          PatternLearningEvent.record_event(
            expense: expense,
            category: category,
            pattern: pattern,
            was_correct: true,
            confidence: 0.85
          )
        end
      end




      context "with custom object pattern" do
        it "creates event using to_s method" do
          custom_pattern = double("CustomPattern",
            id: 30,
            to_s: "CustomPattern#30",
            class: double(name: "CustomPattern")
          )

          expect(PatternLearningEvent).to receive(:create!).with(
            expense: expense,
            category: category,
            pattern_used: "CustomPattern#30",
            was_correct: true,
            confidence_score: 0.95,
            context_data: {
              pattern_id: 30,
              pattern_class: "CustomPattern"
            }
          )

          PatternLearningEvent.record_event(
            expense: expense,
            category: category,
            pattern: custom_pattern,
            was_correct: true,
            confidence: 0.95
          )
        end
      end

      it "handles nil confidence" do
        pattern = build_stubbed(:categorization_pattern, pattern_type: "merchant", pattern_value: "Store")

        expect(PatternLearningEvent).to receive(:create!).with(
          hash_including(confidence_score: nil)
        )

        PatternLearningEvent.record_event(
          expense: expense,
          category: category,
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
        event = build_stubbed(:pattern_learning_event, was_correct: true)
        expect(event.successful?).to be true
      end

      it "returns false when was_correct is false" do
        event = build_stubbed(:pattern_learning_event, was_correct: false)
        expect(event.successful?).to be false
      end

      it "returns false when was_correct is nil (though this shouldn't happen due to validation)" do
        event = build_stubbed(:pattern_learning_event)
        allow(event).to receive(:was_correct).and_return(nil)
        expect(event.successful?).to be false
      end
    end
  end

  describe "edge cases" do
    describe "pattern_used string handling" do
      it "handles very long pattern descriptions" do
        long_pattern = "a" * 1000
        event = build_stubbed(:pattern_learning_event, pattern_used: long_pattern)
        expect(event).to be_valid
        expect(event.pattern_used.length).to eq(1000)
      end

      it "handles special characters in pattern_used" do
        special_pattern = "merchant:Store & Co. #123 @ Location"
        event = build_stubbed(:pattern_learning_event, pattern_used: special_pattern)
        expect(event).to be_valid
      end

      it "handles unicode characters in pattern_used" do
        unicode_pattern = "merchant:Café ñ 中文"
        event = build_stubbed(:pattern_learning_event, pattern_used: unicode_pattern)
        expect(event).to be_valid
      end
    end

    describe "context_data handling" do

      it "handles nil context_data" do
        event = build_stubbed(:pattern_learning_event, context_data: nil)
        expect(event).to be_valid
      end

      it "handles empty context_data" do
        event = build_stubbed(:pattern_learning_event, context_data: {})
        expect(event).to be_valid
      end
    end

    describe "confidence score precision" do
      it "handles very precise confidence scores" do
        event = build_stubbed(:pattern_learning_event, confidence_score: 0.123456789)
        expect(event).to be_valid
        expect(event.confidence_score).to eq(0.123456789)
      end

      it "handles scientific notation confidence scores" do
        event = build_stubbed(:pattern_learning_event, confidence_score: 1e-10)
        expect(event).to be_valid
      end
    end

    describe "concurrent event recording" do
      it "handles multiple events for same expense" do
        expense = build_stubbed(:expense, id: 1)
        category1 = build_stubbed(:category, id: 1)
        category2 = build_stubbed(:category, id: 2)

        event1 = build_stubbed(:pattern_learning_event, 
          expense: expense, 
          category: category1,
          pattern_used: "pattern1"
        )
        event2 = build_stubbed(:pattern_learning_event, 
          expense: expense, 
          category: category2,
          pattern_used: "pattern2"
        )

        expect(event1).to be_valid
        expect(event2).to be_valid
      end

      it "handles events with same pattern but different outcomes" do
        expense1 = build_stubbed(:expense, id: 1)
        expense2 = build_stubbed(:expense, id: 2)
        category = build_stubbed(:category, id: 1)

        event1 = build_stubbed(:pattern_learning_event,
          expense: expense1,
          category: category,
          pattern_used: "merchant:Store",
          was_correct: true
        )
        event2 = build_stubbed(:pattern_learning_event,
          expense: expense2,
          category: category,
          pattern_used: "merchant:Store",
          was_correct: false
        )

        expect(event1).to be_valid
        expect(event2).to be_valid
      end
    end

    describe "pattern type variations" do
      let(:expense) { build_stubbed(:expense) }
      let(:category) { build_stubbed(:category) }


    end
  end
end