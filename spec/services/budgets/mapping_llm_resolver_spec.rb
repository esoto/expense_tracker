# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Budgets::MappingLlmResolver, :unit do
  let(:user) { create(:user) }
  let!(:electricidad) { create(:category, name: "Electricidad", user: nil) }
  let!(:mascotas) { create(:category, name: "Mascotas", user: nil) }
  let(:categories) { [ electricidad, mascotas ] }
  let(:messages_api) { double("messages") }
  let(:client) { instance_double(Anthropic::Client, messages: messages_api) }
  subject(:resolver) { described_class.new(client: client) }

  def stub_llm_text(text)
    content_block = double("content", type: "text", text: text)
    response = double("response", content: [ content_block ], stop_reason: "end_turn")
    allow(messages_api).to receive(:create).and_return(response)
  end

  it "maps names to categories and allocations from a JSON response" do
    stub_llm_text('[{"name":"luz","answer":"Electricidad"},{"name":"familia mariana","answer":"ALLOCATION"}]')

    result = resolver.resolve(names: [ "luz", "familia mariana" ], categories: categories, user: user)

    expect(result["luz"]).to eq(category: electricidad, kind: :category)
    expect(result["familia mariana"]).to eq(category: nil, kind: :allocation)
  end

  it "omits UNKNOWN answers and answers naming nonexistent categories" do
    stub_llm_text('[{"name":"punta leona","answer":"UNKNOWN"},{"name":"x","answer":"Invented Category"}]')

    result = resolver.resolve(names: [ "punta leona", "x" ], categories: categories, user: user)

    expect(result).to eq({})
  end

  it "tolerates a fenced JSON response" do
    stub_llm_text("```json\n[{\"name\":\"luz\",\"answer\":\"Electricidad\"}]\n```")

    result = resolver.resolve(names: [ "luz" ], categories: categories, user: user)

    expect(result["luz"]).to eq(category: electricidad, kind: :category)
  end

  it "re-normalizes echoed names so a non-verbatim echo still resolves" do
    stub_llm_text('[{"name":"LUZ ","answer":"Electricidad"}]')

    result = resolver.resolve(names: [ "luz" ], categories: categories, user: user)

    expect(result["luz"]).to eq(category: electricidad, kind: :category)
  end

  it "returns {} and logs on malformed JSON" do
    stub_llm_text("I think Luz is electricity related")
    allow(Rails.logger).to receive(:error)

    expect(resolver.resolve(names: [ "luz" ], categories: categories, user: user)).to eq({})
    expect(Rails.logger).to have_received(:error).with(/malformed/i)
  end

  it "returns {} for empty names without calling the API" do
    expect(messages_api).not_to receive(:create)
    expect(resolver.resolve(names: [], categories: categories, user: user)).to eq({})
  end
end
