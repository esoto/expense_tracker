require 'rails_helper'

RSpec.describe "API::WebhooksController", type: :request do
  let(:valid_token) { create(:api_token) }
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }

  before do
    # Set up API authentication headers
    @api_headers = {
      'Authorization' => "Bearer #{valid_token.token}",
      'Content-Type' => 'application/json'
    }
  end
end
