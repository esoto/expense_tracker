# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Strategies::LlmStrategy, :unit do
  subject(:strategy) { described_class.new(client: mock_client, logger: logger) }

  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:mock_client) { instance_double(Services::Categorization::Llm::Client) }
  let(:category) { create(:category) }
  let(:expense) { create(:expense, merchant_name: "Automercado San Pedro", description: "groceries") }
  let(:normalized_merchant) { Services::Categorization::MerchantNormalizer.normalize(expense.merchant_name) }

  describe "#layer_name" do
    it "returns 'haiku'" do
      expect(strategy.layer_name).to eq("haiku")
    end
  end

  describe "BaseStrategy interface" do
    it "inherits from BaseStrategy" do
      expect(described_class.superclass).to eq(Services::Categorization::Strategies::BaseStrategy)
    end

    it "responds to #call" do
      expect(strategy).to respond_to(:call)
    end

    it "responds to #layer_name" do
      expect(strategy).to respond_to(:layer_name)
    end
  end

  describe "constants" do
    it "defines MONTHLY_BUDGET as 5.0" do
      expect(described_class::MONTHLY_BUDGET).to eq(5.0)
    end

    it "defines BUDGET_KEY_PREFIX" do
      expect(described_class::BUDGET_KEY_PREFIX).to eq("llm_budget")
    end
  end

  describe "#call" do
    context "when budget is exceeded" do
      before do
        budget_key = "llm_budget:#{Date.current.strftime('%Y-%m')}"
        Rails.cache.write(budget_key, 5.50, expires_in: 35.days)
      end

      it "returns no_match with budget_exceeded reason" do
        result = strategy.call(expense)

        expect(result).not_to be_successful
        expect(result.method).to eq("no_match")
        expect(result.metadata[:reason]).to eq("budget_exceeded")
        expect(result.processing_time_ms).to be > 0
      end

      it "does not call the LLM API" do
        allow(mock_client).to receive(:categorize)

        strategy.call(expense)

        expect(mock_client).not_to have_received(:categorize)
      end
    end

    context "when budget is exactly at the limit" do
      before do
        budget_key = "llm_budget:#{Date.current.strftime('%Y-%m')}"
        Rails.cache.write(budget_key, 5.0, expires_in: 35.days)
      end

      it "returns no_match with budget_exceeded reason" do
        result = strategy.call(expense)

        expect(result).not_to be_successful
        expect(result.metadata[:reason]).to eq("budget_exceeded")
      end
    end

    context "when budget is under the limit" do
      let(:prompt_text) { "categorize this merchant" }
      let(:api_response) do
        {
          response_text: category.i18n_key,
          token_count: { input: 80, output: 5 },
          cost: 0.0003
        }
      end

      before do
        budget_key = "llm_budget:#{Date.current.strftime('%Y-%m')}"
        Rails.cache.write(budget_key, 4.99, expires_in: 35.days)

        allow(Services::Categorization::Llm::PromptBuilder).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::PromptBuilder, build: prompt_text))
        allow(mock_client).to receive(:categorize).with(prompt_text: prompt_text).and_return(api_response)
        allow(Services::Categorization::Llm::ResponseParser).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::ResponseParser,
            parse: { category: category, confidence: 0.85, raw_response: category.i18n_key }))
      end

      it "proceeds with the LLM call" do
        result = strategy.call(expense)

        expect(result).to be_successful
        expect(mock_client).to have_received(:categorize)
      end

      it "increments the budget counter by the call cost" do
        strategy.call(expense)

        budget_key = "llm_budget:#{Date.current.strftime('%Y-%m')}"
        expect(Rails.cache.read(budget_key)).to be_within(0.0001).of(4.9903)
      end
    end

    context "budget counter initialization" do
      let(:prompt_text) { "categorize this merchant" }
      let(:api_response) do
        {
          response_text: category.i18n_key,
          token_count: { input: 80, output: 5 },
          cost: 0.0005
        }
      end

      before do
        allow(Services::Categorization::Llm::PromptBuilder).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::PromptBuilder, build: prompt_text))
        allow(mock_client).to receive(:categorize).with(prompt_text: prompt_text).and_return(api_response)
        allow(Services::Categorization::Llm::ResponseParser).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::ResponseParser,
            parse: { category: category, confidence: 0.85, raw_response: category.i18n_key }))
      end

      it "initializes the counter from zero when no prior spend exists" do
        budget_key = "llm_budget:#{Date.current.strftime('%Y-%m')}"
        Rails.cache.delete(budget_key)

        strategy.call(expense)

        expect(Rails.cache.read(budget_key)).to be_within(0.0001).of(0.0005)
      end
    end
    context "when expense has no merchant_name" do
      let(:expense) { create(:expense, merchant_name: nil, description: "some payment") }

      it "returns no_match without calling the API" do
        result = strategy.call(expense)

        expect(result).not_to be_successful
        expect(result.method).to eq("no_match")
        expect(mock_client).not_to have_received(:categorize) if mock_client.respond_to?(:categorize)
      end
    end

    context "when expense has blank merchant_name" do
      let(:expense) { create(:expense, merchant_name: "", description: "some payment") }

      it "returns no_match" do
        result = strategy.call(expense)

        expect(result).not_to be_successful
        expect(result.method).to eq("no_match")
      end
    end

    context "when cache hit exists (not expired)" do
      let!(:cache_entry) do
        create(:llm_categorization_cache_entry,
          merchant_normalized: normalized_merchant,
          category: category,
          confidence: 0.85,
          model_used: "claude-haiku-4-5",
          token_count: 100,
          cost: 0.001,
          expires_at: 30.days.from_now)
      end

      it "returns cached result without calling the API" do
        result = strategy.call(expense)

        expect(result).to be_successful
        expect(result.category).to eq(category)
        expect(result.confidence).to eq(0.85)
        expect(result.method).to eq("llm_haiku")
        expect(mock_client).not_to have_received(:categorize) if mock_client.respond_to?(:categorize)
      end

      it "refreshes the TTL on the cache entry" do
        freeze_time do
          strategy.call(expense)
          cache_entry.reload

          expect(cache_entry.expires_at).to be_within(1.second).of(90.days.from_now)
        end
      end

      it "includes cache_hit metadata" do
        result = strategy.call(expense)

        expect(result.metadata).to include(cache_hit: true)
      end
    end

    context "when cache miss with correction context in Rails.cache" do
      let(:prompt_text) { "categorize this merchant" }
      let(:correction_history) { { old: "groceries", new: "restaurants" } }
      let(:api_response) do
        {
          response_text: category.i18n_key,
          token_count: { input: 80, output: 5 },
          cost: 0.0003
        }
      end
      let(:prompt_builder) { instance_double(Services::Categorization::Llm::PromptBuilder) }

      before do
        # Store correction context in Rails.cache
        Rails.cache.write("llm_correction:#{normalized_merchant}", correction_history, expires_in: 90.days)

        allow(Services::Categorization::Llm::PromptBuilder).to receive(:new).and_return(prompt_builder)
        allow(prompt_builder).to receive(:build)
          .with(expense: expense, correction_history: correction_history)
          .and_return(prompt_text)
        allow(mock_client).to receive(:categorize).with(prompt_text: prompt_text).and_return(api_response)
        allow(Services::Categorization::Llm::ResponseParser).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::ResponseParser,
            parse: { category: category, confidence: 0.85, raw_response: category.i18n_key }))
      end

      it "passes correction_history to PromptBuilder" do
        strategy.call(expense)

        expect(prompt_builder).to have_received(:build)
          .with(expense: expense, correction_history: correction_history)
      end

      it "returns a successful result" do
        result = strategy.call(expense)

        expect(result).to be_successful
        expect(result.category).to eq(category)
      end
    end

    context "when cache miss (no entry)" do
      let(:prompt_text) { "categorize this merchant" }
      let(:api_response) do
        {
          response_text: category.i18n_key,
          token_count: { input: 80, output: 5 },
          cost: 0.0003
        }
      end

      before do
        allow(Services::Categorization::Llm::PromptBuilder).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::PromptBuilder, build: prompt_text))
        allow(mock_client).to receive(:categorize).with(prompt_text: prompt_text).and_return(api_response)
        allow(Services::Categorization::Llm::ResponseParser).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::ResponseParser,
            parse: { category: category, confidence: 0.85, raw_response: category.i18n_key }))
      end

      it "calls the LLM client and returns a successful result" do
        result = strategy.call(expense)

        expect(result).to be_successful
        expect(result.category).to eq(category)
        expect(result.confidence).to eq(0.85)
        expect(result.method).to eq("llm_haiku")
        expect(mock_client).to have_received(:categorize).with(prompt_text: prompt_text)
      end

      it "stores the result in cache with 90-day TTL" do
        freeze_time do
          expect { strategy.call(expense) }
            .to change(LlmCategorizationCacheEntry, :count).by(1)

          entry = LlmCategorizationCacheEntry.last
          expect(entry.merchant_normalized).to eq(normalized_merchant)
          expect(entry.category).to eq(category)
          expect(entry.confidence).to eq(0.85)
          expect(entry.model_used).to eq("claude-haiku-4-5")
          expect(entry.token_count).to eq(85)
          expect(entry.cost).to eq(0.0003)
          expect(entry.expires_at).to be_within(1.second).of(90.days.from_now)
        end
      end

      it "feeds the result into VectorUpdater" do
        vector_updater = instance_double(Services::Categorization::Learning::VectorUpdater)
        allow(Services::Categorization::Learning::VectorUpdater).to receive(:new).and_return(vector_updater)
        allow(vector_updater).to receive(:upsert)

        strategy.call(expense)

        expect(vector_updater).to have_received(:upsert).with(
          merchant: expense.merchant_name,
          category: category,
          description_keywords: []
        )
      end

      it "includes metadata about the LLM call" do
        result = strategy.call(expense)

        expect(result.metadata).to include(
          cache_hit: false,
          model_used: "claude-haiku-4-5"
        )
      end
    end

    context "when cache entry exists but is expired" do
      let!(:expired_entry) do
        create(:llm_categorization_cache_entry,
          merchant_normalized: normalized_merchant,
          category: category,
          confidence: 0.85,
          model_used: "claude-haiku-4-5",
          token_count: 100,
          cost: 0.001,
          expires_at: 1.day.ago)
      end

      let(:new_category) { create(:category) }
      let(:prompt_text) { "categorize this merchant" }
      let(:api_response) do
        {
          response_text: new_category.i18n_key,
          token_count: { input: 80, output: 5 },
          cost: 0.0003
        }
      end

      before do
        allow(Services::Categorization::Llm::PromptBuilder).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::PromptBuilder, build: prompt_text))
        allow(mock_client).to receive(:categorize).with(prompt_text: prompt_text).and_return(api_response)
        allow(Services::Categorization::Llm::ResponseParser).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::ResponseParser,
            parse: { category: new_category, confidence: 0.85, raw_response: new_category.i18n_key }))
      end

      it "calls the API again instead of using expired cache" do
        result = strategy.call(expense)

        expect(result).to be_successful
        expect(result.category).to eq(new_category)
        expect(mock_client).to have_received(:categorize)
      end

      it "updates the existing cache entry" do
        expect { strategy.call(expense) }
          .not_to change(LlmCategorizationCacheEntry, :count)

        expired_entry.reload
        expect(expired_entry.category).to eq(new_category)
        expect(expired_entry.expires_at).to be > Time.current
      end
    end

    context "when LLM client raises an error" do
      let(:prompt_text) { "categorize this merchant" }

      before do
        allow(Services::Categorization::Llm::PromptBuilder).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::PromptBuilder, build: prompt_text))
        allow(mock_client).to receive(:categorize)
          .and_raise(Services::Categorization::Llm::Client::Error, "API unavailable")
      end

      it "returns no_match gracefully" do
        result = strategy.call(expense)

        expect(result).not_to be_successful
        expect(result.method).to eq("no_match")
      end

      it "logs the error" do
        strategy.call(expense)

        expect(logger).to have_received(:error).with(/API unavailable/)
      end
    end

    context "when LLM returns no matching category" do
      let(:prompt_text) { "categorize this merchant" }
      let(:api_response) do
        {
          response_text: "unknown_category",
          token_count: { input: 80, output: 5 },
          cost: 0.0003
        }
      end

      before do
        allow(Services::Categorization::Llm::PromptBuilder).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::PromptBuilder, build: prompt_text))
        allow(mock_client).to receive(:categorize).with(prompt_text: prompt_text).and_return(api_response)
        allow(Services::Categorization::Llm::ResponseParser).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::ResponseParser,
            parse: { category: nil, confidence: 0.0, raw_response: "unknown_category" }))
      end

      it "returns no_match when parser finds no category" do
        result = strategy.call(expense)

        expect(result).not_to be_successful
        expect(result.method).to eq("no_match")
      end

      it "does not create a cache entry" do
        expect { strategy.call(expense) }
          .not_to change(LlmCategorizationCacheEntry, :count)
      end
    end

    context "when VectorUpdater fails" do
      let(:prompt_text) { "categorize this merchant" }
      let(:api_response) do
        {
          response_text: category.i18n_key,
          token_count: { input: 80, output: 5 },
          cost: 0.0003
        }
      end

      before do
        allow(Services::Categorization::Llm::PromptBuilder).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::PromptBuilder, build: prompt_text))
        allow(mock_client).to receive(:categorize).with(prompt_text: prompt_text).and_return(api_response)
        allow(Services::Categorization::Llm::ResponseParser).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::ResponseParser,
            parse: { category: category, confidence: 0.85, raw_response: category.i18n_key }))

        vector_updater = instance_double(Services::Categorization::Learning::VectorUpdater)
        allow(Services::Categorization::Learning::VectorUpdater).to receive(:new).and_return(vector_updater)
        allow(vector_updater).to receive(:upsert).and_raise(StandardError, "DB error")
      end

      it "still returns the successful result" do
        result = strategy.call(expense)

        expect(result).to be_successful
        expect(result.category).to eq(category)
      end

      it "logs the VectorUpdater error" do
        strategy.call(expense)

        expect(logger).to have_received(:warn).with(/VectorUpdater/)
      end
    end

    context "rate limit handling" do
      let(:prompt_text) do
        instance_double(Services::Categorization::Llm::PromptBuilder).tap do |pb|
          allow(Services::Categorization::Llm::PromptBuilder).to receive(:new).and_return(pb)
          allow(pb).to receive(:build).and_return("prompt")
        end
        "prompt"
      end

      before do
        # Stub sleep to keep tests fast — retry backoffs would otherwise sleep 10s+
        allow_any_instance_of(described_class).to receive(:sleep)
      end

      it "retries when the LLM client raises RateLimitError and succeeds on retry" do
        success_response = {
          response_text: category.i18n_key,
          token_count: { input: 100, output: 10 },
          cost: 0.001
        }

        call_count = 0
        allow(mock_client).to receive(:categorize) do
          call_count += 1
          if call_count == 1
            raise Services::Categorization::Llm::Client::RateLimitError, "Rate limit exceeded"
          else
            success_response
          end
        end

        allow(Services::Categorization::Llm::ResponseParser).to receive(:new).and_return(
          instance_double(Services::Categorization::Llm::ResponseParser,
            parse: { category: category, confidence: 0.85, raw_response: category.i18n_key })
        )
        allow(Services::Categorization::Learning::VectorUpdater).to receive(:new).and_return(
          instance_double(Services::Categorization::Learning::VectorUpdater, upsert: nil)
        )

        result = strategy.call(expense)

        expect(call_count).to eq(2)
        expect(result).to be_successful
        expect(result.category).to eq(category)
      end

      it "gives up after MAX_RETRIES rate limit errors and returns no_match" do
        allow(mock_client).to receive(:categorize)
          .and_raise(Services::Categorization::Llm::Client::RateLimitError, "Rate limit exceeded")

        result = strategy.call(expense)

        expect(mock_client).to have_received(:categorize).exactly(described_class::MAX_RETRIES + 1).times
        expect(result).not_to be_successful
        expect(logger).to have_received(:error).with(/giving up/)
      end

      it "throttles before every retry (not just the first call)" do
        allow(mock_client).to receive(:categorize)
          .and_raise(Services::Categorization::Llm::Client::RateLimitError, "Rate limit exceeded")

        throttle_count = 0
        allow_any_instance_of(described_class).to receive(:throttle!) { throttle_count += 1 }

        strategy.call(expense)

        # Throttle must be called before EVERY attempt, including retries
        expect(throttle_count).to eq(described_class::MAX_RETRIES + 1)
      end
    end

    context "throttling" do
      it "skips throttling in test environment to keep tests fast" do
        expect(Rails.env).to receive(:test?).and_return(true)
        expect(strategy).not_to receive(:sleep)
        strategy.send(:throttle!)
      end
    end
  end
end
