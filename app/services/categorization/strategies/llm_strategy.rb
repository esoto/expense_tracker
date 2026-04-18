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
      DEFAULT_MONTHLY_BUDGET_USD = 5.0
      # Bumped from "llm_budget" when PER-492 changed the cached value encoding
      # from USD floats to integer units. The _v2 suffix orphans pre-deploy
      # float values so the guard doesn't misread 4.99 (USD) as 4 (units =
      # $0.0004) during the 35-day BUDGET_TTL window after rollout.
      BUDGET_KEY_PREFIX = "llm_budget_v2"
      BUDGET_TTL = 35.days
      # Budget is stored in the cache as an integer in "budget units" so
      # Rails.cache.increment (integer-only) can be used atomically. LLM calls
      # can cost fractions of a cent (e.g. $0.0003), so cents (×100) would
      # truncate to 0. BUDGET_UNITS_PER_USD = 10_000 preserves tenths-of-a-cent.
      BUDGET_UNITS_PER_USD = 10_000
      CORRECTION_KEY_PREFIX = "llm_correction"

      # PER-500: auth-failure circuit breaker. A dropped API key, rotated
      # credentials, or a config regression should NOT silently fail every
      # categorization for hours — we saw exactly that on 2026-04-16. When
      # the LLM client reports an auth or configuration error, we trip a
      # short-lived cache flag so subsequent calls return no_match
      # immediately (no 15s throttle, no wasted retry loop) and the error
      # surfaces via the ErrorTrackingService. The flag auto-clears after
      # AUTH_FAILURE_TTL so the system recovers as soon as creds are fixed.
      AUTH_FAILURE_CACHE_KEY = "llm_auth_broken"
      AUTH_FAILURE_TTL = 5.minutes

      # Rate limit handling.
      # Anthropic's default input tokens-per-minute limit is 50,000 for Haiku.
      # Each LLM call with web_search uses ~10,000 input tokens (tool results
      # inflate the prompt), so we can do ~5 calls per minute.
      # MIN_CALL_INTERVAL_S enforces at least N seconds between calls to
      # naturally stay under the limit.
      MIN_CALL_INTERVAL_S = 15
      MAX_RETRIES = 3
      RETRY_BACKOFF_S = [ 10, 30, 60 ].freeze

      # Distributed throttle state (shared across all Solid Queue worker
      # processes via Rails.cache / Solid Cache). The per-process mutex is
      # retained to keep contention between threads in the same process
      # cheap (local lock instead of round-tripping to Solid Cache).
      THROTTLE_SLOT_KEY = "categorization:llm:slot_counter"
      THROTTLE_EPOCH_KEY = "categorization:llm:epoch_start_at"
      # TTL covers the expected worst-case queue burst + idle period. If the
      # system is idle long enough for this to expire, the slot counter
      # resets and a fresh epoch starts — correct behavior (no stale
      # backpressure from last week's sync).
      THROTTLE_STATE_TTL = 1.hour

      @rate_limit_mutex = Mutex.new

      class << self
        attr_reader :rate_limit_mutex
      end

      # Resolves the monthly LLM budget cap in USD. Reads LLM_MONTHLY_BUDGET_USD
      # from the environment and falls back defensively: a non-numeric, empty,
      # zero, negative, or infinite value collapses to the default so a
      # misconfigured env var cannot silently disable the budget guard. (Note
      # that Float("1e400") == Float::INFINITY, and Infinity.positive? is true,
      # so the .finite? check is load-bearing, not cosmetic.)
      def self.monthly_budget
        value = Float(ENV.fetch("LLM_MONTHLY_BUDGET_USD", nil))
        value.positive? && value.finite? ? value : DEFAULT_MONTHLY_BUDGET_USD
      rescue TypeError, ArgumentError
        DEFAULT_MONTHLY_BUDGET_USD
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

        # PER-500: short-circuit when auth has recently broken. Saves the
        # 15s throttle + retry cycle for every expense in the queue.
        if auth_circuit_open?
          @logger.warn "[LlmStrategy] circuit open (auth failure within last #{AUTH_FAILURE_TTL.inspect}) — skipping LLM"
          return CategorizationResult.no_match(processing_time_ms: duration_ms(start_time))
        end

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

        # Cache miss or expired — call LLM. The `cached` value (possibly an
        # expired entry for the CURRENT prompt_version/model_used tuple) is
        # not passed to call_llm_and_cache anymore; store_cache now uses
        # find_or_create_by on the composite key so concurrent writes, stale
        # expired entries, and fresh inserts all converge safely.
        call_llm_and_cache(expense, normalized, start_time)
      rescue Llm::Client::AuthenticationError, Llm::Client::ConfigurationError => e
        trip_auth_circuit!(e)
        CategorizationResult.no_match(processing_time_ms: duration_ms(start_time))
      rescue Llm::Client::Error => e
        @logger.error "[LlmStrategy] LLM client error: #{e.message}"
        CategorizationResult.no_match(processing_time_ms: duration_ms(start_time))
      end

      private

      def client
        @client ||= Llm::Client.new
      end

      # PER-500: circuit-breaker helpers. Read and write the shared cache
      # flag that tells every LlmStrategy instance across every Solid Queue
      # worker that auth is currently broken.
      def auth_circuit_open?
        # `Rails.cache.exist?` is one round trip and doesn't materialize the
        # payload — tighter than `read(...).present?` and signals intent (we
        # only care that the flag is set, not its value).
        Rails.cache.exist?(AUTH_FAILURE_CACHE_KEY)
      end

      def trip_auth_circuit!(exception)
        Rails.cache.write(AUTH_FAILURE_CACHE_KEY, true, expires_in: AUTH_FAILURE_TTL)
        @logger.error(
          "[LlmStrategy] LLM auth failed — circuit open for #{AUTH_FAILURE_TTL.inspect}: " \
          "#{exception.class.name}: #{exception.message}"
        )
        Services::ErrorTrackingService.instance.track_exception(
          exception,
          strategy: "LlmStrategy",
          reason: "auth_failure_circuit_breaker_tripped"
        )
      rescue StandardError => track_err
        # Don't let a broken tracker mask the underlying auth failure. Log at
        # :error (not :warn) — losing the alert signal IS the outage this PR
        # exists to detect, so it must be visible in default log filters.
        @logger.error "[LlmStrategy] ErrorTrackingService.track_exception failed: #{track_err.class.name}: #{track_err.message}"
      end

      def normalize_merchant(expense)
        return "" unless expense.merchant_name?

        MerchantNormalizer.normalize(expense.merchant_name)
      end

      def lookup_cache(normalized)
        # PER-499: the model owns the composite cache key (merchant_normalized,
        # prompt_version, model_used). A prompt or model bump produces a miss
        # instead of silently returning a stale classification.
        LlmCategorizationCacheEntry.lookup_for(merchant_normalized: normalized)
      end

      def call_llm_and_cache(expense, normalized, start_time)
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
        store_cache(normalized, parsed, api_result, total_tokens)

        # Feed Layer 2 so similarity strategy learns from LLM results
        feed_vector_updater(expense, parsed[:category])

        build_llm_result(parsed, duration_ms(start_time))
      end

      # Throttles and retries LLM calls to handle Anthropic's token-per-minute
      # rate limit. Returns the API result on success, or nil on persistent failure.
      def call_with_rate_limit_handling(prompt)
        attempts = 0

        begin
          throttle!
          attempts += 1
          client.categorize(prompt_text: prompt)
        rescue Llm::Client::RateLimitError => e
          if attempts <= MAX_RETRIES
            # Prefer server-provided Retry-After when present — it's
            # authoritative about when the limit window resets. Fall back
            # to our fixed backoff schedule only when absent/invalid.
            sleep_s = e.retry_after || RETRY_BACKOFF_S[attempts - 1]
            source = e.retry_after ? "retry-after header" : "fixed backoff"
            @logger.warn("[LlmStrategy] Rate limited (attempt #{attempts}/#{MAX_RETRIES}), sleeping #{sleep_s}s (#{source})")
            sleep(sleep_s)
            retry
          else
            @logger.error("[LlmStrategy] Rate limited after #{MAX_RETRIES} retries — giving up")
            nil
          end
        end
      end

      # Enforce MIN_CALL_INTERVAL_S between LLM calls across ALL threads in
      # ALL processes (distributed throttle via Rails.cache / Solid Cache).
      #
      # Algorithm: each caller atomically reserves a monotonic "slot" via
      # Rails.cache.increment. Slot N fires at `epoch + (N - 1) *
      # MIN_CALL_INTERVAL_S`. The first caller in an epoch establishes
      # epoch_start. Because increment is atomic and the epoch is read via
      # fetch-or-write, every process + thread converges on the same slot
      # schedule without requiring a distributed mutex.
      #
      # The per-process mutex is kept as a cheap short-circuit — threads
      # in the same process serialize on it first to avoid hammering Solid
      # Cache when the local queue is hot.
      #
      # Disabled in test env to keep unit tests fast (tests that exercise
      # this directly unstub `Rails.env.test?`).
      def throttle!
        return if Rails.env.test?

        self.class.rate_limit_mutex.synchronize do
          my_slot = Rails.cache.increment(THROTTLE_SLOT_KEY, 1, expires_in: THROTTLE_STATE_TTL)

          # Some cache backends return nil when incrementing a missing key
          # (they auto-create starting at 1 but may not return the new
          # value). Guard so the strategy still throttles correctly even
          # on cache hiccups — worst case, we fall back to no-wait for
          # this single call instead of crashing.
          if my_slot.nil? || my_slot < 1
            @logger.warn("[LlmStrategy] Throttle slot reservation failed (cache returned #{my_slot.inspect}); proceeding without wait")
            return
          end

          epoch_start = Rails.cache.fetch(THROTTLE_EPOCH_KEY, expires_in: THROTTLE_STATE_TTL) { Time.now.to_f }
          my_slot_time = epoch_start + (my_slot - 1) * MIN_CALL_INTERVAL_S
          wait_s = my_slot_time - Time.now.to_f

          if wait_s.positive?
            @logger.debug("[LlmStrategy] Throttle slot=#{my_slot} waits #{wait_s.round(1)}s")
            sleep(wait_s)
          end
        end
      end

      def store_cache(normalized, parsed, api_result, total_tokens)
        # PER-499: the model owns the composite key. find_or_create_by! handles
        # the happy path; a concurrent writer that lost the race between find
        # and create raises RecordNotUnique, which we rescue and update the
        # winner's row. If the row was deleted between insert attempt and
        # rescue lookup (e.g. LlmCacheCleanupJob swept an expired entry),
        # find_by + safe-navigation silently drops the cache write — the
        # caller still has `parsed` and returns the categorization.
        key = LlmCategorizationCacheEntry.cache_key_for(merchant_normalized: normalized)
        attrs = {
          category: parsed[:category],
          confidence: parsed[:confidence],
          token_count: total_tokens,
          cost: api_result[:cost],
          expires_at: CACHE_TTL.from_now
        }

        entry = LlmCategorizationCacheEntry.find_or_create_by!(**key) do |e|
          e.assign_attributes(attrs)
        end
        entry.update!(attrs) unless entry.previously_new_record?
      rescue ActiveRecord::RecordNotUnique
        LlmCategorizationCacheEntry.find_by(**key)&.update!(attrs)
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
        current_spend_units = Rails.cache.read(budget_key).to_i
        (current_spend_units.to_f / BUDGET_UNITS_PER_USD) >= self.class.monthly_budget
      end

      def increment_budget(cost)
        # Atomic increment at the cache layer so concurrent workers cannot lose
        # updates to a read-modify-write race (PER-492). Rails.cache.increment
        # is integer-only, so we store cost in units of 1 / BUDGET_UNITS_PER_USD
        # of a USD (tenths of a cent) and rescale on read in #budget_exceeded?.
        units = (cost * BUDGET_UNITS_PER_USD).ceil
        return if units <= 0

        # `write(unless_exist: true)` atomically seeds the counter at 0 on the
        # first call of the month without overwriting an existing value. The
        # subsequent `increment` is then always against an existing integer
        # key — no `|| write` fallback race where two concurrent first-callers
        # both see `nil` and each `write(units)`, clobbering one update.
        Rails.cache.write(budget_key, 0, expires_in: BUDGET_TTL, unless_exist: true)
        Rails.cache.increment(budget_key, units, expires_in: BUDGET_TTL)
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
