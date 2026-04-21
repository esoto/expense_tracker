# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Learning::MetricsRecorder, type: :service, unit: true do
  let(:category) { create(:category) }
  let(:user)     { create(:user) }
  let(:expense)  { create(:expense, category: category, user: user) }
  let(:recorder) { described_class.new }

  describe "#record" do
    let(:result) do
      Services::Categorization::CategorizationResult.new(
        category: category,
        confidence: 0.85,
        patterns_used: [ "merchant:walmart" ],
        processing_time_ms: 5.2,
        method: "fuzzy_match"
      )
    end

    it "creates a categorization_metric row" do
      expect {
        recorder.record(expense: expense, result: result, layer_name: "pattern")
      }.to change(CategorizationMetric, :count).by(1)
    end

    it "stores the correct attributes and derives user from expense" do
      recorder.record(expense: expense, result: result, layer_name: "pattern")

      metric = CategorizationMetric.last
      expect(metric.expense).to eq(expense)
      expect(metric.user).to eq(user)
      expect(metric.layer_used).to eq("pattern")
      expect(metric.confidence).to eq(0.85)
      expect(metric.category).to eq(category)
      expect(metric.processing_time_ms).to eq(5.2)
      expect(metric.was_corrected).to be false
      expect(metric.api_cost).to eq(0)
    end

    it "stores api_cost when provided" do
      recorder.record(expense: expense, result: result, layer_name: "haiku", api_cost: 0.001)

      metric = CategorizationMetric.last
      expect(metric.api_cost).to eq(0.001)
    end

    it "handles no_match results gracefully" do
      no_match = Services::Categorization::CategorizationResult.no_match(processing_time_ms: 1.0)

      expect {
        recorder.record(expense: expense, result: no_match, layer_name: "pattern")
      }.to change(CategorizationMetric, :count).by(1)

      metric = CategorizationMetric.last
      expect(metric.category).to be_nil
      expect(metric.confidence).to be_nil
    end

    it "does not raise on database errors and logs the failure" do
      logger = instance_double(ActiveSupport::Logger)
      allow(logger).to receive(:error)
      recorder_with_logger = described_class.new(logger: logger)

      allow(CategorizationMetric).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect {
        recorder_with_logger.record(expense: expense, result: result, layer_name: "pattern")
      }.not_to raise_error

      expect(logger).to have_received(:error).with(/Failed to record metric/)
    end
  end

  describe "#record_correction" do
    let!(:metric) do
      CategorizationMetric.create!(
        expense: expense,
        user: user,
        layer_used: "pattern",
        confidence: 0.85,
        category: category,
        was_corrected: false,
        processing_time_ms: 5.0
      )
    end
    let(:new_category) { create(:category, name: "Corrected", i18n_key: "corrected_test") }

    it "updates the metric row" do
      recorder.record_correction(expense: expense, corrected_to_category: new_category)

      metric.reload
      expect(metric.was_corrected).to be true
      expect(metric.corrected_to_category).to eq(new_category)
      expect(metric.time_to_correction_hours).to be_present
    end

    it "calculates time_to_correction_hours correctly" do
      metric.update_columns(created_at: 48.hours.ago)

      recorder.record_correction(expense: expense, corrected_to_category: new_category)

      metric.reload
      expect(metric.time_to_correction_hours).to be_between(47, 49)
    end

    it "handles missing metric row gracefully without modifying anything" do
      other_user    = create(:user)
      other_expense = create(:expense, user: other_user)

      recorder.record_correction(expense: other_expense, corrected_to_category: new_category)

      expect(CategorizationMetric.where(was_corrected: true).count).to eq(0)
    end

    it "does not raise on correction errors and logs the failure" do
      logger = instance_double(ActiveSupport::Logger)
      allow(logger).to receive(:error)
      recorder_with_logger = described_class.new(logger: logger)

      allow_any_instance_of(CategorizationMetric).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

      expect {
        recorder_with_logger.record_correction(expense: expense, corrected_to_category: new_category)
      }.not_to raise_error

      expect(logger).to have_received(:error).with(/Failed to record correction/)
    end

    it "updates the most recent metric for the expense" do
      older_metric = CategorizationMetric.create!(
        expense: expense,
        user: user,
        layer_used: "pg_trgm",
        confidence: 0.7,
        category: category,
        was_corrected: false,
        processing_time_ms: 40.0,
        created_at: 2.days.ago
      )

      recorder.record_correction(expense: expense, corrected_to_category: new_category)

      # Should update the newer metric, not the older one
      metric.reload
      older_metric.reload
      expect(metric.was_corrected).to be true
      expect(older_metric.was_corrected).to be false
    end
  end
end
