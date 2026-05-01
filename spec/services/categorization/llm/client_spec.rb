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
    # Every #initialize spec isolates ANTHROPIC_TIMEOUT_SECONDS so the suite
    # is not sensitive to the developer's or CI's ambient shell env.
    around do |example|
      original = ENV["ANTHROPIC_TIMEOUT_SECONDS"]
      ENV.delete("ANTHROPIC_TIMEOUT_SECONDS")
      begin
        example.run
      ensure
        ENV["ANTHROPIC_TIMEOUT_SECONDS"] = original
      end
    end

    it "creates an Anthropic client with the configured API key, no SDK retries, and a 30s default timeout" do
      allow(Anthropic::Client).to receive(:new).and_call_original

      client

      expect(Anthropic::Client).to have_received(:new).with(
        api_key: api_key,
        max_retries: 0,
        timeout: 30
      ).once
    end

    it "honors ANTHROPIC_TIMEOUT_SECONDS when set to a positive integer" do
      allow(Anthropic::Client).to receive(:new).and_call_original
      ENV["ANTHROPIC_TIMEOUT_SECONDS"] = "45"

      described_class.new

      expect(Anthropic::Client).to have_received(:new).with(
        api_key: api_key,
        max_retries: 0,
        timeout: 45
      )
    end

    # The whole point of PER-491 is to cap the timeout so a worker thread
    # cannot hang. A misconfigured env var that silently becomes 0, negative,
    # or garbage must NOT defeat that cap — it must fall back to the default.
    [
      [ "non-numeric string", "disabled" ],
      [ "empty string", "" ],
      [ "zero", "0" ],
      [ "negative integer", "-5" ]
    ].each do |label, value|
      it "falls back to the default timeout when ANTHROPIC_TIMEOUT_SECONDS is a #{label}" do
        allow(Anthropic::Client).to receive(:new).and_call_original
        ENV["ANTHROPIC_TIMEOUT_SECONDS"] = value

        described_class.new

        expect(Anthropic::Client).to have_received(:new).with(
          api_key: api_key,
          max_retries: 0,
          timeout: 30
        )
      end
    end

    it "raises an error when API key is not configured in credentials or ENV" do
      allow(Rails.application.credentials).to receive(:dig)
        .with(:anthropic, :api_key).and_return(nil)
      ENV.delete("ANTHROPIC_API_KEY")

      expect { described_class.new }.to raise_error(
        Services::Categorization::Llm::Client::ConfigurationError,
        /API key not configured/
      )
    end

    it "falls back to ENV['ANTHROPIC_API_KEY'] when credentials are blank (PER-548)" do
      # Production scenario: credentials.yml.enc has a stale/blank entry but
      # the operator pushed a fresh key via kamal env push. ENV must win.
      allow(Rails.application.credentials).to receive(:dig)
        .with(:anthropic, :api_key).and_return(nil)
      env_key = "env-fallback-key-456"
      ENV["ANTHROPIC_API_KEY"] = env_key
      allow(Anthropic::Client).to receive(:new).and_call_original

      begin
        described_class.new
      ensure
        ENV.delete("ANTHROPIC_API_KEY")
      end

      expect(Anthropic::Client).to have_received(:new).with(
        hash_including(api_key: env_key)
      )
    end

    it "prefers credentials over ENV when both are present" do
      # Credentials are the primary source of truth (encrypted at rest).
      # ENV is fallback only — flipping the precedence would mean a
      # forgotten dev shell could hijack the prod-resolved key path.
      ENV["ANTHROPIC_API_KEY"] = "should-not-be-used"
      allow(Anthropic::Client).to receive(:new).and_call_original

      begin
        described_class.new
      ensure
        ENV.delete("ANTHROPIC_API_KEY")
      end

      expect(Anthropic::Client).to have_received(:new).with(
        hash_including(api_key: api_key)
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

    context "when search continuations are exhausted" do
      let(:pause_usage) do
        double("Usage", input_tokens: 100, output_tokens: 5, server_tool_use: nil).tap do |u|
          allow(u).to receive(:respond_to?).with(:server_tool_use).and_return(false)
        end
      end
      let(:always_pause) do
        double("Message",
          content: [ double("Block").tap { |b|
            allow(b).to receive(:respond_to?).with(:text).and_return(false)
            allow(b).to receive(:respond_to?).with(:type).and_return(true)
            allow(b).to receive(:type).and_return("server_tool_use")
          } ],
          usage: pause_usage,
          stop_reason: "pause_turn")
      end

      before do
        allow(messages_api).to receive(:create).and_return(always_pause)
      end

      it "returns uncategorized after MAX_SEARCH_CONTINUATIONS" do
        result = client.categorize(prompt_text: prompt_text)

        expect(result[:response_text]).to eq("uncategorized")
        expect(messages_api).to have_received(:create).exactly(4).times # 1 initial + 3 continuations
      end
    end

    context "when response contains no recognizable category key" do
      let(:gibberish_block) do
        double("TextBlock", text: "I cannot determine what this merchant sells", type: "text").tap do |b|
          allow(b).to receive(:respond_to?).with(:text).and_return(true)
          allow(b).to receive(:respond_to?).with(:type).and_return(true)
        end
      end
      let(:gibberish_response) do
        double("Message", content: [ gibberish_block ], usage: usage, stop_reason: "end_turn")
      end

      before { allow(messages_api).to receive(:create).and_return(gibberish_response) }

      it "returns the raw text when no valid key is found" do
        result = client.categorize(prompt_text: prompt_text)

        expect(result[:response_text]).to eq("I cannot determine what this merchant sells")
      end
    end

    context "when response starts with a valid key followed by explanation" do
      let(:first_word_block) do
        double("TextBlock", text: "food - this is a local restaurant in Cartago", type: "text").tap do |b|
          allow(b).to receive(:respond_to?).with(:text).and_return(true)
          allow(b).to receive(:respond_to?).with(:type).and_return(true)
        end
      end
      let(:first_word_response) do
        double("Message", content: [ first_word_block ], usage: usage, stop_reason: "end_turn")
      end

      before { allow(messages_api).to receive(:create).and_return(first_word_response) }

      it "extracts the first word as the category key" do
        result = client.categorize(prompt_text: prompt_text)

        expect(result[:response_text]).to eq("food")
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
      def raise_rate_limit_with_headers(headers)
        allow(messages_api).to receive(:create)
          .and_raise(Anthropic::Errors::RateLimitError.new(
            url: "https://api.anthropic.com/v1/messages",
            status: 429, body: "rate limited",
            headers: headers, request: nil, response: {}
          ))
      end

      it "raises a RateLimitError" do
        raise_rate_limit_with_headers({})
        expect { client.categorize(prompt_text: prompt_text) }.to raise_error(
          Services::Categorization::Llm::Client::RateLimitError, /Rate limit exceeded/
        )
      end

      it "extracts integer retry-after header into the raised error" do
        raise_rate_limit_with_headers({ "retry-after" => "42" })

        expect { client.categorize(prompt_text: prompt_text) }
          .to raise_error(Services::Categorization::Llm::Client::RateLimitError) { |e|
            expect(e.retry_after).to eq(42)
          }
      end

      it "falls back to nil retry_after when header is absent" do
        raise_rate_limit_with_headers({})

        expect { client.categorize(prompt_text: prompt_text) }
          .to raise_error(Services::Categorization::Llm::Client::RateLimitError) { |e|
            expect(e.retry_after).to be_nil
          }
      end

      it "ignores non-numeric or malformed retry-after" do
        raise_rate_limit_with_headers({ "retry-after" => "soon" })

        expect { client.categorize(prompt_text: prompt_text) }
          .to raise_error(Services::Categorization::Llm::Client::RateLimitError) { |e|
            expect(e.retry_after).to be_nil
          }
      end

      it "ignores unreasonably large retry-after (> 10 min) to protect worker processes" do
        raise_rate_limit_with_headers({ "retry-after" => "3600" })

        expect { client.categorize(prompt_text: prompt_text) }
          .to raise_error(Services::Categorization::Llm::Client::RateLimitError) { |e|
            expect(e.retry_after).to be_nil
          }
      end

      it "accepts Retry-After with uppercase header name" do
        raise_rate_limit_with_headers({ "Retry-After" => "5" })

        expect { client.categorize(prompt_text: prompt_text) }
          .to raise_error(Services::Categorization::Llm::Client::RateLimitError) { |e|
            expect(e.retry_after).to eq(5)
          }
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
