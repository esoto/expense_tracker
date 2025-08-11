# API Testing Helpers
# Provides utilities for testing API endpoints, particularly for iPhone Shortcuts integration

module ApiHelpers
  # Authentication helpers
  def valid_api_token
    @valid_api_token ||= create(:api_token)
  end

  def expired_api_token
    @expired_api_token ||= create(:api_token, expires_at: 1.day.ago)
  end

  def api_headers(token = nil)
    token ||= valid_api_token
    {
      'Authorization' => "Bearer #{token.token}",
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }
  end

  def unauthorized_headers
    {
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }
  end

  def api_request(method, path, params = {}, headers = {})
    headers = api_headers.merge(headers)

    case method
    when :get
      get path, params: params, headers: headers
    when :post
      post path, params: params.to_json, headers: headers
    when :put
      put path, params: params.to_json, headers: headers
    when :patch
      patch path, params: params.to_json, headers: headers
    when :delete
      delete path, params: params, headers: headers
    end
  end

  # Response helpers
  def json_response
    @json_response ||= JSON.parse(response.body, symbolize_names: true)
  rescue JSON::ParserError
    {}
  end

  def expect_json_response(status: 200)
    if status.is_a?(Array)
      expect(status).to include(response.status)
    else
      expect(response).to have_http_status(status)
    end
    expect(response.content_type).to include('application/json')
    json_response
  end

  def expect_successful_json_response
    expect_json_response(status: 200)
  end

  def expect_created_json_response
    expect_json_response(status: 201)
  end

  def expect_unauthorized_response
    expect(response).to have_http_status(:unauthorized)
    expect(json_response).to include(error: match(/unauthorized|token/i))
  end

  def expect_forbidden_response
    expect(response).to have_http_status(:forbidden)
  end

  def expect_not_found_response
    expect(response).to have_http_status(:not_found)
  end

  def expect_validation_error_response
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response).to have_key(:errors)
  end

  def expect_rate_limit_response
    expect(response).to have_http_status(:too_many_requests)
    expect(json_response).to include(error: match(/rate limit/i))
  end

  # iPhone Shortcuts specific helpers
  def iphone_shortcut_headers
    api_headers.merge(
      'User-Agent' => 'Shortcuts/1.0',
      'X-Shortcuts-Version' => '1.0'
    )
  end

  def expense_webhook_payload(amount:, description:, **options)
    {
      expense: {
        amount: amount,
        description: description,
        merchant_name: options[:merchant_name] || 'Test Merchant',
        transaction_date: options[:date] || Date.current.to_s,
        category_id: options[:category_id]
      },
      currency: options[:currency] || 'CRC',
      source: options[:source] || 'iPhone Shortcuts',
      metadata: options[:metadata] || {}
    }
  end

  def sync_webhook_payload(**options)
    {
      action: options[:action] || 'start_sync',
      account_id: options[:account_id],
      options: options[:sync_options] || {}
    }
  end

  # Webhook testing utilities
  def simulate_webhook_request(endpoint, payload, headers = {})
    webhook_headers = api_headers.merge(headers).merge(
      'X-Webhook-Source' => 'iPhone',
      'X-Request-ID' => SecureRandom.uuid
    )

    post endpoint, params: payload.to_json, headers: webhook_headers
  end

  def expect_webhook_success(expected_data = {})
    json = expect_json_response(status: [ 200, 201, 202 ]) # Accept 202 for async
    expect(json).to include(status: 'success')
    expect(json).to include(expected_data) if expected_data.any?
    json
  end

  def expect_webhook_error(error_message = nil)
    json = expect_json_response(status: 400)
    expect(json).to include(status: 'error')
    expect(json[:error]).to match(/#{error_message}/i) if error_message
    json
  end

  # API versioning helpers
  def api_v1_headers(token = nil)
    api_headers(token).merge('Accept' => 'application/vnd.expense-tracker.v1+json')
  end

  def api_v2_headers(token = nil)
    api_headers(token).merge('Accept' => 'application/vnd.expense-tracker.v2+json')
  end

  # Rate limiting test helpers
  def exceed_rate_limit(endpoint, limit = 100)
    (limit + 1).times do |i|
      api_request(:post, endpoint, { test_request: i })
      break if response.status == 429 # Rate limited
    end
  end

  def wait_for_rate_limit_reset(window_duration = 60)
    sleep(window_duration + 1)
  end

  # Batch operation helpers
  def batch_expense_payload(expenses)
    {
      expenses: expenses.map do |expense|
        expense_webhook_payload(
          amount: expense[:amount],
          description: expense[:description],
          currency: expense[:currency] || 'CRC',
          date: expense[:date] || Date.current.to_s
        )
      end
    }
  end

  # Error simulation helpers
  def simulate_server_error
    allow_any_instance_of(Api::WebhooksController).to receive(:create_expense)
      .and_raise(StandardError, "Simulated server error")
  end

  def simulate_database_error
    allow(Expense).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "Simulated DB error")
  end

  def simulate_validation_error(model_class, errors)
    invalid_instance = instance_double(model_class, valid?: false, errors: errors)
    allow(model_class).to receive(:new).and_return(invalid_instance)
  end

  # Security testing helpers
  def inject_malicious_payload(base_payload)
    base_payload.merge(
      malicious_script: '<script>alert("xss")</script>',
      sql_injection: "'; DROP TABLE expenses; --",
      path_traversal: '../../../etc/passwd',
      large_string: 'A' * 10000
    )
  end

  def test_input_sanitization(endpoint, payload)
    malicious_payload = inject_malicious_payload(payload)
    simulate_webhook_request(endpoint, malicious_payload)

    # Should either sanitize or reject malicious input
    expect([ 200, 201, 400, 422 ]).to include(response.status)

    if response.successful?
      # If accepted, ensure data was sanitized
      created_record = Expense.last
      expect(created_record.description).not_to include('<script>')
      expect(created_record.description).not_to include('DROP TABLE')
    end
  end

  # Load testing helpers
  def concurrent_api_requests(endpoint, payload, concurrency: 10, requests_per_thread: 5)
    results = []
    errors = []

    threads = concurrency.times.map do |thread_id|
      Thread.new do
        thread_results = []
        thread_errors = []

        requests_per_thread.times do |request_id|
          begin
            start_time = Time.current
            simulate_webhook_request(endpoint, payload)
            end_time = Time.current

            thread_results << {
              thread_id: thread_id,
              request_id: request_id,
              status: response.status,
              response_time: end_time - start_time,
              success: response.successful?
            }
          rescue StandardError => e
            thread_errors << {
              thread_id: thread_id,
              request_id: request_id,
              error: e.message
            }
          end
        end

        { results: thread_results, errors: thread_errors }
      end
    end

    thread_data = threads.map(&:value)
    results = thread_data.flat_map { |data| data[:results] }
    errors = thread_data.flat_map { |data| data[:errors] }

    {
      results: results,
      errors: errors,
      success_rate: results.count { |r| r[:success] }.to_f / results.length,
      avg_response_time: results.map { |r| r[:response_time] }.sum / results.length,
      error_rate: errors.length.to_f / (concurrency * requests_per_thread)
    }
  end

  # Response validation helpers
  def validate_expense_response(response_data, expected_attributes = {})
    expect(response_data).to include(
      id: be_a(Integer),
      amount: be_a(Numeric),
      description: be_a(String),
      currency: be_a(String),
      date: match(/\d{4}-\d{2}-\d{2}/),
      created_at: be_a(String),
      updated_at: be_a(String)
    )

    expected_attributes.each do |key, value|
      expect(response_data[key]).to eq(value)
    end
  end

  def validate_error_response(response_data, expected_error_fields = [])
    expect(response_data).to include(
      status: 'error',
      error: be_a(String)
    )

    if expected_error_fields.any?
      expect(response_data).to have_key(:errors)
      expected_error_fields.each do |field|
        expect(response_data[:errors]).to have_key(field)
      end
    end
  end
