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

  # PER-500: auth / configuration failures trip a short-lived circuit breaker
  # so the strategy stops burning 15s throttle cycles against a known-broken
  # credential. The break auto-recovers after AUTH_FAILURE_TTL.
  describe "#call auth-failure circuit breaker", :unit do
    let(:prompt_text) { "categorize" }
    let(:api_response) do
      { response_text: category.i18n_key,
        token_count: { input: 80, output: 5 },
        cost: 0.0003 }
    end

    before do
      Rails.cache.delete(described_class::AUTH_FAILURE_CACHE_KEY)
      allow(Services::Categorization::Llm::PromptBuilder).to receive(:new)
        .and_return(instance_double(Services::Categorization::Llm::PromptBuilder, build: prompt_text))
      allow(Services::Categorization::Llm::ResponseParser).to receive(:new)
        .and_return(instance_double(Services::Categorization::Llm::ResponseParser,
          parse: { category: category, confidence: 0.85, raw_response: category.i18n_key }))
    end

    # Guard against leaking the flag into neighboring specs in the same
    # process — Rails.cache is shared state.
    after { Rails.cache.delete(described_class::AUTH_FAILURE_CACHE_KEY) }

    it "defines AUTH_FAILURE_CACHE_KEY and AUTH_FAILURE_TTL" do
      expect(described_class::AUTH_FAILURE_CACHE_KEY).to be_a(String)
      expect(described_class::AUTH_FAILURE_TTL).to be_a(ActiveSupport::Duration)
    end

    context "when the circuit is already open (auth flag set in cache)" do
      before do
        Rails.cache.write(described_class::AUTH_FAILURE_CACHE_KEY, true,
                          expires_in: described_class::AUTH_FAILURE_TTL)
      end

      it "returns no_match without touching the LLM client" do
        allow(mock_client).to receive(:categorize)
        result = strategy.call(expense)

        expect(result).not_to be_successful
        expect(result.method).to eq("no_match")
        expect(mock_client).not_to have_received(:categorize)
      end

      it "logs that the circuit is open with a short explanation" do
        strategy.call(expense)
        expect(logger).to have_received(:warn).with(/circuit open|auth failure/i)
      end
    end

    context "when the LLM client raises AuthenticationError" do
      before do
        allow(mock_client).to receive(:categorize)
          .and_raise(Services::Categorization::Llm::Client::AuthenticationError.new("bad api key"))
      end

      it "trips the circuit breaker by writing the cache flag" do
        strategy.call(expense)
        expect(Rails.cache.read(described_class::AUTH_FAILURE_CACHE_KEY)).to be true
      end

      it "reports the exception via Services::ErrorTrackingService" do
        tracker = instance_double(Services::ErrorTrackingService, track_exception: nil)
        allow(Services::ErrorTrackingService).to receive(:instance).and_return(tracker)

        strategy.call(expense)

        expect(tracker).to have_received(:track_exception).with(
          instance_of(Services::Categorization::Llm::Client::AuthenticationError),
          hash_including(strategy: "LlmStrategy")
        )
      end

      it "returns no_match so the engine falls through to the next layer" do
        result = strategy.call(expense)
        expect(result).not_to be_successful
        expect(result.method).to eq("no_match")
      end
    end

    context "when the LLM client raises ConfigurationError" do
      before do
        allow(mock_client).to receive(:categorize)
          .and_raise(Services::Categorization::Llm::Client::ConfigurationError.new("missing api key"))
      end

      it "trips the circuit breaker" do
        strategy.call(expense)
        expect(Rails.cache.read(described_class::AUTH_FAILURE_CACHE_KEY)).to be true
      end

      it "reports via Services::ErrorTrackingService (parity with AuthenticationError)" do
        tracker = instance_double(Services::ErrorTrackingService, track_exception: nil)
        allow(Services::ErrorTrackingService).to receive(:instance).and_return(tracker)

        strategy.call(expense)

        expect(tracker).to have_received(:track_exception).with(
          instance_of(Services::Categorization::Llm::Client::ConfigurationError),
          hash_including(strategy: "LlmStrategy")
        )
      end

      it "returns no_match so the engine falls through to the next layer" do
        result = strategy.call(expense)
        expect(result).not_to be_successful
        expect(result.method).to eq("no_match")
      end
    end

    # Lock in the design decision: when the circuit is open, we DO NOT serve
    # a stale cached classification — we return no_match so the outage
    # signal propagates. A future refactor that moved the circuit check
    # below `lookup_cache` (for "performance") would silently hide outages.
    context "when the circuit is open AND a valid cache entry exists" do
      before do
        Rails.cache.write(described_class::AUTH_FAILURE_CACHE_KEY, true,
                          expires_in: described_class::AUTH_FAILURE_TTL)
        create(:llm_categorization_cache_entry,
          merchant_normalized: normalized_merchant,
          category: category,
          expires_at: 30.days.from_now)
      end

      it "returns no_match (circuit wins over cache)" do
        result = strategy.call(expense)
        expect(result).not_to be_successful
        expect(result.method).to eq("no_match")
      end
    end

    # Lock in the auto-recovery contract: when AUTH_FAILURE_TTL expires the
    # circuit closes on its own. Prevents a future typo that pinned the
    # circuit open forever.
    context "when the circuit has expired (auto-recovery)" do
      before do
        Rails.cache.write(described_class::AUTH_FAILURE_CACHE_KEY, true,
                          expires_in: described_class::AUTH_FAILURE_TTL)
        allow(mock_client).to receive(:categorize).and_return(api_response)
      end

      it "recovers and calls the LLM after the TTL elapses" do
        travel_to(described_class::AUTH_FAILURE_TTL.from_now + 1.second) do
          strategy.call(expense)
          expect(mock_client).to have_received(:categorize)
        end
      end
    end

    # Non-auth errors (rate limits, timeouts, server 500s) must NOT trip the
    # circuit — those are transient and have their own retry layer. Tripping
    # the circuit on a flaky network would lock out categorization for 5min
    # every time Anthropic has a bad minute.
    context "when the LLM client raises a non-auth Llm::Client::Error" do
      before do
        allow(mock_client).to receive(:categorize)
          .and_raise(Services::Categorization::Llm::Client::ApiError.new("500 upstream"))
      end

      it "does NOT trip the circuit breaker" do
        strategy.call(expense)
        expect(Rails.cache.read(described_class::AUTH_FAILURE_CACHE_KEY)).to be_nil
      end

      it "returns no_match" do
        result = strategy.call(expense)
        expect(result).not_to be_successful
      end
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
    it "defines BUDGET_KEY_PREFIX with the v2 suffix (PER-492 encoding change)" do
      expect(described_class::BUDGET_KEY_PREFIX).to eq("llm_budget_v2")
    end

    it "defines BUDGET_UNITS_PER_USD as 10_000" do
      expect(described_class::BUDGET_UNITS_PER_USD).to eq(10_000)
    end
  end

  describe ".monthly_budget" do
    around do |example|
      original = ENV["LLM_MONTHLY_BUDGET_USD"]
      ENV.delete("LLM_MONTHLY_BUDGET_USD")
      example.run
    ensure
      ENV["LLM_MONTHLY_BUDGET_USD"] = original
    end

    it "defaults to 5.0 when LLM_MONTHLY_BUDGET_USD is not set" do
      expect(described_class.monthly_budget).to eq(5.0)
    end

    it "reads LLM_MONTHLY_BUDGET_USD from env when set" do
      ENV["LLM_MONTHLY_BUDGET_USD"] = "12.50"
      expect(described_class.monthly_budget).to eq(12.50)
    end

    it "falls back to the default for a non-numeric value" do
      ENV["LLM_MONTHLY_BUDGET_USD"] = "disabled"
      expect(described_class.monthly_budget).to eq(5.0)
    end

    it "falls back to the default for an empty value" do
      ENV["LLM_MONTHLY_BUDGET_USD"] = ""
      expect(described_class.monthly_budget).to eq(5.0)
    end

    it "falls back to the default for zero" do
      ENV["LLM_MONTHLY_BUDGET_USD"] = "0"
      expect(described_class.monthly_budget).to eq(5.0)
    end

    it "falls back to the default for a negative value" do
      ENV["LLM_MONTHLY_BUDGET_USD"] = "-1"
      expect(described_class.monthly_budget).to eq(5.0)
    end

    # Float("1e400") == Float::INFINITY, and Infinity.positive? is true, so
    # without the .finite? guard a misconfigured env would silently disable
    # the cap.
    it "falls back to the default for a value that parses to Infinity" do
      ENV["LLM_MONTHLY_BUDGET_USD"] = "1e400"
      expect(described_class.monthly_budget).to eq(5.0)
    end
  end

  describe "#budget_exceeded? boundary" do
    let(:budget_key) { "llm_budget_v2:#{Date.current.strftime('%Y-%m')}" }

    it "returns false at 49_999 units (1 unit under the $5 cap)" do
      Rails.cache.write(budget_key, 49_999, expires_in: 35.days)
      expect(strategy.send(:budget_exceeded?)).to be false
    end

    it "returns true at 50_000 units (exactly at the $5 cap)" do
      Rails.cache.write(budget_key, 50_000, expires_in: 35.days)
      expect(strategy.send(:budget_exceeded?)).to be true
    end

    it "returns true at 50_001 units (1 unit over the $5 cap)" do
      Rails.cache.write(budget_key, 50_001, expires_in: 35.days)
      expect(strategy.send(:budget_exceeded?)).to be true
    end
  end

  describe "#increment_budget edge cases" do
    let(:budget_key) { "llm_budget_v2:#{Date.current.strftime('%Y-%m')}" }

    before { Rails.cache.delete(budget_key) }

    it "no-ops when cost is exactly zero" do
      strategy.send(:increment_budget, 0.0)
      expect(Rails.cache.read(budget_key)).to be_nil
    end

    it "no-ops when cost rounds down to zero units (e.g. tiny negative)" do
      strategy.send(:increment_budget, -0.00001)
      expect(Rails.cache.read(budget_key)).to be_nil
    end

    # Guards against provider refund / upstream bug producing a negative cost,
    # which would otherwise decrement the counter via Rails.cache.increment.
    it "no-ops for a larger negative cost instead of decrementing" do
      strategy.send(:increment_budget, -0.50)
      expect(Rails.cache.read(budget_key)).to be_nil
    end

    # Exercises the write(unless_exist:) + increment pair on a fresh key —
    # the production path on the first LLM call of each month.
    it "seeds and increments on the first call when the key is absent" do
      strategy.send(:increment_budget, 0.25)
      # ceil(0.25 * 10_000) = 2_500 units
      expect(Rails.cache.read(budget_key)).to eq(2_500)
    end
  end

  describe "#call" do
    context "when budget is exceeded" do
      before do
        # Cache stores spend in integer units scaled by BUDGET_UNITS_PER_USD (10_000).
        # 5.50 USD = 55_000 units (over the 5.00 cap).
        budget_key = "llm_budget_v2:#{Date.current.strftime('%Y-%m')}"
        Rails.cache.write(budget_key, 55_000, expires_in: 35.days)
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
        # 5.00 USD = 50_000 units (exactly at the cap).
        budget_key = "llm_budget_v2:#{Date.current.strftime('%Y-%m')}"
        Rails.cache.write(budget_key, 50_000, expires_in: 35.days)
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
        # 4.99 USD = 49_900 units.
        budget_key = "llm_budget_v2:#{Date.current.strftime('%Y-%m')}"
        Rails.cache.write(budget_key, 49_900, expires_in: 35.days)

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

      it "increments the budget counter atomically by (cost * BUDGET_UNITS_PER_USD).ceil" do
        strategy.call(expense)

        budget_key = "llm_budget_v2:#{Date.current.strftime('%Y-%m')}"
        # 49_900 seed + ceil(0.0003 * 10_000) = 49_900 + 3 = 49_903
        expect(Rails.cache.read(budget_key)).to eq(49_903)
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
        budget_key = "llm_budget_v2:#{Date.current.strftime('%Y-%m')}"
        Rails.cache.delete(budget_key)

        strategy.call(expense)

        # ceil(0.0005 * 10_000) = 5
        expect(Rails.cache.read(budget_key)).to eq(5)
      end
    end

    # PER-492: Replaces the read-modify-write pattern with atomic cache increment.
    # Under burst load, RMW silently undercounts by 10-20% and the $5/mo cap
    # stops triggering. This test spins up 10 threads hitting the same key.
    context "atomic budget increment under concurrency", :integration do
      let(:budget_key) { "llm_budget_v2:#{Date.current.strftime('%Y-%m')}" }

      it "produces the correct total when 10 threads each increment $0.50" do
        Rails.cache.delete(budget_key)

        # Build 10 strategy instances so each thread has its own (throttle mutex
        # is class-level; we want to exercise the cache increment, not the throttle).
        threads = 10.times.map do
          Thread.new { described_class.new.send(:increment_budget, 0.50) }
        end
        threads.each(&:join)

        # 10 threads * ceil(0.50 * 10_000) = 10 * 5_000 = 50_000
        expect(Rails.cache.read(budget_key)).to eq(50_000)
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

    # PER-499: prompt_version and model_used are part of the cache key.
    # A row written under an older prompt/model must NOT be served after a
    # bump — the strategy should treat it as a miss and call the LLM.
    context "when cache entry exists but has a stale prompt_version" do
      let!(:stale_entry) do
        create(:llm_categorization_cache_entry,
          merchant_normalized: normalized_merchant,
          category: category,
          prompt_version: "v0-historical",
          model_used: "claude-haiku-4-5",
          expires_at: 30.days.from_now)
      end
      let(:prompt_text) { "categorize" }
      let(:api_response) do
        { response_text: category.i18n_key,
          token_count: { input: 80, output: 5 },
          cost: 0.0003 }
      end

      before do
        allow(Services::Categorization::Llm::PromptBuilder).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::PromptBuilder, build: prompt_text))
        allow(mock_client).to receive(:categorize).with(prompt_text: prompt_text).and_return(api_response)
        allow(Services::Categorization::Llm::ResponseParser).to receive(:new)
          .and_return(instance_double(Services::Categorization::Llm::ResponseParser,
            parse: { category: category, confidence: 0.85, raw_response: category.i18n_key }))
      end

      it "treats the stale-version entry as a cache miss and calls the LLM" do
        strategy.call(expense)
        expect(mock_client).to have_received(:categorize)
      end

      it "creates a new cache row at the current PROMPT_VERSION" do
        expect { strategy.call(expense) }.to change(LlmCategorizationCacheEntry, :count).by(1)

        fresh_entry = LlmCategorizationCacheEntry.find_by(
          merchant_normalized: normalized_merchant,
          prompt_version: Services::Categorization::Llm::PromptBuilder::PROMPT_VERSION,
          model_used: "claude-haiku-4-5"
        )
        expect(fresh_entry).to be_present
      end

      it "leaves the stale entry in place so it can age out naturally" do
        strategy.call(expense)
        expect(LlmCategorizationCacheEntry.exists?(stale_entry.id)).to be true
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

      context "distributed throttle (multi-process coordination)" do
        before do
          # Unstub Rails.env.test? so throttle! executes its real body.
          # Stub sleep to avoid real waits.
          allow(Rails.env).to receive(:test?).and_return(false)
          allow(strategy).to receive(:sleep)
          # Clear any state from other tests in this describe block.
          Rails.cache.delete(described_class::THROTTLE_SLOT_KEY)
          Rails.cache.delete(described_class::THROTTLE_EPOCH_KEY)
        end

        it "first caller fires immediately (slot=1, wait=0)" do
          expect(strategy).not_to receive(:sleep)
          strategy.send(:throttle!)

          expect(Rails.cache.read(described_class::THROTTLE_SLOT_KEY)).to eq(1)
          expect(Rails.cache.read(described_class::THROTTLE_EPOCH_KEY)).to be_a(Float)
        end

        it "second caller waits MIN_CALL_INTERVAL_S seconds (minus elapsed)" do
          # First call establishes epoch
          strategy.send(:throttle!)

          # Freeze-ish: we can't freeze time trivially, so instead assert
          # sleep is called with a value close to MIN_CALL_INTERVAL_S.
          allow(strategy).to receive(:sleep) do |seconds|
            expect(seconds).to be_within(0.5).of(described_class::MIN_CALL_INTERVAL_S)
          end

          strategy.send(:throttle!)
          expect(Rails.cache.read(described_class::THROTTLE_SLOT_KEY)).to eq(2)
        end

        it "coordinates across multiple strategy instances (simulating multiple processes)" do
          # Two separate instances share Rails.cache state — exactly the
          # multi-process scenario we're fixing (each SQ process has its
          # own LlmStrategy objects but reaches the same Solid Cache).
          a = described_class.new(client: mock_client, logger: logger)
          b = described_class.new(client: mock_client, logger: logger)

          allow(a).to receive(:sleep)
          allow(b).to receive(:sleep)

          a.send(:throttle!)
          b.send(:throttle!)

          # Both reserved a slot; counter must be monotonic.
          expect(Rails.cache.read(described_class::THROTTLE_SLOT_KEY)).to eq(2)
          # b (second caller) must have been asked to sleep ~MIN_CALL_INTERVAL_S.
          expect(b).to have_received(:sleep).with(a_value_within(0.5).of(described_class::MIN_CALL_INTERVAL_S))
        end

        it "proceeds without waiting when Rails.cache.increment returns nil (graceful degradation)" do
          allow(Rails.cache).to receive(:increment).and_return(nil)
          expect(strategy).not_to receive(:sleep)
          expect(logger).to receive(:warn).with(/slot reservation failed/)

          strategy.send(:throttle!)
        end
      end

      context "retry backoff honors Retry-After header" do
        before do
          allow(strategy).to receive(:throttle!)  # skip throttle during retry test
          allow(strategy).to receive(:sleep)
          allow(Services::Categorization::Llm::ResponseParser).to receive(:new).and_return(
            instance_double(Services::Categorization::Llm::ResponseParser,
              parse: { category: category, confidence: 0.85, raw_response: category.i18n_key })
          )
          allow(Services::Categorization::Learning::VectorUpdater).to receive(:new).and_return(
            instance_double(Services::Categorization::Learning::VectorUpdater, upsert: nil)
          )
        end

        it "sleeps for retry_after seconds when the error carries it" do
          call_count = 0
          allow(mock_client).to receive(:categorize) do
            call_count += 1
            if call_count == 1
              raise Services::Categorization::Llm::Client::RateLimitError.new("Rate limit", retry_after: 7)
            else
              { response_text: category.i18n_key, token_count: { input: 100, output: 10 }, cost: 0.001 }
            end
          end

          strategy.call(expense)

          expect(strategy).to have_received(:sleep).with(7).once
          expect(logger).to have_received(:warn).with(/retry-after header/)
        end

        it "falls back to fixed backoff schedule when retry_after is nil" do
          call_count = 0
          allow(mock_client).to receive(:categorize) do
            call_count += 1
            if call_count == 1
              raise Services::Categorization::Llm::Client::RateLimitError.new("Rate limit", retry_after: nil)
            else
              { response_text: category.i18n_key, token_count: { input: 100, output: 10 }, cost: 0.001 }
            end
          end

          strategy.call(expense)

          expect(strategy).to have_received(:sleep).with(described_class::RETRY_BACKOFF_S.first).once
          expect(logger).to have_received(:warn).with(/fixed backoff/)
        end
      end
    end
  end
end
