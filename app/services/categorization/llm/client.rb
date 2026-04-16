# frozen_string_literal: true

require "anthropic"

module Services::Categorization
  module Llm
    class Client
      MODEL = "claude-haiku-4-5"
      MAX_TOKENS = 100
      INPUT_COST_PER_TOKEN = 0.80 / 1_000_000.0
      OUTPUT_COST_PER_TOKEN = 4.00 / 1_000_000.0
      SEARCH_COST_PER_QUERY = 10.0 / 1_000.0 # $10 per 1000 searches

      # Custom error hierarchy
      class Error < StandardError; end
      class ConfigurationError < Error; end
      class AuthenticationError < Error; end
      class RateLimitError < Error; end
      class TimeoutError < Error; end
      class ApiError < Error; end

      # @param client [Anthropic::Client, nil] injectable for testing
      def initialize(client: nil)
        if client
          @client = client
        else
          api_key = Rails.application.credentials.dig(:anthropic, :api_key)
          raise ConfigurationError, "Anthropic API key not configured" unless api_key

          @client = Anthropic::Client.new(api_key: api_key)
        end
      end

      def categorize(prompt_text:)
        response = @client.messages.create(
          model: MODEL,
          max_tokens: MAX_TOKENS,
          temperature: 0.0,
          system: PromptBuilder::SYSTEM_INSTRUCTION,
          tools: [ { type: "web_search_20250305", name: "web_search" } ],
          messages: [ { role: :user, content: prompt_text } ]
        )

        # Response may contain multiple content blocks: tool_use, tool_result, text.
        # Extract the final text block which contains the category key.
        text_blocks = response.content.select { |block| block.respond_to?(:text) }
        raise ApiError, "Empty response from API" if text_blocks.empty?

        response_text = text_blocks.last.text.strip
        input_tokens = response.usage.input_tokens
        output_tokens = response.usage.output_tokens

        # Extract just the category key if the model returned extra text
        response_text = extract_category_key(response_text)

        {
          response_text: response_text,
          token_count: { input: input_tokens, output: output_tokens },
          cost: calculate_cost(input_tokens, output_tokens, response.content)
        }
      rescue Anthropic::Errors::AuthenticationError => e
        Rails.logger.error("[LLM::Client] Authentication failed: #{e.message}")
        raise AuthenticationError, "Authentication failed: #{e.message}"
      rescue Anthropic::Errors::RateLimitError => e
        Rails.logger.warn("[LLM::Client] Rate limit exceeded: #{e.message}")
        raise RateLimitError, "Rate limit exceeded: #{e.message}"
      rescue Anthropic::Errors::APITimeoutError => e
        Rails.logger.warn("[LLM::Client] Request timed out: #{e.message}")
        raise TimeoutError, "Request timed out: #{e.message}"
      rescue Anthropic::Errors::APIError => e
        Rails.logger.error("[LLM::Client] API error: #{e.message}")
        raise ApiError, "API error: #{e.message}"
      end

      private

      # Extract just the category key from a potentially verbose response.
      # The model sometimes returns explanations despite the "ONLY the key" instruction.
      def extract_category_key(text)
        # Load valid keys once
        @valid_keys ||= Category.where.not(i18n_key: [ nil, "" ]).pluck(:i18n_key).to_set

        # First try: the whole response is a valid key
        return text if @valid_keys.include?(text)

        # Second try: first word/line is the key
        first_word = text.split(/[\s\n]/).first&.downcase
        return first_word if first_word && @valid_keys.include?(first_word)

        # Third try: scan for any valid key in the response
        @valid_keys.each do |key|
          return key if text.downcase.include?(key)
        end

        # Give up — return the raw text and let the caller handle it
        text
      end

      def calculate_cost(input_tokens, output_tokens, content_blocks)
        token_cost = (input_tokens * INPUT_COST_PER_TOKEN) + (output_tokens * OUTPUT_COST_PER_TOKEN)

        # Count web searches (tool_use blocks with web_search)
        search_count = content_blocks.count { |b| b.respond_to?(:type) && b.type == "server_tool_use" }
        search_cost = search_count * SEARCH_COST_PER_QUERY

        token_cost + search_cost
      end
    end
  end
end