end

# Custom matchers for API testing
RSpec::Matchers.define :have_valid_json_structure do |expected_structure|
  match do |response_body|
    json = JSON.parse(response_body, symbolize_names: true)
    validate_structure(json, expected_structure)
  rescue JSON::ParserError
    false
  end

  failure_message do |response_body|
    "Expected valid JSON with structure #{expected_structure}, but got: #{response_body}"
  end

  private

  def validate_structure(json, structure)
    case structure
    when Hash
      return false unless json.is_a?(Hash)
      structure.all? do |key, expected_type|
        json.key?(key) && validate_structure(json[key], expected_type)
      end
    when Array
      return false unless json.is_a?(Array)
      return true if structure.empty? # Empty array matches any array
      json.all? { |item| validate_structure(item, structure.first) }
    when Class
      json.is_a?(structure)
    else
      json == structure
    end
  end
end

RSpec::Matchers.define :have_api_error do |error_type|
  chain :with_message do |message|
    @expected_message = message
  end

  match do |response|
    json = JSON.parse(response.body, symbolize_names: true) rescue {}

    return false unless json[:status] == 'error'
    return false if error_type && json[:error_type] != error_type
    return false if @expected_message && !json[:error].include?(@expected_message)

    true
  end

  failure_message do |response|
    json = JSON.parse(response.body, symbolize_names: true) rescue {}
    "Expected API error of type '#{error_type}' with message '#{@expected_message}', but got: #{json}"
  end
end

# Include API helpers in request specs
RSpec.configure do |config|
  config.include ApiHelpers, type: :request
  config.include ApiHelpers, type: :api

  # Set up API testing environment
  config.before(:each, type: :request) do
    # Clear any cached tokens
    @valid_api_token = nil
    @expired_api_token = nil
    @json_response = nil
  end
end
