# frozen_string_literal: true

# BroadcastRateLimiter provides rate limiting for broadcast requests to prevent
# system abuse and DoS attacks. Uses Redis for distributed rate limiting.
#
# Features:
# - Token bucket algorithm for smooth rate limiting
# - Multiple rate limit tiers (per-user, per-IP, global)
# - Burst capacity handling
# - Whitelist/blacklist support
# - Automatic IP blocking for abuse
# - Priority-based rate limiting
#
# Usage:
#   limiter = BroadcastRateLimiter.new(identifier: user_id, request_ip: '1.2.3.4')
#   if limiter.allowed?(priority: :high)
#     # Proceed with broadcast
#     limiter.consume!
#   else
#     # Rate limit exceeded
#     retry_after = limiter.retry_after
#   end
module Services
  class BroadcastRateLimiter
  # Rate limit configurations by priority
  RATE_LIMITS = {
    critical: { requests: 100, window: 1.minute, burst: 20 },
    high: { requests: 50, window: 1.minute, burst: 10 },
    medium: { requests: 30, window: 1.minute, burst: 5 },
    low: { requests: 10, window: 1.minute, burst: 2 }
  }.freeze

  # Global rate limits (across all users)
  GLOBAL_LIMITS = {
    requests: 1000,
    window: 1.minute,
    burst: 100
  }.freeze

  # IP-based rate limits
  IP_LIMITS = {
    requests: 100,
    window: 1.minute,
    burst: 20
  }.freeze

  # Abuse detection thresholds
  ABUSE_THRESHOLDS = {
    requests_per_minute: 200,
    requests_per_hour: 5000,
    block_duration: 1.hour,
    warning_threshold: 150
  }.freeze

  # Redis key prefixes
  KEY_PREFIXES = {
    user_rate: "rate_limit:user",
    ip_rate: "rate_limit:ip",
    global_rate: "rate_limit:global",
    blocked_ip: "rate_limit:blocked",
    abuse_counter: "rate_limit:abuse",
    whitelist: "rate_limit:whitelist"
  }.freeze

  attr_reader :identifier, :request_ip, :errors

  # Initialize rate limiter
  # @param identifier [String] User/entity identifier
  # @param request_ip [String] Request IP address
  # @param redis [Redis] Redis connection (optional)
  def initialize(identifier:, request_ip: nil, redis: nil)
    @identifier = identifier.to_s
    @request_ip = request_ip
    @redis = redis || default_redis
    @errors = []
  end

  # Check if request is allowed
  # @param priority [Symbol] Request priority
  # @return [Boolean] True if allowed
  def allowed?(priority: :medium)
    @errors.clear

    # Check if IP is blocked
    return false if ip_blocked?

    # Check if identifier is whitelisted (always allow)
    return true if whitelisted?

    # Check global rate limits
    return false unless check_global_limit

    # Check IP-based limits
    return false unless check_ip_limit if @request_ip

    # Check user-specific limits based on priority
    check_user_limit(priority)
  end

  # Consume rate limit tokens (call after allowed? returns true)
  # @param priority [Symbol] Request priority
  # @return [Boolean] True if consumed successfully
  def consume!(priority: :medium)
    return false unless allowed?(priority: priority)

    current_time = Time.current.to_i

    # Consume from all applicable buckets
    consume_global_token(current_time)
    consume_ip_token(current_time) if @request_ip
    consume_user_token(priority, current_time)

    # Update abuse tracking
    update_abuse_counters

    true
  end

  # Get time until next request is allowed
  # @param priority [Symbol] Request priority
  # @return [Integer] Seconds until retry
  def retry_after(priority: :medium)
    limits = RATE_LIMITS[priority]
    user_key = "#{KEY_PREFIXES[:user_rate]}:#{@identifier}:#{priority}"

    bucket_data = get_token_bucket(user_key, limits)
    return 0 if bucket_data[:tokens] > 0

    # Calculate time for one token to be added
    refill_rate = limits[:requests].to_f / limits[:window]
    (1.0 / refill_rate).ceil
  end

  # Get current rate limit status
  # @return [Hash] Status information
  def status
    {
      identifier: @identifier,
      request_ip: @request_ip,
      ip_blocked: ip_blocked?,
      whitelisted: whitelisted?,
      global_remaining: global_remaining,
      ip_remaining: ip_remaining,
      user_remaining: user_remaining_by_priority,
      abuse_score: abuse_score,
      blocked_until: blocked_until
    }
  end

  # Block IP address for abuse
  # @param duration [Integer] Block duration in seconds
  # @param reason [String] Reason for blocking
  def block_ip!(duration: ABUSE_THRESHOLDS[:block_duration], reason: "Rate limit abuse")
    return unless @request_ip

    block_key = "#{KEY_PREFIXES[:blocked_ip]}:#{@request_ip}"
    block_data = {
      blocked_at: Time.current.to_i,
      expires_at: Time.current.to_i + duration,
      reason: reason,
      identifier: @identifier
    }

    @redis.setex(block_key, duration, block_data.to_json)

    Rails.logger.warn "[RATE_LIMITER] Blocked IP #{@request_ip} for #{duration}s: #{reason}"
  end

  # Add identifier to whitelist
  # @param duration [Integer] Whitelist duration in seconds (nil for permanent)
  def whitelist!(duration: nil)
    whitelist_key = "#{KEY_PREFIXES[:whitelist]}:#{@identifier}"

    if duration
      @redis.setex(whitelist_key, duration, Time.current.to_i)
    else
      @redis.set(whitelist_key, Time.current.to_i)
    end

    Rails.logger.info "[RATE_LIMITER] Whitelisted #{@identifier} for #{duration || 'unlimited'} seconds"
  end

  # Remove identifier from whitelist
  def remove_from_whitelist!
    whitelist_key = "#{KEY_PREFIXES[:whitelist]}:#{@identifier}"
    @redis.del(whitelist_key)

    Rails.logger.info "[RATE_LIMITER] Removed #{@identifier} from whitelist"
  end

  # Get rate limiting statistics
  # @return [Hash] Statistics
  def self.stats
    redis = new(identifier: "stats").send(:default_redis)

    {
      total_blocked_ips: redis.keys("#{KEY_PREFIXES[:blocked_ip]}:*").size,
      total_whitelisted: redis.keys("#{KEY_PREFIXES[:whitelist]}:*").size,
      active_rate_limits: redis.keys("#{KEY_PREFIXES[:user_rate]}:*").size,
      global_usage: global_bucket_usage(redis)
    }
  end

  private

  # Get default Redis connection
  # @return [Redis] Redis connection
  def default_redis
    Redis.new(
      url: ENV.fetch("REDIS_URL", "redis://localhost:6379/2"),
      timeout: 1.0
    )
  end

  # Check if IP is currently blocked
  # @return [Boolean] True if blocked
  def ip_blocked?
    return false unless @request_ip

    block_key = "#{KEY_PREFIXES[:blocked_ip]}:#{@request_ip}"
    blocked_data = @redis.get(block_key)

    if blocked_data
      data = JSON.parse(blocked_data)
      if Time.current.to_i < data["expires_at"]
        @errors << "IP blocked until #{Time.at(data['expires_at']).iso8601}: #{data['reason']}"
        return true
      else
        # Clean up expired block
        @redis.del(block_key)
      end
    end

    false
  rescue JSON::ParserError
    # Invalid block data, remove it
    @redis.del(block_key)
    false
  end

  # Check if identifier is whitelisted
  # @return [Boolean] True if whitelisted
  def whitelisted?
    whitelist_key = "#{KEY_PREFIXES[:whitelist]}:#{@identifier}"
    @redis.exists?(whitelist_key) == 1
  end

  # Check global rate limits
  # @return [Boolean] True if within limits
  def check_global_limit
    global_key = KEY_PREFIXES[:global_rate]
    bucket = get_token_bucket(global_key, GLOBAL_LIMITS)

    if bucket[:tokens] <= 0
      @errors << "Global rate limit exceeded. Try again in #{bucket[:retry_after]} seconds"
      return false
    end

    true
  end

  # Check IP-based rate limits
  # @return [Boolean] True if within limits
  def check_ip_limit
    ip_key = "#{KEY_PREFIXES[:ip_rate]}:#{@request_ip}"
    bucket = get_token_bucket(ip_key, IP_LIMITS)

    if bucket[:tokens] <= 0
      @errors << "IP rate limit exceeded. Try again in #{bucket[:retry_after]} seconds"
      return false
    end

    true
  end

  # Check user-specific rate limits
  # @param priority [Symbol] Request priority
  # @return [Boolean] True if within limits
  def check_user_limit(priority)
    limits = RATE_LIMITS[priority]
    user_key = "#{KEY_PREFIXES[:user_rate]}:#{@identifier}:#{priority}"
    bucket = get_token_bucket(user_key, limits)

    if bucket[:tokens] <= 0
      @errors << "User rate limit exceeded for #{priority} priority. Try again in #{bucket[:retry_after]} seconds"
      return false
    end

    true
  end

  # Get or create token bucket state
  # @param key [String] Redis key
  # @param limits [Hash] Rate limit configuration
  # @return [Hash] Bucket state
  def get_token_bucket(key, limits)
    current_time = Time.current.to_i
    bucket_data = @redis.get(key)

    if bucket_data
      data = JSON.parse(bucket_data)
      tokens = data["tokens"].to_f
      last_refill = data["last_refill"].to_i
    else
      tokens = limits[:requests].to_f
      last_refill = current_time
    end

    # Calculate token refill
    time_passed = current_time - last_refill
    if time_passed > 0
      refill_rate = limits[:requests].to_f / limits[:window]
      tokens_to_add = time_passed * refill_rate
      tokens = [ tokens + tokens_to_add, limits[:requests] + limits[:burst] ].min
    end

    # Calculate retry_after if no tokens available
    retry_after = 0
    if tokens <= 0
      refill_rate = limits[:requests].to_f / limits[:window]
      retry_after = (1.0 / refill_rate).ceil
    end

    {
      tokens: tokens,
      last_refill: current_time,
      retry_after: retry_after
    }
  end

  # Consume token from global bucket
  # @param current_time [Integer] Current timestamp
  def consume_global_token(current_time)
    consume_token(KEY_PREFIXES[:global_rate], GLOBAL_LIMITS, current_time)
  end

  # Consume token from IP bucket
  # @param current_time [Integer] Current timestamp
  def consume_ip_token(current_time)
    return unless @request_ip

    ip_key = "#{KEY_PREFIXES[:ip_rate]}:#{@request_ip}"
    consume_token(ip_key, IP_LIMITS, current_time)
  end

  # Consume token from user bucket
  # @param priority [Symbol] Request priority
  # @param current_time [Integer] Current timestamp
  def consume_user_token(priority, current_time)
    limits = RATE_LIMITS[priority]
    user_key = "#{KEY_PREFIXES[:user_rate]}:#{@identifier}:#{priority}"
    consume_token(user_key, limits, current_time)
  end

  # Consume one token from bucket
  # @param key [String] Redis key
  # @param limits [Hash] Rate limit configuration
  # @param current_time [Integer] Current timestamp
  def consume_token(key, limits, current_time)
    bucket = get_token_bucket(key, limits)
    bucket[:tokens] -= 1

    new_data = {
      tokens: bucket[:tokens],
      last_refill: current_time
    }

    @redis.setex(key, limits[:window] * 2, new_data.to_json)
  end

  # Update abuse tracking counters
  def update_abuse_counters
    return unless @request_ip

    current_time = Time.current

    # Per-minute counter
    minute_key = "#{KEY_PREFIXES[:abuse_counter]}:#{@request_ip}:#{current_time.strftime('%Y%m%d%H%M')}"
    minute_count = @redis.incr(minute_key)
    @redis.expire(minute_key, 120) # Keep for 2 minutes

    # Per-hour counter
    hour_key = "#{KEY_PREFIXES[:abuse_counter]}:#{@request_ip}:#{current_time.strftime('%Y%m%d%H')}"
    hour_count = @redis.incr(hour_key)
    @redis.expire(hour_key, 7200) # Keep for 2 hours

    # Check abuse thresholds
    if minute_count >= ABUSE_THRESHOLDS[:requests_per_minute]
      block_ip!(reason: "Exceeded #{ABUSE_THRESHOLDS[:requests_per_minute]} requests per minute")
    elsif hour_count >= ABUSE_THRESHOLDS[:requests_per_hour]
      block_ip!(reason: "Exceeded #{ABUSE_THRESHOLDS[:requests_per_hour]} requests per hour")
    elsif minute_count >= ABUSE_THRESHOLDS[:warning_threshold]
      Rails.logger.warn "[RATE_LIMITER] High request rate from IP #{@request_ip}: #{minute_count} requests/minute"
    end
  end

  # Get remaining global requests
  # @return [Integer] Remaining requests
  def global_remaining
    bucket = get_token_bucket(KEY_PREFIXES[:global_rate], GLOBAL_LIMITS)
    bucket[:tokens].floor
  end

  # Get remaining IP requests
  # @return [Integer] Remaining requests
  def ip_remaining
    return nil unless @request_ip

    ip_key = "#{KEY_PREFIXES[:ip_rate]}:#{@request_ip}"
    bucket = get_token_bucket(ip_key, IP_LIMITS)
    bucket[:tokens].floor
  end

  # Get remaining user requests by priority
  # @return [Hash] Remaining requests by priority
  def user_remaining_by_priority
    RATE_LIMITS.keys.map do |priority|
      user_key = "#{KEY_PREFIXES[:user_rate]}:#{@identifier}:#{priority}"
      bucket = get_token_bucket(user_key, RATE_LIMITS[priority])
      [ priority, bucket[:tokens].floor ]
    end.to_h
  end

  # Get abuse score for IP
  # @return [Integer] Abuse score
  def abuse_score
    return 0 unless @request_ip

    current_time = Time.current
    minute_key = "#{KEY_PREFIXES[:abuse_counter]}:#{@request_ip}:#{current_time.strftime('%Y%m%d%H%M')}"
    hour_key = "#{KEY_PREFIXES[:abuse_counter]}:#{@request_ip}:#{current_time.strftime('%Y%m%d%H')}"

    minute_count = (@redis.get(minute_key) || 0).to_i
    hour_count = (@redis.get(hour_key) || 0).to_i

    (minute_count * 10) + hour_count
  end

  # Get blocked until timestamp
  # @return [Time, nil] Blocked until time
  def blocked_until
    return nil unless @request_ip

    block_key = "#{KEY_PREFIXES[:blocked_ip]}:#{@request_ip}"
    blocked_data = @redis.get(block_key)

    return nil unless blocked_data

    data = JSON.parse(blocked_data)
    Time.at(data["expires_at"])
  rescue JSON::ParserError
    nil
  end

  # Get global bucket usage statistics
  # @param redis [Redis] Redis connection
  # @return [Hash] Usage stats
  def self.global_bucket_usage(redis)
    bucket_data = redis.get(KEY_PREFIXES[:global_rate])
    return { tokens: GLOBAL_LIMITS[:requests], usage_percent: 0 } unless bucket_data

    data = JSON.parse(bucket_data)
    tokens = data["tokens"].to_f
    max_tokens = GLOBAL_LIMITS[:requests] + GLOBAL_LIMITS[:burst]
    usage_percent = ((max_tokens - tokens) / max_tokens * 100).round(2)

    { tokens: tokens.floor, usage_percent: usage_percent }
  rescue JSON::ParserError
    { tokens: GLOBAL_LIMITS[:requests], usage_percent: 0 }
  end
  end
end
