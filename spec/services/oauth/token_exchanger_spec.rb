# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe Services::Oauth::TokenExchanger, :unit do
  let(:base_url) { "https://salary-calc.estebansoto.dev" }
  let(:code) { "xyz" }
  let(:redirect_uri) { "https://example.test/external_source/callback" }

  subject(:exchanger) do
    described_class.new(base_url: base_url, code: code, redirect_uri: redirect_uri)
  end

  describe "#call" do
    context "when the server returns 200 with valid JSON" do
      before do
        stub_request(:post, "#{base_url}/oauth/token")
          .with(body: hash_including(
            "grant_type" => "authorization_code",
            "code" => code,
            "redirect_uri" => redirect_uri
          ))
          .to_return(
            status: 200,
            body: { access_token: "abc", token_type: "Bearer", scope: "budget:read" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns the parsed token payload with symbolized keys" do
        result = exchanger.call
        expect(result).to eq(access_token: "abc", token_type: "Bearer", scope: "budget:read")
      end
    end

    context "when the server returns a non-200 response" do
      before do
        stub_request(:post, "#{base_url}/oauth/token")
          .to_return(status: 401, body: "invalid code")
      end

      it "raises Error with status=401 in the message" do
        expect { exchanger.call }.to raise_error(described_class::Error, /status=401/)
      end
    end

    context "when the network connection fails" do
      before do
        stub_request(:post, "#{base_url}/oauth/token")
          .to_raise(Errno::ECONNREFUSED)
      end

      it "raises Error with 'network:' prefix" do
        expect { exchanger.call }.to raise_error(described_class::Error, /network:/)
      end
    end

    context "when the server returns invalid JSON" do
      before do
        stub_request(:post, "#{base_url}/oauth/token")
          .to_return(status: 200, body: "not json")
      end

      it "raises Error with 'invalid JSON' in the message" do
        expect { exchanger.call }.to raise_error(described_class::Error, /invalid JSON/)
      end
    end
  end
end
