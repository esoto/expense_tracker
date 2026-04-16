# frozen_string_literal: true

module Services::Categorization
  module Strategies
    # Layer 3 categorization strategy that uses an LLM (Claude Haiku) to
    # categorize expenses when pattern matching (Layer 1) and similarity
    # matching (Layer 2) fail to produce a confident result.
    #
    # Implements a cache-first approach: checks LlmCategorizationCacheEntry
    # before making an API call. Successful results are cached for 90 days
    # and fed into VectorUpdater so Layer 2 can learn from them.
    class LlmStrategy < BaseStrategy
      CACHE_TTL = 90.days
      MONTHLY_BUDGET = 5.0
      BUDGET_KEY_PREFIX = "llm_budget"
      BUDGET_TTL = 35.days
      CORRECTION_KEY_PREFIX = "llm_correction"

      # Rate limit handling.
      # Anthropic's default input tokens-per-minute limit is 50,000 for Haiku.
      # Each LLM call with web_search uses ~10,000 input tokens (tool results
      # inflate the prompt), so we can do ~5 calls per minute.
      # MIN_CALL_INTERVAL_S enforces at least N seconds between calls to
      # naturally stay under the limit.
      MIN_CALL_INTERVAL_S = 15
      MAX_RETRIES = 3
      RETRY_BACKOFF_S = [ 10, 30, 60 ].freeze

      # Class-level mutex for inter-thread throttling within a process.
      # Each Solid Queue worker thread shares this mutex.
      @rate_limit_mutex = Mutex.new
      @last_llm_call_at = nil

      class << self
        attr_accessor :last_llm_call_at
        attr_reader :rate_limit_mutex
      end

      # @param client [Llm::Client, nil] injectable LLM client for testing
      # @param logger [Logger]
      def initialize(client: nil, logger: Rails.logger)
        @client = client
        @logger = logger
      end

      # @return [String]
      def layer_name
        "haiku"
      end

      # Attempt to categorize an expense via LLM with cache lookup.
      #
      # @param expense [Expense]
      # @param _options [Hash] unused
      # @return [CategorizationResult]
      def call(expense, _options = {})
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        normalized = normalize_merchant(expense)
        if normalized.blank?
          return CategorizationResult.no_match(processing_time_ms: duration_ms(start_time))
        end

        # Check budget before any work
        if budget_exceeded?
          return build_budget_exceeded_result(start_time)
        end

        # Check cache first
        cached = lookup_cache(normalized)
        if cached && !cached.expired?
          cached.refresh_ttl!(CACHE_TTL)
          return build_cached_result(cached, duration_ms(start_time))
        end

        # Cache miss or expired — call LLM
        call_llm_and_cache(expense, normalized, cached, start_time)
      rescue Llm::Client::Error => e
        @logger.error "[LlmStrategy] LLM client error: #{e.message}"
        CategorizationResult.no_match(processing_time_ms: duration_ms(start_time))
      end

      private

      def client
        @client ||= Llm::Client.new
      end

      def normalize_merchant(expense)
        return "" unless expense.merchant_name?

        MerchantNormalizer.normalize(expense.merchant_name)
      end

      def lookup_cache(normalized)
        LlmCategorizationCacheEntry.find_by(merchant_normalized: normalized)
      end

      def call_llm_and_cache(expense, normalized, existing_entry, start_time)
        correction_history = Rails.cache.read("#{CORRECTION_KEY_PREFIX}:#{normalized}")
        prompt = Llm::PromptBuilder.new.build(expense: expense, correction_history: correction_history)
        api_result = call_with_rate_limit_handling(prompt)
        return CategorizationResult.no_match(processing_time_ms: duration_ms(start_time)) unless api_result

        increment_budget(api_result[:cost])

        parsed = Llm::ResponseParser.new.parse(response_text: api_result[:response_text])

        # If parser found no category, return no_match
        unless parsed[:category]
          return CategorizationResult.no_match(processing_time_ms: duration_ms(start_time))
        end

        total_tokens = api_result[:token_count][:input] + api_result[:token_count][:output]

        # Store or update cache
        store_cache(normalized, parsed, api_result, total_tokens, existing_entry)

        # Feed Layer 2 so similarity strategy learns from LLM results
        feed_vector_updater(expense, parsed[:category])

        build_llm_result(parsed, duration_ms(start_time))
      end

      # Throttles and retries LLM calls to handle Anthropic's token-per-minute
      # rate limit. Returns the API result on success, or nil on persistent failure.
      def call_with_rate_limit_handling(prompt)
        throttle!
        attempts = 0

        begin
          attempts += 1
          client.categorize(prompt_text: prompt)
        rescue Llm::Client::RateLimitError => e
          if attempts <= MAX_RETRIES
            sleep_s = extract_retry_after(e.message) || RETRY_BACKOFF_S[attempts - 1]
            @logger.warn("[LlmStrategy] Rate limited (attempt #{attempts}/#{MAX_RETRIES}), sleeping #{sleep_s}s")
            sleep(sleep_s)
            retry
          else
            @logger.error("[LlmStrategy] Rate limited after #{MAX_RETRIES} retries — giving up")
            nil
          end
        end
      end

      # Parse "retry-after" hint from Anthropic error body if present.
      # Falls back to nil so caller uses exponential backoff.
      def extract_retry_after(message)
        match = message.match(/"retry-after"\s*=>\s*"(\d+)"/) || message.match(/retry.after[^\d]+(\d+)/i)
        match && match[1].to_i
      end

      # Enforce MIN_CALL_INTERVAL_S between LLM calls across all threads in
      # this process. When multiple workers hit the LLM simultaneously, they
      # queue up on this mutex and wait their turn.
      # Disabled in test env to keep unit tests fast.
      def throttle!
        return if Rails.env.test?

        self.class.rate_limit_mutex.synchronize do
          last = self.class.last_llm_call_at
          if last
            elapsed = Time.now - last
            if elapsed < MIN_CALL_INTERVAL_S
              wait_s = MIN_CALL_INTERVAL_S - elapsed
              @logger.debug("[LlmStrategy] Throttling: waiting #{wait_s.round(1)}s before next LLM call")
              sleep(wait_s)
            end
          end
          self.class.last_llm_call_at = Time.now
        end
      end

      def store_cache(normalized, parsed, api_result, total_tokens, _existing_entry)
        attrs = {
          category: parsed[:category],
          confidence: parsed[:confidence],
          model_used: Llm::Client::MODEL,
          token_count: total_tokens,
          cost: api_result[:cost],
          expires_at: CACHE_TTL.from_now
        }

        # Use find_or_create + update to handle concurrent requests safely.
        # Rescues RecordNotUnique from the unique index on merchant_normalized.
        entry = LlmCategorizationCacheEntry.find_or_create_by!(merchant_normalized: normalized) do |e|
          e.assign_attributes(attrs)
        end
        entry.update!(attrs) unless entry.previously_new_record?
      rescue ActiveRecord::RecordNotUnique
        LlmCategorizationCacheEntry.find_by!(merchant_normalized: normalized).update!(attrs)
      end

      def feed_vector_updater(expense, category)
        Learning::VectorUpdater.new.upsert(
          merchant: expense.merchant_name,
          category: category,
          description_keywords: []
        )
      rescue StandardError => e
        @logger.warn "[LlmStrategy] VectorUpdater failed: #{e.message}"
      end

      def build_cached_result(cache_entry, processing_time_ms)
        CategorizationResult.new(
          category: cache_entry.category,
          confidence: cache_entry.confidence,
          method: "llm_haiku",
          patterns_used: [ "llm_cache:#{cache_entry.merchant_normalized}" ],
          processing_time_ms: processing_time_ms,
          metadata: {
            cache_hit: true,
            merchant_normalized: cache_entry.merchant_normalized
          }
        )
      end

      def build_llm_result(parsed, processing_time_ms)
        CategorizationResult.new(
          category: parsed[:category],
          confidence: parsed[:confidence],
          method: "llm_haiku",
          patterns_used: [ "llm_api" ],
          processing_time_ms: processing_time_ms,
          metadata: {
            cache_hit: false,
            model_used: Llm::Client::MODEL
          }
        )
      end

      def budget_key
        "#{BUDGET_KEY_PREFIX}:#{Date.current.strftime('%Y-%m')}"
      end

      def budget_exceeded?
        current_spend = Rails.cache.read(budget_key) || 0.0
        current_spend.to_f >= MONTHLY_BUDGET
      end

      def increment_budget(cost)
        # Atomic-safe: read + write with the new total.
        # Acceptable for single-user app — concurrent LLM calls are serialized
        # by the strategy chain (one expense at a time).
        current = Rails.cache.read(budget_key) || 0.0
        Rails.cache.write(budget_key, current.to_f + cost, expires_in: BUDGET_TTL)
      end

      def build_budget_exceeded_result(start_time)
        CategorizationResult.new(
          method: "no_match",
          processing_time_ms: duration_ms(start_time),
          metadata: { reason: "budget_exceeded" }
        )
      end

      def duration_ms(start_time)
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
      end
    end
  end
end
