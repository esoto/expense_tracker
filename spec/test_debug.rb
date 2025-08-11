require 'rails_helper'

RSpec.describe "Debug API test", type: :request do
  include ApiHelpers

  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }
  let(:endpoint) { "/api/webhooks/add_expense" }
  let(:valid_payload) do
    expense_webhook_payload(
      amount: 15000.50,
      description: "Test expense",
      currency: "CRC",
      date: Date.current.to_s,
      category: category.name
    )
  end

  it "debugs the API call" do
    puts "\n=== DEBUG INFO ==="
    puts "Endpoint: #{endpoint}"
    puts "Payload: #{valid_payload.inspect}"

    headers = api_headers
    puts "Headers: #{headers.inspect}"

    post endpoint, params: valid_payload.to_json, headers: headers

    puts "Response status: #{response.status}"
    puts "Response body: #{response.body}"
    puts "Response headers: #{response.headers.to_h.select { |k, v| k.start_with?('X-') }}"

    if response.body.present?
      begin
        json = JSON.parse(response.body)
        puts "Parsed JSON: #{json.inspect}"
      rescue => e
        puts "JSON parse error: #{e.message}"
      end
    end
    puts "=== END DEBUG ==="
  end
end
