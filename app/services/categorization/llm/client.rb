# frozen_string_literal: true

require "anthropic"

module Services::Categorization
  module Llm
    class Client
      MODEL = "claude-haiku-4-5"
      MAX_TOKENS = 100
      MAX_SEARCH_CONTINUATIONS = 3
      INPUT_COST_PER_TOKEN = 1.00 / 1_000_000.0
      OUTPUT_COST_PER_TOKEN = 5.00 / 1_000_000.0
      SEARCH_COST_PER_QUERY = 10.0 / 1_000.0 # $10 per 1000 searches
      DEFAULT_TIMEOUT_S = 30

      # Custom error hierarchy
      class Error < StandardError; end
      class ConfigurationError < Error; end
      class AuthenticationError < Error; end
      class RateLimitError < Error
        # Seconds to wait before retrying, parsed from the Retry-After response
        # header when the Anthropic SDK surfaces it. nil when absent or invalid
        # (caller should fall back to a fixed backoff schedule).
        attr_reader :retry_after

        def initialize(message, retry_after: nil)
          super(message)
          @retry_after = retry_after
        end
      end
      class TimeoutError < Error; end
      class ApiError < Error; end

      # @param client [Anthropic::Client, nil] injectable for testing
      def initialize(client: nil)
        if client
          @client = client
        else
          # Credentials first (encrypted in repo), then ENV fallback so the
          # key can be rotated via `kamal env push` without rebuilding the
          # image. Without the ENV branch a stale credentials entry silently
          # 401s on every call (PER-548).
          api_key = Rails.application.credentials.dig(:anthropic, :api_key).presence ||
                    ENV["ANTHROPIC_API_KEY"].presence
          raise ConfigurationError, "Anthropic API key not configured" unless api_key

          @client = Anthropic::Client.new(
            api_key: api_key,
            max_retries: 0,
            timeout: self.class.anthropic_timeout
          )
        end
      end

      # Resolves the Anthropic SDK timeout with defensive parsing so that an
      # invalid ANTHROPIC_TIMEOUT_SECONDS cannot produce a 0s timeout (which
      # would hard-fail every request and defeat the B1 mitigation).
      def self.anthropic_timeout
        value = Integer(ENV.fetch("ANTHROPIC_TIMEOUT_SECONDS", nil), 10)
        value.positive? ? value : DEFAULT_TIMEOUT_S
      rescue TypeError, ArgumentError
        DEFAULT_TIMEOUT_S
      end

      def categorize(prompt_text:)
        messages = [ { role: :user, content: prompt_text } ]
        total_input = 0
        total_output = 0
        total_searches = 0

        # Server tools may require continuation when stop_reason is "pause_turn".
        # Loop until we get an "end_turn" or hit the continuation limit.
        (MAX_SEARCH_CONTINUATIONS + 1).times do
          response = @client.messages.create(
            model: MODEL,
            max_tokens: MAX_TOKENS,
            temperature: 0.0,
            system: PromptBuilder::SYSTEM_INSTRUCTION,
            tools: [ { type: "web_search_20250305", name: "web_search" } ],
            messages: messages
          )

          total_input += response.usage.input_tokens
          total_output += response.usage.output_tokens
          total_searches += extract_search_count(response)

          # If the model is done, extract the final answer
          if response.stop_reason != "pause_turn"
            response_text = extract_final_text(response)
            response_text = extract_category_key(response_text)

            return {
              response_text: response_text,
              token_count: { input: total_input, output: total_output },
              cost: calculate_cost(total_input, total_output, total_searches)
            }
          end

          # Continue the turn: append assistant response and re-submit
          messages << { role: :assistant, content: response.content }
        end

        # Exhausted continuations — return uncategorized
        Rails.logger.warn("[LLM::Client] Exhausted #{MAX_SEARCH_CONTINUATIONS} search continuations")
        {
          response_text: "uncategorized",
          token_count: { input: total_input, output: total_output },
          cost: calculate_cost(total_input, total_output, total_searches)
        }
      rescue Anthropic::Errors::AuthenticationError => e
        Rails.logger.error("[LLM::Client] Authentication failed: #{e.message}")
        raise AuthenticationError, "Authentication failed: #{e.message}"
      rescue Anthropic::Errors::RateLimitError => e
        retry_after = parse_retry_after(e)
        Rails.logger.warn("[LLM::Client] Rate limit exceeded: #{e.message} (retry_after=#{retry_after.inspect}s)")
        raise RateLimitError.new("Rate limit exceeded: #{e.message}", retry_after: retry_after)
      rescue Anthropic::Errors::APITimeoutError => e
        Rails.logger.warn("[LLM::Client] Request timed out: #{e.message}")
        raise TimeoutError, "Request timed out: #{e.message}"
      rescue Anthropic::Errors::APIError => e
        Rails.logger.error("[LLM::Client] API error: #{e.message}")
        raise ApiError, "API error: #{e.message}"
      end

      private

      # Parse the Retry-After header from an Anthropic SDK error. Accepts
      # an integer number of seconds (the common form from Anthropic), or
      # an HTTP-date per RFC 7231. Returns nil if the header is missing,
      # malformed, non-positive, or unreasonably large (> 10 min — we'd
      # rather fall back to our own backoff than sleep a Solid Queue worker
      # for hours on a malformed response).
      MAX_RETRY_AFTER_SECONDS = 600

      def parse_retry_after(anthropic_error)
        headers = anthropic_error.headers rescue nil
        return nil unless headers.respond_to?(:[])

        raw = headers["retry-after"] || headers["Retry-After"]
        return nil if raw.nil? || raw.to_s.empty?

        seconds = Integer(raw.to_s, 10)
        return nil if seconds <= 0 || seconds > MAX_RETRY_AFTER_SECONDS

        seconds
      rescue ArgumentError, TypeError
        # HTTP-date fallback — rare for Anthropic, but RFC 7231 allows it.
        begin
          delta = Time.httpdate(raw.to_s) - Time.now
          delta.positive? && delta <= MAX_RETRY_AFTER_SECONDS ? delta.ceil : nil
        rescue ArgumentError
          nil
        end
      end

      def extract_final_text(response)
        text_blocks = response.content.select { |block| block.respond_to?(:text) }
        raise ApiError, "Empty response from API" if text_blocks.empty?

        text = text_blocks.last.text
        raise ApiError, "Nil text in response" unless text

        text.strip
      end

      # Extract just the category key from a potentially verbose response.
      def extract_category_key(text)
        @valid_keys ||= Category.where.not(i18n_key: [ nil, "" ]).pluck(:i18n_key).to_set

        # First try: the whole response (stripped) is a valid key
        return text if @valid_keys.include?(text)

        # Second try: first word is the key
        first_word = text.split(/[\s\n]/).first&.downcase
        return first_word if first_word && @valid_keys.include?(first_word)

        # Third try: find the longest matching key as a whole word in the response.
        # Sort by length descending to prefer "hardware_store" over "home".
        found = @valid_keys
          .select { |key| text.downcase.match?(/\b#{Regexp.escape(key)}\b/) }
          .max_by(&:length)
        return found if found

        # Give up — return the raw text and let the caller handle it
        text
      end

      def extract_search_count(response)
        # Prefer the usage field if available (accurate billing count)
        if response.usage.respond_to?(:server_tool_use)
          server_usage = response.usage.server_tool_use
          return server_usage.web_search_requests if server_usage.respond_to?(:web_search_requests)
        end

        # Fallback: count server_tool_use blocks in content
        response.content.count { |b| b.respond_to?(:type) && b.type == "server_tool_use" }
      end

      def calculate_cost(input_tokens, output_tokens, search_count)
        token_cost = (input_tokens * INPUT_COST_PER_TOKEN) + (output_tokens * OUTPUT_COST_PER_TOKEN)
        token_cost + (search_count * SEARCH_COST_PER_QUERY)
      end
    end
  end
end
