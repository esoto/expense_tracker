# frozen_string_literal: true

# BroadcastRequestValidator provides input validation and sanitization for broadcast requests
# to prevent malicious data injection and ensure system security.
#
# Features:
# - Input sanitization and validation
# - Data size limits to prevent memory exhaustion
# - Channel name validation
# - Rate limiting integration
# - Suspicious activity detection
#
# Usage:
#   validator = BroadcastRequestValidator.new(request_data)
#   if validator.valid?
#     # Safe to proceed with broadcast
#   else
#     # Handle validation errors
#     validator.errors.each { |error| puts error }
#   end
module Services
  class BroadcastRequestValidator
  # Maximum allowed data size (1MB)
  MAX_DATA_SIZE = 1.megabyte

  # Maximum string length for individual fields
  MAX_STRING_LENGTH = 10_000

  # Maximum array size for data arrays
  MAX_ARRAY_SIZE = 1_000

  # Maximum nesting depth for data structures
  MAX_NESTING_DEPTH = 10

  # Allowed channel names (whitelist approach)
  ALLOWED_CHANNELS = %w[
    SyncStatusChannel
    DashboardChannel
    NotificationChannel
  ].freeze

  # Allowed target types (whitelist approach)
  ALLOWED_TARGET_TYPES = %w[
    SyncSession
    User
    EmailAccount
    Expense
  ].freeze

  # Allowed priority levels
  ALLOWED_PRIORITIES = %w[critical high medium low].freeze

  # Suspicious patterns in data
  SUSPICIOUS_PATTERNS = [
    /<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/mi, # Script tags
    /javascript:/i,                                        # JavaScript protocol
    /on\w+\s*=/i,                                         # Event handlers
    /eval\s*\(/i,                                         # eval() calls
    /expression\s*\(/i,                                   # CSS expressions
    /vbscript:/i,                                         # VBScript protocol
    /data:text\/html/i,                                   # Data URLs with HTML
    /<iframe\b/i,                                         # Iframe tags
    /<object\b/i,                                         # Object tags
    /<embed\b/i,                                          # Embed tags
    /\bsql\b.*\b(union|select|insert|delete|update|drop)\b/i # SQL injection
  ].freeze

  attr_reader :errors, :warnings

  def initialize(request_data)
    @request_data = request_data
    @errors = []
    @warnings = []
    @sanitized_data = nil
  end

  # Validate the broadcast request
  # @return [Boolean] True if valid
  def valid?
    @errors.clear
    @warnings.clear

    validate_required_fields
    validate_field_types
    validate_channel_name
    validate_target_type
    validate_priority
    validate_data_structure
    validate_data_size
    check_suspicious_content

    @errors.empty?
  end

  # Get sanitized and validated data
  # @return [Hash] Sanitized data
  def sanitized_data
    return nil unless valid?

    @sanitized_data ||= sanitize_data(@request_data)
  end

  # Get validation summary
  # @return [Hash] Validation summary
  def validation_summary
    {
      valid: @errors.empty?,
      error_count: @errors.size,
      warning_count: @warnings.size,
      errors: @errors,
      warnings: @warnings,
      data_size: calculate_data_size(@request_data),
      max_allowed_size: MAX_DATA_SIZE
    }
  end

  private

  # Validate required fields are present
  def validate_required_fields
    required_fields = %w[channel_name target_type target_id data priority]

    required_fields.each do |field|
      unless @request_data.key?(field)
        @errors << "Missing required field: #{field}"
      end

      if @request_data[field].nil?
        @errors << "Field cannot be nil: #{field}"
      end
    end
  end

  # Validate field data types
  def validate_field_types
    return unless @request_data.is_a?(Hash)

    # Channel name must be string
    if @request_data["channel_name"] && !@request_data["channel_name"].is_a?(String)
      @errors << "channel_name must be a string"
    end

    # Target type must be string
    if @request_data["target_type"] && !@request_data["target_type"].is_a?(String)
      @errors << "target_type must be a string"
    end

    # Target ID must be numeric
    if @request_data["target_id"] && !@request_data["target_id"].is_a?(Numeric)
      @errors << "target_id must be numeric"
    end

    # Priority must be string
    if @request_data["priority"] && !@request_data["priority"].is_a?(String)
      @errors << "priority must be a string"
    end

    # Data must be hash or array
    if @request_data["data"] && !(@request_data["data"].is_a?(Hash) || @request_data["data"].is_a?(Array))
      @errors << "data must be a hash or array"
    end
  end

  # Validate channel name against whitelist
  def validate_channel_name
    channel_name = @request_data["channel_name"]
    return unless channel_name

    unless ALLOWED_CHANNELS.include?(channel_name)
      @errors << "Invalid channel name: #{channel_name}. Allowed: #{ALLOWED_CHANNELS.join(', ')}"
    end

    if channel_name.length > MAX_STRING_LENGTH
      @errors << "Channel name too long: #{channel_name.length} > #{MAX_STRING_LENGTH}"
    end
  end

  # Validate target type against whitelist
  def validate_target_type
    target_type = @request_data["target_type"]
    return unless target_type

    unless ALLOWED_TARGET_TYPES.include?(target_type)
      @errors << "Invalid target type: #{target_type}. Allowed: #{ALLOWED_TARGET_TYPES.join(', ')}"
    end
  end

  # Validate priority level
  def validate_priority
    priority = @request_data["priority"]
    return unless priority

    unless ALLOWED_PRIORITIES.include?(priority)
      @errors << "Invalid priority: #{priority}. Allowed: #{ALLOWED_PRIORITIES.join(', ')}"
    end
  end

  # Validate data structure complexity and size
  def validate_data_structure
    data = @request_data["data"]
    return unless data

    # Check nesting depth
    depth = calculate_nesting_depth(data)
    if depth > MAX_NESTING_DEPTH
      @errors << "Data structure too deep: #{depth} > #{MAX_NESTING_DEPTH}"
    end

    # Check array sizes
    if data.is_a?(Array) && data.size > MAX_ARRAY_SIZE
      @errors << "Array too large: #{data.size} > #{MAX_ARRAY_SIZE}"
    end

    # Recursively check nested structures
    validate_nested_structure(data)
  end

  # Validate overall data size
  def validate_data_size
    size = calculate_data_size(@request_data)

    if size > MAX_DATA_SIZE
      @errors << "Data size too large: #{size} bytes > #{MAX_DATA_SIZE} bytes"
    elsif size > MAX_DATA_SIZE * 0.8
      @warnings << "Data size approaching limit: #{size} bytes (#{((size.to_f / MAX_DATA_SIZE) * 100).round(1)}% of limit)"
    end
  end

  # Check for suspicious content patterns
  def check_suspicious_content
    data_json = @request_data.to_json

    SUSPICIOUS_PATTERNS.each do |pattern|
      if data_json.match?(pattern)
        @errors << "Suspicious content detected matching pattern: #{pattern.inspect}"
      end
    end

    # Check for excessive special characters
    special_char_ratio = data_json.count('<>&"\'(){}[]').to_f / data_json.length
    if special_char_ratio > 0.1
      @warnings << "High ratio of special characters detected: #{(special_char_ratio * 100).round(2)}%"
    end
  end

  # Validate nested data structures
  # @param data [Object] Data to validate
  # @param path [String] Current path for error reporting
  def validate_nested_structure(data, path = "data")
    case data
    when Hash
      if data.size > MAX_ARRAY_SIZE
        @errors << "Hash too large at #{path}: #{data.size} > #{MAX_ARRAY_SIZE}"
      end

      data.each do |key, value|
        if key.is_a?(String) && key.length > MAX_STRING_LENGTH
          @errors << "Hash key too long at #{path}.#{key}: #{key.length} > #{MAX_STRING_LENGTH}"
        end

        validate_nested_structure(value, "#{path}.#{key}")
      end

    when Array
      if data.size > MAX_ARRAY_SIZE
        @errors << "Array too large at #{path}: #{data.size} > #{MAX_ARRAY_SIZE}"
      end

      data.each_with_index do |item, index|
        validate_nested_structure(item, "#{path}[#{index}]")
      end

    when String
      if data.length > MAX_STRING_LENGTH
        @errors << "String too long at #{path}: #{data.length} > #{MAX_STRING_LENGTH}"
      end
    end
  end

  # Calculate nesting depth of data structure
  # @param data [Object] Data to analyze
  # @return [Integer] Nesting depth
  def calculate_nesting_depth(data, current_depth = 0)
    case data
    when Hash
      return current_depth if data.empty?
      data.values.map { |v| calculate_nesting_depth(v, current_depth + 1) }.max
    when Array
      return current_depth if data.empty?
      data.map { |v| calculate_nesting_depth(v, current_depth + 1) }.max
    else
      current_depth
    end
  end

  # Calculate approximate data size in bytes
  # @param data [Object] Data to measure
  # @return [Integer] Size in bytes
  def calculate_data_size(data)
    data.to_json.bytesize
  rescue StandardError
    # Fallback for non-JSON-serializable data
    Marshal.dump(data).bytesize
  rescue StandardError
    # Ultimate fallback
    data.to_s.bytesize
  end

  # Sanitize data by removing/escaping dangerous content
  # @param data [Object] Data to sanitize
  # @return [Object] Sanitized data
  def sanitize_data(data)
    case data
    when Hash
      data.transform_keys { |k| sanitize_string(k.to_s) }
          .transform_values { |v| sanitize_data(v) }
    when Array
      data.map { |item| sanitize_data(item) }
    when String
      sanitize_string(data)
    else
      data
    end
  end

  # Sanitize individual string values
  # @param string [String] String to sanitize
  # @return [String] Sanitized string
  def sanitize_string(string)
    return string unless string.is_a?(String)

    # Remove potentially dangerous HTML/JavaScript
    sanitized = string.gsub(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/mi, "[SCRIPT_REMOVED]")
                         .gsub(/javascript:/i, "javascript_removed:")
                         .gsub(/on\w+\s*=/i, "event_removed=")
                         .gsub(/eval\s*\(/i, "eval_removed(")

    # Truncate if too long
    if sanitized.length > MAX_STRING_LENGTH
      sanitized = sanitized.truncate(MAX_STRING_LENGTH)
      @warnings << "String truncated from #{string.length} to #{MAX_STRING_LENGTH} characters"
    end

    sanitized
  end
  end
end
