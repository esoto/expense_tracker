# frozen_string_literal: true

# Rate limiting and security configuration using Rack::Attack
# Protects against brute force attacks, DoS, and other abusive behavior

# Skip all rate limiting in test environment
return if Rails.env.test?

class Rack::Attack
  # Store configuration in Redis if available, otherwise use in-memory cache
  if ENV["REDIS_URL"].present?
    Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(url: ENV["REDIS_URL"])
  else
    # Use Rails cache for development/testing
    Rack::Attack.cache.store = Rails.cache
  end

  # === Allow Lists ===
  # Always allow requests from localhost in development
  Rack::Attack.safelist("allow-localhost") do |req|
    req.ip == "127.0.0.1" || req.ip == "::1"
  end if Rails.env.development?

  # Allow specific IPs (e.g., monitoring services)
  Rack::Attack.safelist("allow-monitoring") do |req|
    ENV["ALLOWED_IPS"]&.split(",")&.include?(req.ip)
  end

  # === Block Lists ===
  # Block suspicious requests
  Rack::Attack.blocklist("block-bad-agents") do |req|
    # Block requests with suspicious user agents
    bad_agents = [
      /bot/i,
      /crawler/i,
      /spider/i,
      /scraper/i,
      /curl/i,
      /wget/i,
      /python/i,
      /nikto/i,
      /sqlmap/i,
      /nmap/i
    ]

    # Allow legitimate bots
    good_bots = [
      /googlebot/i,
      /bingbot/i,
      /slackbot/i,
      /twitterbot/i,
      /facebookexternalhit/i
    ]

    user_agent = req.user_agent.to_s
    bad_agents.any? { |pattern| user_agent.match?(pattern) } &&
      good_bots.none? { |pattern| user_agent.match?(pattern) }
  end

  # Block requests to sensitive files
  Rack::Attack.blocklist("block-sensitive-files") do |req|
    sensitive_paths = [
      /\.env/,
      /\.git/,
      /\.svn/,
      /wp-admin/,
      /wp-login/,
      /phpmyadmin/,
      /\.sql/,
      /\.bak/,
      /\.backup/,
      /\.config/,
      /\.yml$/,
      /\.yaml$/
    ]

    sensitive_paths.any? { |pattern| req.path.match?(pattern) }
  end

  # === Throttles ===

  # Throttle all requests by IP (general rate limiting)
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?("/assets", "/packs")
  end

  # Throttle login attempts by IP
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    if req.path == "/admin/login" && req.post?
      req.ip
    end
  end

  # Throttle login attempts by email (prevent account takeover)
  throttle("logins/email", limit: 5, period: 20.seconds) do |req|
    if req.path == "/admin/login" && req.post?
      # Normalize email to prevent bypass
      req.params["email"].to_s.downcase.strip.presence
    end
  end

  # Throttle password reset requests
  throttle("password-reset/ip", limit: 3, period: 15.minutes) do |req|
    if req.path == "/admin/password/reset" && req.post?
      req.ip
    end
  end

  # Throttle API endpoints more strictly
  throttle("api/ip", limit: 100, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api")
  end

  # Throttle pattern testing (resource intensive)
  throttle("patterns/test/ip", limit: 30, period: 1.minute) do |req|
    if req.path.match?(%r{/admin/patterns/.*/test}) && req.post?
      req.ip
    end
  end

  # Throttle pattern imports (file upload)
  throttle("patterns/import/ip", limit: 5, period: 1.hour) do |req|
    if req.path == "/admin/patterns/import" && req.post?
      req.ip
    end
  end

  # Throttle CSV exports
  throttle("exports/ip", limit: 10, period: 1.hour) do |req|
    if req.path.match?(/\.csv$/) || req.path.match?(/\/export/)
      req.ip
    end
  end

  # Throttle statistics endpoints (expensive queries)
  throttle("statistics/ip", limit: 20, period: 5.minutes) do |req|
    if req.path.match?(%r{/admin/patterns/(statistics|performance)})
      req.ip
    end
  end

  # === Track suspicious activity ===

  # Track 404s to identify scanners
  # Note: This is disabled as status is not available during request processing
  # track("req/404s") do |req|
  #   req.ip if req.status == 404
  # end

  # Block IPs with too many 404s (likely scanners)
  # Note: This is disabled as status is not available during request processing
  # blocklist("fail2ban/404s") do |req|
  #   Rack::Attack::Fail2Ban.filter("req/404s:#{req.ip}", maxretry: 20, findtime: 1.minute, bantime: 1.hour) do
  #     req.status == 404
  #   end
  # end

  # Track failed login attempts
  track("login/failures") do |req|
    if req.path == "/admin/login" && req.post? && req.env["rack.attack.matched"] == "login-failed"
      req.ip
    end
  end

  # === Custom Throttle Response ===

  # Customize throttled response
  self.throttled_responder = lambda do |env|
    # Handle both Hash and Request objects
    request_env = env.is_a?(Hash) ? env : env.env
    throttle_data = request_env["rack.attack.throttle_data"]
    match_type = request_env["rack.attack.matched"]

    # Calculate retry-after in seconds
    now = throttle_data[:epoch_time] || Time.now.to_i
    retry_after = throttle_data[:period] ? throttle_data[:period] - (now % throttle_data[:period]) : 60

    # Log the throttle event
    Rails.logger.warn(
      "Rate limit exceeded: #{match_type} for IP #{request_env['HTTP_X_FORWARDED_FOR'] || request_env['REMOTE_ADDR']}"
    )

    # Return appropriate response based on request type
    if request_env["HTTP_ACCEPT"]&.include?("application/json")
      [
        429,
        {
          "Content-Type" => "application/json",
          "Retry-After" => retry_after.to_s,
          "X-RateLimit-Limit" => throttle_data[:limit].to_s,
          "X-RateLimit-Remaining" => "0",
          "X-RateLimit-Reset" => (now + retry_after).to_s
        },
        [
          {
            error: "Too Many Requests",
            message: "Rate limit exceeded. Please try again in #{retry_after} seconds.",
            retry_after: retry_after
          }.to_json
        ]
      ]
    else
      [
        429,
        {
          "Content-Type" => "text/html",
          "Retry-After" => retry_after.to_s
        },
        [
          <<~HTML
            <!DOCTYPE html>
            <html>
            <head>
              <title>Rate Limited</title>
              <style>
                body {
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                  background: #f8fafc;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  height: 100vh;
                  margin: 0;
                }
                .container {
                  text-align: center;
                  padding: 2rem;
                  background: white;
                  border-radius: 8px;
                  box-shadow: 0 1px 3px rgba(0,0,0,0.1);
                  max-width: 400px;
                }
                h1 { color: #ef4444; margin-bottom: 1rem; }
                p { color: #64748b; line-height: 1.5; }
                .retry {#{' '}
                  margin-top: 1rem;
                  padding: 0.5rem 1rem;
                  background: #f1f5f9;
                  border-radius: 4px;
                  color: #475569;
                  font-weight: 500;
                }
              </style>
            </head>
            <body>
              <div class="container">
                <h1>Too Many Requests</h1>
                <p>You've made too many requests in a short period. This limit helps us maintain service quality for all users.</p>
                <div class="retry">Please try again in #{retry_after} seconds</div>
              </div>
            </body>
            </html>
          HTML
        ]
      ]
    end
  end

  # === Blocked Response ===

  self.blocklisted_responder = lambda do |env|
    Rails.logger.error(
      "Blocked request from IP #{env['HTTP_X_FORWARDED_FOR'] || env['REMOTE_ADDR']}: #{env['PATH_INFO']}"
    )

    [
      403,
      { "Content-Type" => "text/plain" },
      [ "Forbidden - Your request has been blocked for security reasons." ]
    ]
  end
end

# Enable Rack::Attack in production and staging
if Rails.env.production? || Rails.env.staging?
  Rails.application.config.middleware.use Rack::Attack

  # Log attacks
  ActiveSupport::Notifications.subscribe("rack.attack") do |name, start, finish, request_id, payload|
    req = payload[:request]
    Rails.logger.info "[Rack::Attack] #{req.env['rack.attack.match_type']} #{req.ip} #{req.request_method} #{req.fullpath}"
  end
end
