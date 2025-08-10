# Rack::Attack configuration for rate limiting and security
# Skip in test environment
if Rails.env.test?
  # Disable Rack::Attack in test environment
  Rack::Attack.enabled = false
else
  class Rack::Attack
  # Configure cache store (uses Rails.cache by default)
  Rack::Attack.cache.store = Rails.cache

  # Rate limit ActionCable connections
  # Allow 10 WebSocket connection attempts per minute per IP
  throttle("cable/connections", limit: 10, period: 1.minute) do |req|
    req.ip if req.path == "/cable"
  end

  # Rate limit subscription attempts
  # Allow 20 subscription attempts per minute per IP
  throttle("cable/subscriptions", limit: 20, period: 1.minute) do |req|
    req.ip if req.path == "/cable" && req.post?
  end

  # General API rate limiting
  # Allow 300 requests per 5 minutes per IP
  throttle("api/ip", limit: 300, period: 5.minutes) do |req|
    req.ip if req.path.start_with?("/api")
  end

  # Sync session creation rate limiting
  # Allow 5 sync sessions per hour per IP
  throttle("sync_sessions/create", limit: 5, period: 1.hour) do |req|
    req.ip if req.path == "/sync_sessions" && req.post?
  end

  # Queue status monitoring rate limiting
  # Allow 60 status checks per minute per IP (every second)
  throttle("queue/status", limit: 60, period: 1.minute) do |req|
    req.ip if req.path == "/api/queue/status" || req.path == "/api/queue/status.json"
  end

  # Queue control operations rate limiting
  # Allow 10 control operations per minute per IP
  throttle("queue/control", limit: 10, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/queue/") && (req.post? || req.put? || req.patch? || req.delete?)
  end

  # Exponential backoff for repeated failed requests
  # Block IP for 10 minutes after 5 failed authentication attempts
  Rack::Attack.blocklist("fail2ban:logins") do |req|
    # This would be implemented with actual authentication logic
    # For now, we'll skip this as we don't have user auth yet
    false
  end

  # Custom response for throttled requests
  Rack::Attack.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    now = match_data[:epoch_time]

    headers = {
      "Content-Type" => "application/json",
      "X-RateLimit-Limit" => match_data[:limit].to_s,
      "X-RateLimit-Remaining" => "0",
      "X-RateLimit-Reset" => (now + (match_data[:period] - now % match_data[:period])).to_s
    }

    message = {
      error: "Too many requests",
      message: "You have exceeded the rate limit. Please try again later.",
      retry_after: headers["X-RateLimit-Reset"]
    }

    [ 429, headers, [ message.to_json ] ]
  end
  end

  # Enable Rack::Attack middleware
  Rails.application.config.middleware.use Rack::Attack
end
