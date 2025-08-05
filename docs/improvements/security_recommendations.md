# Security Recommendations - Expense Tracker

## Overall Security Assessment: A- (Excellent)

### Security Audit Results
- **Brakeman Scan**: 0 vulnerabilities ✅
- **Parameter Filtering**: Comprehensive ✅
- **Encryption**: Rails 8 built-in encryption ✅
- **API Authentication**: State-of-the-art dual-layer security ✅

## High Priority Security Tasks

### 1. Add Password Validation to EmailAccount

**File**: `app/models/email_account.rb`

**Add validation**:
```ruby
# Add after line 14
validates :encrypted_password, presence: true
validate :password_strength, if: :encrypted_password_changed?

private

def password_strength
  return unless encrypted_password.present?
  
  # Implement password strength requirements
  if encrypted_password.length < 8
    errors.add(:encrypted_password, "must be at least 8 characters long")
  end
  
  # Add more password strength validations as needed
  unless encrypted_password.match?(/[A-Z]/) && encrypted_password.match?(/[a-z]/) && encrypted_password.match?(/[0-9]/)
    errors.add(:encrypted_password, "must contain uppercase, lowercase, and numbers")
  end
end
```

### 2. Implement API Rate Limiting

**File**: `app/controllers/api/webhooks_controller.rb`

**Option A - Using rack-attack gem**:

1. Add to Gemfile:
```ruby
gem 'rack-attack'
```

2. Create `config/initializers/rack_attack.rb`:
```ruby
class Rack::Attack
  # Throttle API requests by IP
  throttle('api/ip', limit: 60, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/api')
  end

  # Throttle API requests by token
  throttle('api/token', limit: 300, period: 5.minutes) do |req|
    if req.path.start_with?('/api') && req.env['HTTP_AUTHORIZATION']
      req.env['HTTP_AUTHORIZATION'].gsub('Bearer ', '')
    end
  end

  # Block suspicious requests
  blocklist('block suspicious requests') do |req|
    # Block requests with SQL keywords in parameters
    Rack::Attack::Fail2Ban.filter("pentesters-#{req.ip}", maxretry: 3, findtime: 10.minutes, bantime: 1.hour) do
      req.path.include?("'") || req.path.include?("SELECT") || req.path.include?("UNION")
    end
  end
end

# Custom response for rate limited requests
Rack::Attack.throttled_responder = lambda do |request|
  now = Time.now.to_i
  match_data = request.env['rack.attack.match_data']
  
  headers = {
    'Content-Type' => 'application/json',
    'X-RateLimit-Limit' => match_data[:limit].to_s,
    'X-RateLimit-Remaining' => '0',
    'X-RateLimit-Reset' => (now + (match_data[:period] - now % match_data[:period])).to_s
  }
  
  [429, headers, [{error: "Too Many Requests"}.to_json]]
end
```

**Option B - Simple controller-based rate limiting**:

```ruby
class Api::WebhooksController < ApplicationController
  before_action :check_rate_limit

  private

  def check_rate_limit
    cache_key = "api_rate_limit:#{request.ip}:#{Time.current.to_i / 60}"
    request_count = Rails.cache.increment(cache_key, 1, expires_in: 1.minute)
    
    if request_count > 60
      render json: { error: "Rate limit exceeded" }, status: :too_many_requests
    end
  end
end
```

### 3. Add Settings Schema Validation

**File**: `app/models/email_account.rb`

**Add validation method**:
```ruby
validate :validate_settings_schema

private

def validate_settings_schema
  return unless encrypted_settings.present?
  
  begin
    parsed = JSON.parse(encrypted_settings)
    
    # Validate structure
    if parsed.is_a?(Hash)
      # Validate IMAP settings if present
      if parsed["imap"].present?
        validate_imap_settings(parsed["imap"])
      end
    else
      errors.add(:encrypted_settings, "must be a valid JSON object")
    end
  rescue JSON::ParserError
    errors.add(:encrypted_settings, "must be valid JSON")
  end
end

def validate_imap_settings(imap_settings)
  allowed_keys = %w[server port ssl_options auth_method]
  
  imap_settings.each_key do |key|
    unless allowed_keys.include?(key)
      errors.add(:encrypted_settings, "contains invalid IMAP setting: #{key}")
    end
  end
  
  # Validate port if present
  if imap_settings["port"].present?
    port = imap_settings["port"].to_i
    unless (1..65535).include?(port)
      errors.add(:encrypted_settings, "IMAP port must be between 1 and 65535")
    end
  end
end
```

