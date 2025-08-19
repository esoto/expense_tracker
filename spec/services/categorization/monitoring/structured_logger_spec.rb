# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe Categorization::Monitoring::StructuredLogger, performance: true do
  let(:mock_logger) { instance_double(Logger) }
  let(:structured_logger) { described_class.new(logger: mock_logger) }

  describe "#log_categorization", performance: true do
    let(:expense) { create(:expense, description: "Test purchase at Store") }
    let(:category) { create(:category, name: "Shopping") }
    let(:result) do
      OpenStruct.new(
        category_id: category.id,
        category: category,
        confidence: 0.85,
        method: "pattern_matching",
        metadata: { processing_time_ms: 5.2 }
      )
    end

    it "logs categorization events in JSON format" do
      expect(mock_logger).to receive(:add).with(
        Logger::INFO,
        a_string_matching(/"event":"categorization.completed"/)
      )

      structured_logger.log_categorization(
        event_type: "completed",
        expense: expense,
        result: result
      )
    end

    it "includes correlation ID in logs" do
      expect(mock_logger).to receive(:add).with(
        Logger::INFO,
        a_string_matching(/"correlation_id":"cat_[a-f0-9]{16}"/)
      )

      structured_logger.log_categorization(
        event_type: "started",
        expense: expense,
        result: nil
      )
    end

    it "sanitizes sensitive data" do
      expense.update!(description: "Purchase at store@example.com with 4111-1111-1111-1111")

      expect(mock_logger).to receive(:add).with(
        Logger::INFO,
        a_string_matching(/\[EMAIL\].*\[CARD\]/)
      )

      structured_logger.log_categorization(
        event_type: "completed",
        expense: expense,
        result: result
      )
    end
  end

  describe "#log_learning", performance: true do
    let(:pattern) { create(:categorization_pattern) }

    it "logs learning events with changes" do
      expect(mock_logger).to receive(:add).with(
        Logger::INFO,
        a_string_matching(/"event":"learning.pattern_updated"/)
      )

      structured_logger.log_learning(
        action: "pattern_updated",
        pattern: pattern,
        changes: {
          confidence_before: 0.7,
          confidence_after: 0.75,
          confidence_change: 0.05
        }
      )
    end
  end

  describe "#log_error", performance: true do
    let(:error) { StandardError.new("Test error message") }

    before do
      error.set_backtrace([
        "#{Rails.root}/app/services/test.rb:10:in `method'",
        "/usr/lib/ruby/test.rb:20:in `other_method'",
        "#{Rails.root}/app/controllers/test.rb:30:in `action'"
      ])
    end

    it "logs errors with context" do
      expect(mock_logger).to receive(:add).with(
        Logger::ERROR,
        a_string_matching(/"event":"error.standard_error".*"error_message":"Test error message"/)
      )

      structured_logger.log_error(
        error: error,
        context: { expense_id: 123 }
      )
    end

    it "cleans backtrace to show only app lines" do
      expect(mock_logger).to receive(:add).with(
        Logger::ERROR,
        a_string_matching(/\[APP_ROOT\]/)
      )

      structured_logger.log_error(error: error)
    end
  end

  describe "#with_correlation_id", performance: true do
    it "uses provided correlation ID for all logs in block" do
      correlation_id = "test_correlation_123"

      expect(mock_logger).to receive(:add).exactly(2).times.with(
        anything,
        a_string_matching(/"correlation_id":"#{correlation_id}"/)
      )

      structured_logger.with_correlation_id(correlation_id) do |logger|
        logger.log(level: :info, message: "First log")
        logger.log(level: :info, message: "Second log")
      end
    end

    it "restores original correlation ID after block" do
      original_correlation_id = structured_logger.instance_variable_get(:@correlation_id)

      structured_logger.with_correlation_id("temp_id") do |logger|
        # Inside block
      end

      expect(structured_logger.instance_variable_get(:@correlation_id)).to eq(original_correlation_id)
    end
  end

  describe "#with_context", performance: true do
    it "adds context to logs within block" do
      expect(mock_logger).to receive(:add).with(
        Logger::INFO,
        a_string_matching(/"user_id":123.*"request_id":"req_456"/)
      )

      structured_logger.with_context(user_id: 123, request_id: "req_456") do |logger|
        logger.log(level: :info, message: "Test message")
      end
    end

    it "restores original context after block" do
      original_context = structured_logger.context.dup

      structured_logger.with_context(temp_key: "temp_value") do |logger|
        # Inside block
      end

      expect(structured_logger.context).to eq(original_context)
    end
  end

  describe "#child", performance: true do
    it "creates child logger with inherited context" do
      parent = described_class.new(logger: mock_logger, context: { parent_key: "parent_value" })
      child = parent.child(child_key: "child_value")

      expect(child.context).to include(
        parent_key: "parent_value",
        child_key: "child_value"
      )
    end

    it "inherits correlation ID from parent" do
      parent = described_class.new(logger: mock_logger)
      parent_correlation_id = parent.instance_variable_get(:@correlation_id)

      child = parent.child

      expect(child.instance_variable_get(:@correlation_id)).to eq(parent_correlation_id)
    end
  end

  describe "class methods", performance: true do
    it "provides convenience class methods" do
      expect(described_class).to respond_to(:log_categorization)
      expect(described_class).to respond_to(:log_learning)
      expect(described_class).to respond_to(:log_error)
      expect(described_class).to respond_to(:log_performance)
      expect(described_class).to respond_to(:log_cache)
    end
  end
end
