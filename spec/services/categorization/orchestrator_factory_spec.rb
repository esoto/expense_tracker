# frozen_string_literal: true

require "rails_helper"

RSpec.describe Categorization::OrchestratorFactory, type: :service do
  describe ".create_production" do
    it "creates orchestrator with production services" do
      orchestrator = described_class.create_production

      expect(orchestrator).to be_a(Categorization::Orchestrator)
      expect(orchestrator.pattern_cache).to be_a(Categorization::PatternCache)
      expect(orchestrator.matcher).to be_a(Categorization::Matchers::FuzzyMatcher)
      expect(orchestrator.confidence_calculator).to be_a(Categorization::ConfidenceCalculator)
      expect(orchestrator.pattern_learner).to be_a(Categorization::PatternLearner)
      expect(orchestrator.performance_tracker).to be_a(Categorization::PerformanceTracker)
    end

    it "accepts custom services" do
      custom_cache = instance_double(Categorization::PatternCache)
      orchestrator = described_class.create_production(pattern_cache: custom_cache)

      expect(orchestrator.pattern_cache).to eq(custom_cache)
    end

    it "accepts custom logger" do
      custom_logger = Logger.new(STDOUT)
      orchestrator = described_class.create_production(logger: custom_logger)

      expect(orchestrator.logger).to eq(custom_logger)
    end
  end

  describe ".create_test" do
    it "creates orchestrator with test services" do
      orchestrator = described_class.create_test

      expect(orchestrator).to be_a(Categorization::Orchestrator)
      expect(orchestrator.pattern_cache).to be_a(Categorization::OrchestratorFactory::InMemoryPatternCache)
      expect(orchestrator.performance_tracker).to be_a(Categorization::OrchestratorFactory::NoOpPerformanceTracker)
    end

    it "uses simplified services for faster tests" do
      orchestrator = described_class.create_test

      # Test services should be lightweight
      expect(orchestrator.pattern_cache).to respond_to(:get_pattern)
      expect(orchestrator.matcher).to respond_to(:match_pattern)
      expect(orchestrator.confidence_calculator).to respond_to(:calculate)
    end
  end

  describe ".create_development" do
    it "creates orchestrator with development services" do
      orchestrator = described_class.create_development

      expect(orchestrator).to be_a(Categorization::Orchestrator)
      expect(orchestrator.pattern_cache).to be_a(Categorization::PatternCache)
      expect(orchestrator.performance_tracker).to be_a(Categorization::PerformanceTracker)
    end

    it "configures services for debugging" do
      orchestrator = described_class.create_development

      # Development services should have debugging features
      expect(orchestrator.pattern_cache).to be_a(Categorization::PatternCache)
      expect(orchestrator.matcher).to be_a(Categorization::Matchers::FuzzyMatcher)
    end
  end

  describe ".create_custom" do
    it "creates orchestrator with provided services" do
      custom_services = {
        pattern_cache: instance_double(Categorization::PatternCache),
        matcher: instance_double(Categorization::Matchers::FuzzyMatcher),
        confidence_calculator: instance_double(Categorization::ConfidenceCalculator),
        pattern_learner: instance_double(Categorization::PatternLearner),
        performance_tracker: instance_double(Categorization::PerformanceTracker)
      }

      orchestrator = described_class.create_custom(custom_services)

      expect(orchestrator.pattern_cache).to eq(custom_services[:pattern_cache])
      expect(orchestrator.matcher).to eq(custom_services[:matcher])
      expect(orchestrator.confidence_calculator).to eq(custom_services[:confidence_calculator])
      expect(orchestrator.pattern_learner).to eq(custom_services[:pattern_learner])
      expect(orchestrator.performance_tracker).to eq(custom_services[:performance_tracker])
    end

    it "creates default services for missing ones" do
      orchestrator = described_class.create_custom({})

      expect(orchestrator.pattern_cache).to be_a(Categorization::PatternCache)
      expect(orchestrator.matcher).to be_a(Categorization::Matchers::FuzzyMatcher)
    end
  end

  describe ".create_minimal" do
    it "creates orchestrator with minimal services" do
      orchestrator = described_class.create_minimal

      expect(orchestrator).to be_a(Categorization::Orchestrator)
      expect(orchestrator.pattern_cache).to be_a(Categorization::OrchestratorFactory::InMemoryPatternCache)
      expect(orchestrator.matcher).to be_a(Categorization::OrchestratorFactory::SimpleMatcher)
      expect(orchestrator.confidence_calculator).to be_a(Categorization::OrchestratorFactory::SimpleConfidenceCalculator)
      expect(orchestrator.pattern_learner).to be_a(Categorization::OrchestratorFactory::NoOpPatternLearner)
      expect(orchestrator.performance_tracker).to be_a(Categorization::OrchestratorFactory::NoOpPerformanceTracker)
    end
  end

  describe "Test Services" do
    describe "InMemoryPatternCache" do
      let(:cache) { described_class::InMemoryPatternCache.new(max_size: 10) }

      it "implements pattern cache interface" do
        expect(cache).to respond_to(:get_pattern)
        expect(cache).to respond_to(:get_patterns_for_expense)
        expect(cache).to respond_to(:get_user_preference)
        expect(cache).to respond_to(:preload_for_texts)
        expect(cache).to respond_to(:invalidate_category)
        expect(cache).to respond_to(:metrics)
        expect(cache).to respond_to(:healthy?)
        expect(cache).to respond_to(:reset!)
      end

      it "stores patterns in memory" do
        pattern = create(:categorization_pattern)
        allow(CategorizationPattern).to receive(:find_by).and_return(pattern)

        result = cache.get_pattern(pattern.id)
        expect(result).to eq(pattern)
      end

      it "reports health based on size" do
        expect(cache).to be_healthy
      end

      it "provides metrics" do
        metrics = cache.metrics
        expect(metrics).to include(cache_size: 0, max_size: 10)
      end
    end

    describe "SimpleMatcher" do
      let(:matcher) { described_class::SimpleMatcher.new }

      it "implements matcher interface" do
        expect(matcher).to respond_to(:match_pattern)
        expect(matcher).to respond_to(:clear_cache)
        expect(matcher).to respond_to(:metrics)
        expect(matcher).to respond_to(:healthy?)
      end

      it "performs simple text matching" do
        pattern = create(:categorization_pattern, pattern_value: "food")
        result = matcher.match_pattern("Whole Foods Market", [ pattern ])

        expect(result).to be_success
        expect(result.matches).to be_an(Array)
        expect(result.matches.first[:pattern]).to eq(pattern)
        expect(result.matches.first[:score]).to eq(0.8)
      end
    end

    describe "SimpleConfidenceCalculator" do
      let(:calculator) { described_class::SimpleConfidenceCalculator.new }

      it "implements confidence calculator interface" do
        expect(calculator).to respond_to(:calculate)
        expect(calculator).to respond_to(:metrics)
        expect(calculator).to respond_to(:healthy?)
      end

      it "calculates simple confidence score" do
        expense = create(:expense)
        pattern = create(:categorization_pattern)

        result = calculator.calculate(expense, pattern, 0.9)

        expect(result.score).to eq(0.81) # 0.9 * 0.9
        expect(result.factor_breakdown).to include(:text_match, :pattern_quality)
      end
    end

    describe "NoOpPatternLearner" do
      let(:learner) { described_class::NoOpPatternLearner.new }

      it "implements pattern learner interface" do
        expect(learner).to respond_to(:learn_from_correction)
        expect(learner).to respond_to(:metrics)
        expect(learner).to respond_to(:healthy?)
      end

      it "returns disabled message" do
        result = learner.learn_from_correction(nil, nil, nil)

        expect(result).to be_failure
        expect(result.message).to eq("Learning disabled")
      end
    end

    describe "NoOpPerformanceTracker" do
      let(:tracker) { described_class::NoOpPerformanceTracker.new }

      it "implements performance tracker interface" do
        expect(tracker).to respond_to(:track_operation)
        expect(tracker).to respond_to(:reset!)
        expect(tracker).to respond_to(:metrics)
        expect(tracker).to respond_to(:healthy?)
      end

      it "passes through operations without tracking" do
        result = tracker.track_operation("test") { "result" }
        expect(result).to eq("result")
      end
    end
  end

  describe "Integration" do
    it "creates working orchestrator for each environment" do
      [ :production, :test, :development, :minimal ].each do |env|
        orchestrator = case env
        when :production then described_class.create_production
        when :test then described_class.create_test
        when :development then described_class.create_development
        when :minimal then described_class.create_minimal
        end

        expense = create(:expense, merchant_name: "Test Store")
        result = orchestrator.categorize(expense)

        expect(result).to be_a(Categorization::CategorizationResult)
      end
    end
  end
end
