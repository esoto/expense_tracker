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
        prompt = Llm::PromptBuilder.new.build(expense: expense)
        api_result = client.categorize(prompt_text: prompt)

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

      def store_cache(normalized, parsed, api_result, total_tokens, existing_entry)
        attrs = {
          category: parsed[:category],
          confidence: parsed[:confidence],
          model_used: Llm::Client::MODEL,
          token_count: total_tokens,
          cost: api_result[:cost],
          expires_at: CACHE_TTL.from_now
        }

        if existing_entry
          existing_entry.update!(attrs)
        else
          LlmCategorizationCacheEntry.create!(attrs.merge(merchant_normalized: normalized))
        end
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

      def duration_ms(start_time)
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
      end
    end
  end
end
