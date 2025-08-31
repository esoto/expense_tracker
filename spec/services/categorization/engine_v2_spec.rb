# frozen_string_literal: true

require "rails_helper"

RSpec.describe Categorization::EngineV2, type: :service, unit: true do
  let(:engine) { described_class.new(logger: logger) }
  let(:logger) { instance_double(Logger) }
  let(:orchestrator) { instance_double(Categorization::Orchestrator) }
  let(:orchestrator_factory) { class_double(Categorization::OrchestratorFactory) }

  # Test data
  let(:expense) { build(:expense, merchant_name: "Test Merchant", amount: 100.00) }
  let(:category) { build(:category, name: "Test Category") }
  let(:successful_result) do
    instance_double(Categorization::CategorizationResult, successful?: true)
  end
  let(:error_result) do
    instance_double(Categorization::CategorizationResult, successful?: false)
  end

  before do
    # Mock Rails.env
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))

    # Mock Rails.logger
    allow(Rails).to receive(:logger).and_return(logger)

    # Mock logger methods
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)

    # Mock OrchestratorFactory
    stub_const("Categorization::OrchestratorFactory", orchestrator_factory)
    allow(orchestrator_factory).to receive(:create_test).and_return(orchestrator)
    allow(orchestrator_factory).to receive(:create_development).and_return(orchestrator)
    allow(orchestrator_factory).to receive(:create_production).and_return(orchestrator)

    # Mock orchestrator methods
    allow(orchestrator).to receive(:categorize).and_return(successful_result)
    allow(orchestrator).to receive(:batch_categorize).and_return([ successful_result ])
    allow(orchestrator).to receive(:learn_from_correction).and_return(
      Categorization::LearningResult.success(patterns_created: 1)
    )
    allow(orchestrator).to receive(:metrics).and_return({})
    allow(orchestrator).to receive(:healthy?).and_return(true)
    allow(orchestrator).to receive(:reset!)

    # Mock CategorizationResult.error and LearningResult.error class methods
    allow(Categorization::CategorizationResult).to receive(:error) do |msg|
      Categorization::CategorizationResult.new(error: msg, method: "error")
    end
    allow(Categorization::LearningResult).to receive(:error) do |msg|
      Categorization::LearningResult.new(success: false, message: msg)
    end
  end

  describe ".create" do
    it "creates a new instance with options" do
      custom_logger = instance_double(Logger)
      allow(custom_logger).to receive(:info)

      engine = described_class.create(logger: custom_logger)

      expect(engine).to be_a(described_class)
      expect(engine.logger).to eq(custom_logger)
    end

    it "creates a new instance without options" do
      engine = described_class.create

      expect(engine).to be_a(described_class)
      expect(engine.logger).to eq(logger)
    end
  end

  describe "#initialize" do
    context "with custom logger" do
      let(:custom_logger) { instance_double(Logger) }

      before do
        allow(custom_logger).to receive(:info)
      end

      it "uses the provided logger" do
        engine = described_class.new(logger: custom_logger)
        expect(engine.logger).to eq(custom_logger)
      end

      it "logs initialization message" do
        expect(custom_logger).to receive(:info).with("[EngineV2] Initialized with clean orchestrator pattern")
        described_class.new(logger: custom_logger)
      end
    end

    context "without custom logger" do
      it "uses Rails.logger as default" do
        engine = described_class.new
        expect(engine.logger).to eq(logger)
      end
    end

    context "orchestrator creation" do
      it "creates test orchestrator in test environment" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))
        expect(orchestrator_factory).to receive(:create_test).with({ logger: logger })

        described_class.new(logger: logger)
      end

      it "creates development orchestrator in development environment" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        expect(orchestrator_factory).to receive(:create_development).with({ logger: logger })

        described_class.new(logger: logger)
      end

      it "creates production orchestrator in production environment" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        expect(orchestrator_factory).to receive(:create_production).with({ logger: logger })

        described_class.new(logger: logger)
      end
    end

    it "initializes metrics" do
      expect(engine.metrics[:engine][:total_categorizations]).to eq(0)
      expect(engine.metrics[:engine][:successful_categorizations]).to eq(0)
    end

    it "initializes shutdown state as false" do
      expect(engine.shutdown?).to be false
    end
  end

  describe "#categorize" do
    context "when not shutdown" do
      it "delegates to orchestrator and tracks metrics for successful result" do
        expect(orchestrator).to receive(:categorize).with(expense, {}).and_return(successful_result)

        result = engine.categorize(expense)

        expect(result).to eq(successful_result)
        expect(engine.metrics[:engine][:total_categorizations]).to eq(1)
        expect(engine.metrics[:engine][:successful_categorizations]).to eq(1)
        expect(engine.metrics[:engine][:success_rate]).to eq(100.0)
      end

      it "delegates to orchestrator and tracks metrics for unsuccessful result" do
        unsuccessful_result = instance_double(Categorization::CategorizationResult, successful?: false)
        allow(orchestrator).to receive(:categorize).and_return(unsuccessful_result)

        result = engine.categorize(expense)

        expect(result).to eq(unsuccessful_result)
        expect(engine.metrics[:engine][:total_categorizations]).to eq(1)
        expect(engine.metrics[:engine][:successful_categorizations]).to eq(0)
        expect(engine.metrics[:engine][:success_rate]).to eq(0.0)
      end

      it "passes options to orchestrator" do
        options = { force_match: true }
        expect(orchestrator).to receive(:categorize).with(expense, options)

        engine.categorize(expense, options)
      end

      it "handles orchestrator errors" do
        allow(orchestrator).to receive(:categorize).and_raise(StandardError, "Orchestrator error")

        expect(logger).to receive(:error).with("[EngineV2] Categorization failed: Orchestrator error")
        expect(Categorization::CategorizationResult).to receive(:error).with("Categorization failed")

        result = engine.categorize(expense)

        # Metrics are still incremented even on error (track_metrics is called before the error)
        expect(engine.metrics[:engine][:total_categorizations]).to eq(1)
        expect(engine.metrics[:engine][:successful_categorizations]).to eq(0)
      end
    end

    context "when shutdown" do
      before do
        engine.shutdown!
      end

      it "returns error result without calling orchestrator" do
        expect(orchestrator).not_to receive(:categorize)
        expect(Categorization::CategorizationResult).to receive(:error).with("Service shutdown")

        engine.categorize(expense)
      end

      it "does not track metrics" do
        engine.categorize(expense)

        expect(engine.metrics[:engine][:total_categorizations]).to eq(0)
        expect(engine.metrics[:engine][:successful_categorizations]).to eq(0)
      end
    end
  end

  describe "#batch_categorize" do
    let(:expenses) { [ expense, build(:expense) ] }
    let(:results) { [ successful_result, successful_result ] }

    context "when not shutdown" do
      it "returns empty array for blank expenses" do
        expect(orchestrator).not_to receive(:batch_categorize)

        expect(engine.batch_categorize(nil)).to eq([])
        expect(engine.batch_categorize([])).to eq([])
      end

      it "delegates to orchestrator for valid batch" do
        expect(orchestrator).to receive(:batch_categorize).with(expenses, {}).and_return(results)

        result = engine.batch_categorize(expenses)

        expect(result).to eq(results)
      end

      it "passes options to orchestrator" do
        options = { parallel: true }
        expect(orchestrator).to receive(:batch_categorize).with(expenses, options)

        engine.batch_categorize(expenses, options)
      end

      it "enforces batch size limit" do
        large_batch = Array.new(1500) { build(:expense) }
        limited_batch = large_batch.first(1000)

        expect(logger).to receive(:warn).with("[EngineV2] Batch size 1500 exceeds limit, processing first 1000")
        expect(orchestrator).to receive(:batch_categorize).with(limited_batch, {})

        engine.batch_categorize(large_batch)
      end

      it "handles orchestrator errors" do
        allow(orchestrator).to receive(:batch_categorize).and_raise(StandardError, "Batch error")

        expect(logger).to receive(:error).with("[EngineV2] Batch categorization failed: Batch error")

        result = engine.batch_categorize(expenses)

        expect(result.size).to eq(2)
        result.each do |r|
          expect(r.error).to eq("Batch processing failed")
        end
      end
    end

    context "when shutdown" do
      before do
        engine.shutdown!
      end

      it "returns error results without calling orchestrator" do
        expect(orchestrator).not_to receive(:batch_categorize)

        result = engine.batch_categorize(expenses)

        expect(result.size).to eq(2)
        result.each do |r|
          expect(r.error).to eq("Service shutdown")
        end
      end

      it "returns empty array for blank expenses" do
        expect(engine.batch_categorize([])).to eq([])
      end
    end
  end

  describe "#learn_from_correction" do
    let(:correct_category) { category }
    let(:predicted_category) { build(:category, name: "Wrong Category") }
    let(:learning_result) { instance_double(Categorization::LearningResult, success?: true) }

    context "when not shutdown" do
      it "delegates to orchestrator with all parameters" do
        options = { update_patterns: true }
        expect(orchestrator).to receive(:learn_from_correction).with(
          expense, correct_category, predicted_category, options
        ).and_return(learning_result)

        result = engine.learn_from_correction(expense, correct_category, predicted_category, options)

        expect(result).to eq(learning_result)
      end

      it "delegates to orchestrator without predicted category" do
        expect(orchestrator).to receive(:learn_from_correction).with(
          expense, correct_category, nil, {}
        ).and_return(learning_result)

        result = engine.learn_from_correction(expense, correct_category)

        expect(result).to eq(learning_result)
      end

      it "handles orchestrator errors" do
        allow(orchestrator).to receive(:learn_from_correction).and_raise(StandardError, "Learning error")

        expect(logger).to receive(:error).with("[EngineV2] Learning failed: Learning error")
        expect(Categorization::LearningResult).to receive(:error).with("Learning failed")

        engine.learn_from_correction(expense, correct_category)
      end
    end

    context "when shutdown" do
      before do
        engine.shutdown!
      end

      it "returns error result without calling orchestrator" do
        expect(orchestrator).not_to receive(:learn_from_correction)
        expect(Categorization::LearningResult).to receive(:error).with("Service shutdown")

        engine.learn_from_correction(expense, correct_category)
      end
    end
  end

  describe "#warm_up" do
    context "when not shutdown" do
      context "with successful pattern loading" do
        let(:patterns) { double("patterns") }

        before do
          allow(CategorizationPattern).to receive(:active).and_return(patterns)
          allow(patterns).to receive(:joins).with(:category).and_return(patterns)
          allow(patterns).to receive(:where).with("usage_count > ?", 10).and_return(patterns)
          allow(patterns).to receive(:order).with(usage_count: :desc).and_return(patterns)
          allow(patterns).to receive(:limit).with(100).and_return(patterns)
          allow(patterns).to receive(:count).and_return(42)
        end

        it "warms pattern cache and returns success status" do
          expect(logger).to receive(:info).with("[EngineV2] Starting warm-up...")
          expect(logger).to receive(:info).with("[EngineV2] Warm-up completed")

          result = engine.warm_up

          expect(result).to eq({
            patterns: 42,
            status: :ready
          })
        end
      end

      context "with database error" do
        before do
          allow(CategorizationPattern).to receive(:active).and_raise(ActiveRecord::RecordNotFound, "DB error")
        end

        it "handles errors and returns failed status" do
          expect(logger).to receive(:info).with("[EngineV2] Starting warm-up...")
          expect(logger).to receive(:error).with("[EngineV2] Warm-up failed: DB error")

          result = engine.warm_up

          expect(result).to eq({
            status: :failed,
            error: "DB error"
          })
        end
      end
    end

    context "when shutdown" do
      before do
        engine.shutdown!
      end

      it "returns shutdown status without warming cache" do
        expect(logger).not_to receive(:info)

        result = engine.warm_up

        expect(result).to eq({ status: :shutdown })
      end
    end
  end

  describe "#metrics" do
    before do
      allow(orchestrator).to receive(:metrics).and_return({
        total_categorizations: 100,
        cache_hits: 50
      })
    end

    it "returns combined engine and orchestrator metrics" do
      # Perform some operations to populate metrics
      allow(orchestrator).to receive(:categorize).and_return(successful_result, error_result)
      engine.categorize(expense)
      engine.categorize(expense)

      metrics = engine.metrics

      expect(metrics).to eq({
        engine: {
          total_categorizations: 2,
          successful_categorizations: 1,
          success_rate: 50.0,
          shutdown: false
        },
        orchestrator: {
          total_categorizations: 100,
          cache_hits: 50
        }
      })
    end

    it "calculates zero success rate when no categorizations" do
      metrics = engine.metrics

      expect(metrics[:engine][:success_rate]).to eq(0.0)
    end

    it "reflects shutdown state in metrics" do
      engine.shutdown!
      metrics = engine.metrics

      expect(metrics[:engine][:shutdown]).to be true
    end
  end

  describe "#healthy?" do
    context "when not shutdown" do
      it "returns true when orchestrator is healthy" do
        allow(orchestrator).to receive(:healthy?).and_return(true)

        expect(engine.healthy?).to be true
      end

      it "returns false when orchestrator is unhealthy" do
        allow(orchestrator).to receive(:healthy?).and_return(false)

        expect(engine.healthy?).to be false
      end
    end

    context "when shutdown" do
      before do
        engine.shutdown!
      end

      it "returns false regardless of orchestrator health" do
        allow(orchestrator).to receive(:healthy?).and_return(true)

        expect(engine.healthy?).to be false
      end
    end
  end

  describe "#reset!" do
    context "when not shutdown" do
      before do
        # Populate metrics
        allow(orchestrator).to receive(:categorize).and_return(successful_result)
        engine.categorize(expense)
        engine.categorize(expense)
      end

      it "resets orchestrator and metrics" do
        expect(orchestrator).to receive(:reset!)
        expect(logger).to receive(:info).with("[EngineV2] Engine reset completed")

        engine.reset!

        expect(engine.metrics[:engine][:total_categorizations]).to eq(0)
        expect(engine.metrics[:engine][:successful_categorizations]).to eq(0)
      end
    end

    context "when shutdown" do
      before do
        engine.shutdown!
      end

      it "does nothing" do
        expect(orchestrator).not_to receive(:reset!)
        expect(logger).not_to receive(:info).with("[EngineV2] Engine reset completed")

        engine.reset!
      end
    end
  end

  describe "#shutdown!" do
    context "when not shutdown" do
      it "sets shutdown state and logs" do
        expect(logger).to receive(:info).with("[EngineV2] Shutting down...")
        expect(logger).to receive(:info).with("[EngineV2] Shutdown complete")

        expect(engine.shutdown?).to be false

        engine.shutdown!

        expect(engine.shutdown?).to be true
      end
    end

    context "when already shutdown" do
      before do
        allow(logger).to receive(:info)
        engine.shutdown!
      end

      it "is idempotent" do
        expect(logger).not_to receive(:info)

        engine.shutdown!

        expect(engine.shutdown?).to be true
      end
    end
  end

  describe "#shutdown?" do
    it "returns false initially" do
      expect(engine.shutdown?).to be false
    end

    it "returns true after shutdown" do
      engine.shutdown!
      expect(engine.shutdown?).to be true
    end
  end

  describe "error handling" do
    it "defines CategorizationError" do
      expect(Categorization::EngineV2::CategorizationError).to be < StandardError
    end

    it "defines ValidationError as subclass of CategorizationError" do
      expect(Categorization::EngineV2::ValidationError).to be < Categorization::EngineV2::CategorizationError
    end
  end

  describe "performance tracking" do
    it "tracks successful categorizations in metrics" do
      3.times { engine.categorize(expense) }

      metrics = engine.metrics[:engine]
      expect(metrics[:total_categorizations]).to eq(3)
      expect(metrics[:successful_categorizations]).to eq(3)
      expect(metrics[:success_rate]).to eq(100.0)
    end

    it "tracks mixed results in metrics" do
      allow(orchestrator).to receive(:categorize).and_return(
        successful_result,
        error_result,
        successful_result
      )

      3.times { engine.categorize(expense) }

      metrics = engine.metrics[:engine]
      expect(metrics[:total_categorizations]).to eq(3)
      expect(metrics[:successful_categorizations]).to eq(2)
      expect(metrics[:success_rate]).to eq(66.67)
    end
  end

  describe "constants" do
    it "defines PERFORMANCE_TARGET_MS" do
      expect(Categorization::EngineV2::PERFORMANCE_TARGET_MS).to eq(10.0)
    end

    it "defines BATCH_SIZE_LIMIT" do
      expect(Categorization::EngineV2::BATCH_SIZE_LIMIT).to eq(1000)
    end
  end

  describe "thread safety" do
    it "maintains separate shutdown state per instance" do
      engine1 = described_class.new(logger: logger)
      engine2 = described_class.new(logger: logger)

      engine1.shutdown!

      expect(engine1.shutdown?).to be true
      expect(engine2.shutdown?).to be false
    end

    it "maintains separate metrics per instance" do
      engine1 = described_class.new(logger: logger)
      engine2 = described_class.new(logger: logger)

      engine1.categorize(expense)

      expect(engine1.metrics[:engine][:total_categorizations]).to eq(1)
      expect(engine2.metrics[:engine][:total_categorizations]).to eq(0)
    end
  end
end