## Medium Priority Security Tasks

### 1. Enhanced Time Parsing Validation

**File**: `app/controllers/api/webhooks_controller.rb`

**Update method**:
```ruby
def parse_since_parameter
  return 1.week.ago unless params[:since].present?
  
  # Sanitize input
  since_param = params[:since].to_s.strip
  
  # Predefined safe values
  case since_param
  when "today"
    Date.current.beginning_of_day
  when "yesterday"
    1.day.ago.beginning_of_day
  when "week"
    1.week.ago
  when "month"
    1.month.ago
  when /\A\d{1,3}\z/  # Only allow 1-3 digit numbers
    hours = [since_param.to_i, 168].min  # Cap at 1 week
    hours.hours.ago
  else
    # Strict date parsing with validation
    begin
      parsed_time = Time.zone.parse(since_param)
      
      # Validate reasonable time range (not future, not too far past)
      if parsed_time > Time.current
        1.week.ago  # Default for future dates
      elsif parsed_time < 1.year.ago
        1.month.ago  # Cap at 1 month for very old dates
      else
        parsed_time
      end
    rescue ArgumentError, TypeError
      # Default fallback for invalid input
      1.week.ago
    end
  end
end
```

### 2. Add Request Size Limits

**File**: `config/application.rb`

```ruby
class Application < Rails::Application
  # Limit request body size to prevent DoS
  config.middleware.use Rack::Protection::MaximumRequestSize, max_request_size: 1.megabyte
end
```

### 3. API Request Logging for Audit

**File**: `app/controllers/api/webhooks_controller.rb`

```ruby
class Api::WebhooksController < ApplicationController
  after_action :log_api_request

  private

  def log_api_request
    # Log API requests for security audit
    Rails.logger.info({
      event: "api_request",
      path: request.path,
      method: request.method,
      ip: request.remote_ip,
      user_agent: request.user_agent,
      api_token_id: @api_token&.id,
      response_status: response.status,
      duration: (Time.current - @request_start_time).round(3)
    }.to_json)
  end

  def authenticate_api_token!
    @request_start_time = Time.current
    # existing authentication logic...
  end
end
```

## Low Priority Security Tasks

### 1. Add Constant-Time Comparison (Defense in Depth)

**File**: `app/models/api_token.rb`

```ruby
# Although we use hash lookup now, add this for any future string comparisons
require 'openssl'

def self.secure_compare(a, b)
  return false unless a.bytesize == b.bytesize
  
  # Use OpenSSL's constant-time comparison
  OpenSSL.fixed_length_secure_compare(a, b)
end
```

### 2. API Versioning

**File**: `config/routes.rb`

```ruby
namespace :api do
  namespace :v1 do
    resources :webhooks, only: [] do
      collection do
        post :process_emails
        post :add_expense
        get :recent_expenses
        get :expense_summary
      end
    end
  end
  
  # Redirect unversioned routes to v1 (backwards compatibility)
  resources :webhooks, only: [] do
    collection do
      post :process_emails, to: redirect('/api/v1/webhooks/process_emails')
      post :add_expense, to: redirect('/api/v1/webhooks/add_expense')
      get :recent_expenses, to: redirect('/api/v1/webhooks/recent_expenses')
      get :expense_summary, to: redirect('/api/v1/webhooks/expense_summary')
    end
  end
end
```

## Security Monitoring

### Add Security Headers

**File**: `app/controllers/application_controller.rb`

```ruby
class ApplicationController < ActionController::Base
  after_action :set_security_headers

  private

  def set_security_headers
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    
    # Content Security Policy
    response.headers['Content-Security-Policy'] = [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline'",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: https:",
      "font-src 'self'",
      "connect-src 'self'",
      "frame-ancestors 'none'"
    ].join('; ')
  end
end
```

## Testing Security Improvements

```bash
# Run Brakeman after changes
bundle exec brakeman

# Test rate limiting
for i in {1..70}; do
  curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:3000/api/webhooks/recent_expenses
done

# Check security headers
curl -I http://localhost:3000

# Test password validation
rails console
> ea = EmailAccount.new(email: "test@example.com", provider: "gmail", bank_name: "BAC")
> ea.encrypted_password = "weak"
> ea.valid? # Should return false with password errors
```