# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Llm::Client, :unit do
  subject(:client) { described_class.new }

  let(:api_key) { "test-api-key-123" }
  let(:prompt_text) { "You are an expense categorizer..." }

  before do
    allow(Rails.application.credentials).to receive(:dig)
      .with(:anthropic, :api_key).and_return(api_key)
  end

  describe "#initialize" do
    it "creates an Anthropic client with the configured API key" do
      allow(Anthropic::Client).to receive(:new)
        .with(api_key: api_key).and_call_original

      client

      expect(Anthropic::Client).to have_received(:new).with(api_key: api_key)
    end

    it "raises an error when API key is not configured" do
      allow(Rails.application.credentials).to receive(:dig)
        .with(:anthropic, :api_key).and_return(nil)

      expect { described_class.new }.to raise_error(
        Services::Categorization::Llm::Client::ConfigurationError,
        /API key not configured/
      )
    end
  end

  describe "#categorize" do
    let(:anthropic_client) { instance_double(Anthropic::Client) }
    let(:messages_api) { instance_double(Anthropic::Resources::Messages) }
    let(:usage) { double("Usage", input_tokens: 150, output_tokens: 10) }
    let(:text_block) { double("TextBlock", text: "food") }
    let(:response) do
      double("Message", content: [ text_block ], usage: usage)
    end

    before do
      allow(Anthropic::Client).to receive(:new).and_return(anthropic_client)
      allow(anthropic_client).to receive(:messages).and_return(messages_api)
      allow(messages_api).to receive(:create).and_return(response)
    end

    it "sends the prompt to Claude Haiku and returns the response" do
      result = client.categorize(prompt_text: prompt_text)

      expect(messages_api).to have_received(:create).with(
        model: "claude-haiku-4-5",
        max_tokens: 50,
        temperature: 0.0,
        messages: [ { role: :user, content: prompt_text } ]
      )
      expect(result[:response_text]).to eq("food")
    end

    it "returns token count in the result" do
      result = client.categorize(prompt_text: prompt_text)

      expect(result[:token_count]).to eq(input: 150, output: 10)
    end

    it "calculates cost based on token usage" do
      result = client.categorize(prompt_text: prompt_text)

      # input: 150 * $0.25/1M = 0.0000375
      # output: 10 * $1.25/1M = 0.0000125
      expected_cost = (150 * 0.25 / 1_000_000.0) + (10 * 1.25 / 1_000_000.0)
      expect(result[:cost]).to be_within(0.0000001).of(expected_cost)
    end

    context "when the API returns an authentication error" do
      before do
        allow(messages_api).to receive(:create)
          .and_raise(Anthropic::Errors::AuthenticationError.new(
            url: "https://api.anthropic.com/v1/messages",
            status: 401,
            body: "invalid api key",
            headers: {},
            request: nil,
            response: {}
          ))
      end

      it "raises an AuthenticationError" do
        expect { client.categorize(prompt_text: prompt_text) }.to raise_error(
          Services::Categorization::Llm::Client::AuthenticationError,
          /Authentication failed/
        )
      end
    end

    context "when the API returns a rate limit error" do
      before do
        allow(messages_api).to receive(:create)
          .and_raise(Anthropic::Errors::RateLimitError.new(
            url: "https://api.anthropic.com/v1/messages",
            status: 429,
            body: "rate limited",
            headers: {},
            request: nil,
            response: {}
          ))
      end

      it "raises a RateLimitError" do
        expect { client.categorize(prompt_text: prompt_text) }.to raise_error(
          Services::Categorization::Llm::Client::RateLimitError,
          /Rate limit exceeded/
        )
      end
    end

    context "when the API times out" do
      before do
        allow(messages_api).to receive(:create)
          .and_raise(Anthropic::Errors::APITimeoutError.new(url: "https://api.anthropic.com/v1/messages", request: nil))
      end

      it "raises a TimeoutError" do
        expect { client.categorize(prompt_text: prompt_text) }.to raise_error(
          Services::Categorization::Llm::Client::TimeoutError,
          /Request timed out/
        )
      end
    end

    context "when the API returns a server error" do
      before do
        allow(messages_api).to receive(:create)
          .and_raise(Anthropic::Errors::APIStatusError.new(
            url: "https://api.anthropic.com/v1/messages",
            status: 500,
            body: "internal server error",
            headers: {},
            request: nil,
            response: {}
          ))
      end

      it "raises an ApiError with the status details" do
        expect { client.categorize(prompt_text: prompt_text) }.to raise_error(
          Services::Categorization::Llm::Client::ApiError,
          /API error/
        )
      end
    end

    context "when a network connection error occurs" do
      before do
        allow(messages_api).to receive(:create)
          .and_raise(Anthropic::Errors::APIConnectionError.new(
            url: "https://api.anthropic.com/v1/messages",
            request: nil
          ))
      end

      it "raises an ApiError" do
        expect { client.categorize(prompt_text: prompt_text) }.to raise_error(
          Services::Categorization::Llm::Client::ApiError,
          /API error/
        )
      end
    end
  end
end
