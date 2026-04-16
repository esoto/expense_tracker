# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Llm::Client, :unit do
  subject(:client) { described_class.new }

  let(:api_key) { "test-api-key-123" }
  let(:prompt_text) { "Categories:\n- food\n\nTransaction:\nMerchant: Test" }

  before do
    allow(Rails.application.credentials).to receive(:dig)
      .with(:anthropic, :api_key).and_return(api_key)

    # Stub valid keys for extract_category_key
    not_relation = double("NotRelation", pluck: %w[food restaurants supermarket uncategorized hardware_store])
    where_relation = double("WhereRelation", not: not_relation)
    allow(Category).to receive(:where).and_return(where_relation)
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
    let(:usage) { double("Usage", input_tokens: 150, output_tokens: 10, server_tool_use: nil) }
    let(:text_block) { double("TextBlock", text: "food", type: "text") }
    let(:response) do
      double("Message", content: [ text_block ], usage: usage, stop_reason: "end_turn")
    end

    before do
      allow(Anthropic::Client).to receive(:new).and_return(anthropic_client)
      allow(anthropic_client).to receive(:messages).and_return(messages_api)
      allow(messages_api).to receive(:create).and_return(response)
      allow(text_block).to receive(:respond_to?).with(:text).and_return(true)
      allow(text_block).to receive(:respond_to?).with(:type).and_return(true)
      allow(usage).to receive(:respond_to?).with(:server_tool_use).and_return(false)
    end

    it "sends the prompt with web search tool and system prompt" do
      result = client.categorize(prompt_text: prompt_text)

      expect(messages_api).to have_received(:create).with(
        hash_including(
          model: "claude-haiku-4-5",
          max_tokens: 100,
          temperature: 0.0,
          system: Services::Categorization::Llm::PromptBuilder::SYSTEM_INSTRUCTION,
          tools: [ { type: "web_search_20250305", name: "web_search" } ]
        )
      )
      expect(result[:response_text]).to eq("food")
    end

    it "returns token count in the result" do
      result = client.categorize(prompt_text: prompt_text)

      expect(result[:token_count]).to eq(input: 150, output: 10)
    end

    it "calculates cost with Haiku 4.5 pricing" do
      result = client.categorize(prompt_text: prompt_text)

      # input: 150 * $1.00/MTok = 0.00015
      # output: 10 * $5.00/MTok = 0.00005
      expected_cost = (150 * 1.00 / 1_000_000.0) + (10 * 5.00 / 1_000_000.0)
      expect(result[:cost]).to be_within(0.0000001).of(expected_cost)
    end

    it "extracts category key from verbose response" do
      verbose_block = double("TextBlock",
        text: "Based on my search, this is a hardware_store in Costa Rica.",
        type: "text")
      allow(verbose_block).to receive(:respond_to?).with(:text).and_return(true)
      allow(verbose_block).to receive(:respond_to?).with(:type).and_return(true)
      verbose_response = double("Message", content: [ verbose_block ], usage: usage, stop_reason: "end_turn")
      allow(messages_api).to receive(:create).and_return(verbose_response)

      result = client.categorize(prompt_text: prompt_text)

      expect(result[:response_text]).to eq("hardware_store")
    end

    it "prefers longer key matches to avoid substring collisions" do
      ambiguous_block = double("TextBlock",
        text: "This is a hardware_store, not a regular home store.",
        type: "text")
      allow(ambiguous_block).to receive(:respond_to?).with(:text).and_return(true)
      allow(ambiguous_block).to receive(:respond_to?).with(:type).and_return(true)
      ambiguous_response = double("Message", content: [ ambiguous_block ], usage: usage, stop_reason: "end_turn")
      allow(messages_api).to receive(:create).and_return(ambiguous_response)

      result = client.categorize(prompt_text: prompt_text)

      expect(result[:response_text]).to eq("hardware_store")
    end

    context "when stop_reason is pause_turn (web search in progress)" do
      let(:search_block) { double("ServerToolUse", type: "server_tool_use") }
      let(:pause_response) do
        double("Message",
          content: [ search_block ],
          usage: double("Usage", input_tokens: 500, output_tokens: 5,
            server_tool_use: nil).tap { |u| allow(u).to receive(:respond_to?).with(:server_tool_use).and_return(false) },
          stop_reason: "pause_turn")
      end
      let(:final_response) do
        double("Message", content: [ text_block ], usage: usage, stop_reason: "end_turn")
      end

      before do
        allow(search_block).to receive(:respond_to?).with(:text).and_return(false)
        allow(search_block).to receive(:respond_to?).with(:type).and_return(true)
        allow(messages_api).to receive(:create).and_return(pause_response, final_response)
      end

      it "continues the turn and returns the final category" do
        result = client.categorize(prompt_text: prompt_text)

        expect(messages_api).to have_received(:create).twice
        expect(result[:response_text]).to eq("food")
        expect(result[:token_count][:input]).to eq(650) # 500 + 150
      end
    end

    context "when the API returns an authentication error" do
      before do
        allow(messages_api).to receive(:create)
          .and_raise(Anthropic::Errors::AuthenticationError.new(
            url: "https://api.anthropic.com/v1/messages",
            status: 401, body: "invalid api key",
            headers: {}, request: nil, response: {}
          ))
      end

      it "raises an AuthenticationError" do
        expect { client.categorize(prompt_text: prompt_text) }.to raise_error(
          Services::Categorization::Llm::Client::AuthenticationError, /Authentication failed/
        )
      end
    end

    context "when the API returns a rate limit error" do
      before do
        allow(messages_api).to receive(:create)
          .and_raise(Anthropic::Errors::RateLimitError.new(
            url: "https://api.anthropic.com/v1/messages",
            status: 429, body: "rate limited",
            headers: {}, request: nil, response: {}
          ))
      end

      it "raises a RateLimitError" do
        expect { client.categorize(prompt_text: prompt_text) }.to raise_error(
          Services::Categorization::Llm::Client::RateLimitError, /Rate limit exceeded/
        )
      end
    end

    context "when the API times out" do
      before do
        allow(messages_api).to receive(:create)
          .and_raise(Anthropic::Errors::APITimeoutError.new(
            url: "https://api.anthropic.com/v1/messages", request: nil
          ))
      end

      it "raises a TimeoutError" do
        expect { client.categorize(prompt_text: prompt_text) }.to raise_error(
          Services::Categorization::Llm::Client::TimeoutError, /Request timed out/
        )
      end
    end

    context "when the API returns a server error" do
      before do
        allow(messages_api).to receive(:create)
          .and_raise(Anthropic::Errors::APIStatusError.new(
            url: "https://api.anthropic.com/v1/messages",
            status: 500, body: "internal server error",
            headers: {}, request: nil, response: {}
          ))
      end

      it "raises an ApiError" do
        expect { client.categorize(prompt_text: prompt_text) }.to raise_error(
          Services::Categorization::Llm::Client::ApiError, /API error/
        )
      end
    end

    context "when a network connection error occurs" do
      before do
        allow(messages_api).to receive(:create)
          .and_raise(Anthropic::Errors::APIConnectionError.new(
            url: "https://api.anthropic.com/v1/messages", request: nil
          ))
      end

      it "raises an ApiError" do
        expect { client.categorize(prompt_text: prompt_text) }.to raise_error(
          Services::Categorization::Llm::Client::ApiError, /API error/
        )
      end
    end
  end
end
