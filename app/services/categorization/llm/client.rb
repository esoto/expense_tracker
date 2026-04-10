# frozen_string_literal: true

require "anthropic"

module Services::Categorization
  module Llm
    class Client
      MODEL = "claude-haiku-4-5"
      MAX_TOKENS = 50
      INPUT_COST_PER_TOKEN = 0.25 / 1_000_000.0
      OUTPUT_COST_PER_TOKEN = 1.25 / 1_000_000.0

      # Custom error hierarchy
      class Error < StandardError; end
      class ConfigurationError < Error; end
      class AuthenticationError < Error; end
      class RateLimitError < Error; end
      class TimeoutError < Error; end
      class ApiError < Error; end

      def initialize
        api_key = Rails.application.credentials.dig(:anthropic, :api_key)
        raise ConfigurationError, "Anthropic API key not configured" unless api_key

        @client = Anthropic::Client.new(api_key: api_key)
      end

      def categorize(prompt_text:)
        response = @client.messages.create(
          model: MODEL,
          max_tokens: MAX_TOKENS,
          temperature: 0.0,
          messages: [ { role: :user, content: prompt_text } ]
        )

        response_text = response.content.first.text
        input_tokens = response.usage.input_tokens
        output_tokens = response.usage.output_tokens

        {
          response_text: response_text,
          token_count: { input: input_tokens, output: output_tokens },
          cost: (input_tokens * INPUT_COST_PER_TOKEN) + (output_tokens * OUTPUT_COST_PER_TOKEN)
        }
      rescue Anthropic::Errors::AuthenticationError => e
        raise AuthenticationError, "Authentication failed: #{e.message}"
      rescue Anthropic::Errors::RateLimitError => e
        raise RateLimitError, "Rate limit exceeded: #{e.message}"
      rescue Anthropic::Errors::APITimeoutError => e
        raise TimeoutError, "Request timed out: #{e.message}"
      rescue Anthropic::Errors::APIError => e
        raise ApiError, "API error: #{e.message}"
      end
    end
  end
end
