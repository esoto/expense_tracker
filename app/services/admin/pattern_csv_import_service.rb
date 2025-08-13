# frozen_string_literal: true

require "csv"

module Admin
  # Service for securely importing patterns from CSV files
  class PatternCsvImportService
    include ActiveModel::Model

    # Constants
    MAX_FILE_SIZE = 10.megabytes
    ALLOWED_MIME_TYPES = %w[text/csv application/csv text/plain].freeze
    MAX_ROWS = 10_000
    REQUIRED_HEADERS = %w[pattern_type pattern_value category_id].freeze
    VALID_PATTERN_TYPES = %w[exact_match contains regex merchant_name amount_range].freeze

    attr_accessor :file, :admin_user
    attr_reader :imported_count, :errors, :warnings

    validates :file, presence: true
    validates :admin_user, presence: true

    def initialize(file:, admin_user:)
      @file = file
      @admin_user = admin_user
      @imported_count = 0
      @errors = []
      @warnings = []
    end

    def import
      return false unless valid?

      validate_file!
      process_csv

      @errors.empty?
    rescue StandardError => e
      Rails.logger.error "CSV Import Error: #{e.message}"
      @errors << "Import failed: #{e.message}"
      false
    end

    private

    def validate_file!
      validate_file_presence
      validate_file_size
      validate_file_type
      validate_csv_structure
    end

    def validate_file_presence
      raise ArgumentError, "No file provided" unless @file.present?
    end

    def validate_file_size
      if @file.size > MAX_FILE_SIZE
        raise ArgumentError, "File too large. Maximum size is #{MAX_FILE_SIZE / 1.megabyte}MB"
      end
    end

    def validate_file_type
      mime_type = Marcel::MimeType.for(@file)

      unless ALLOWED_MIME_TYPES.include?(mime_type)
        raise ArgumentError, "Invalid file type. Please upload a CSV file"
      end

      # Additional validation: check file extension
      unless @file.original_filename.downcase.end_with?(".csv")
        raise ArgumentError, "File must have .csv extension"
      end
    end

    def validate_csv_structure
      # Read first line to validate headers
      first_line = File.open(@file.path, "r:UTF-8", &:readline)
      headers = CSV.parse_line(first_line)&.map(&:downcase)&.map(&:strip)

      missing_headers = REQUIRED_HEADERS - (headers || [])
      if missing_headers.any?
        raise ArgumentError, "Missing required columns: #{missing_headers.join(', ')}"
      end
    rescue CSV::MalformedCSVError => e
      raise ArgumentError, "Invalid CSV format: #{e.message}"
    end

    def process_csv
      ActiveRecord::Base.transaction do
        row_count = 0

        CSV.foreach(@file.path, headers: true, header_converters: :downcase) do |row|
          row_count += 1

          if row_count > MAX_ROWS
            @warnings << "Import limited to #{MAX_ROWS} rows. Remaining rows were skipped."
            break
          end

          process_row(row, row_count)
        end
      end
    rescue CSV::MalformedCSVError => e
      raise ArgumentError, "CSV parsing error: #{e.message}"
    end

    def process_row(row, row_number)
      # Sanitize and validate inputs
      pattern_type = sanitize_string(row["pattern_type"])
      pattern_value = sanitize_pattern_value(row["pattern_value"], pattern_type)
      category_id = sanitize_integer(row["category_id"])
      confidence_weight = sanitize_float(row["confidence_weight"]) || 1.0
      active = sanitize_boolean(row["active"])

      # Validate pattern type
      unless VALID_PATTERN_TYPES.include?(pattern_type)
        @errors << "Row #{row_number}: Invalid pattern type '#{pattern_type}'"
        return
      end

      # Validate regex patterns for ReDoS attacks
      if pattern_type == "regex"
        validate_regex_safety(pattern_value, row_number)
        return if @errors.any? { |e| e.include?("Row #{row_number}") }
      end

      # Validate category exists
      unless Category.exists?(category_id)
        @errors << "Row #{row_number}: Category ID #{category_id} does not exist"
        return
      end

      # Create pattern with audit trail
      pattern = CategorizationPattern.new(
        pattern_type: pattern_type,
        pattern_value: pattern_value,
        category_id: category_id,
        confidence_weight: confidence_weight,
        active: active,
        user_created: true,
        created_by: @admin_user.email,
        import_batch_id: SecureRandom.uuid
      )

      if pattern.save
        @imported_count += 1
        log_import_success(pattern, row_number)
      else
        @errors << "Row #{row_number}: #{pattern.errors.full_messages.join(', ')}"
      end
    rescue StandardError => e
      @errors << "Row #{row_number}: #{e.message}"
    end

    def sanitize_string(value)
      return nil if value.blank?

      # Remove potentially dangerous characters and limit length
      value.to_s.strip.gsub(/[^\w\s\-\.@]/, "").slice(0, 255)
    end

    def sanitize_pattern_value(value, pattern_type)
      return nil if value.blank?

      case pattern_type
      when "regex"
        # Don't modify regex patterns but validate them
        value.to_s.strip.slice(0, 500)
      when "amount_range"
        # Validate amount range format
        sanitize_amount_range(value)
      else
        # Regular string sanitization
        value.to_s.strip.slice(0, 500)
      end
    end

    def sanitize_amount_range(value)
      # Expected format: "min-max" or "min-" or "-max"
      match = value.to_s.match(/^(\d*\.?\d*)-(\d*\.?\d*)$/)
      return value unless match

      min_val = match[1].presence&.to_f
      max_val = match[2].presence&.to_f

      # Validate reasonable ranges
      if min_val && min_val < 0
        raise ArgumentError, "Negative amounts not allowed"
      end

      if max_val && max_val > 1_000_000
        raise ArgumentError, "Amount exceeds maximum allowed (1,000,000)"
      end

      if min_val && max_val && min_val > max_val
        raise ArgumentError, "Invalid range: min > max"
      end

      value
    end

    def sanitize_integer(value)
      return nil if value.blank?
      Integer(value.to_s.strip)
    rescue ArgumentError
      nil
    end

    def sanitize_float(value)
      return nil if value.blank?

      float_val = Float(value.to_s.strip)

      # Validate reasonable confidence weights
      return 1.0 if float_val < 0.1 || float_val > 10.0

      float_val
    rescue ArgumentError
      nil
    end

    def sanitize_boolean(value)
      return true if value.blank? # Default to active

      ActiveModel::Type::Boolean.new.cast(value)
    end

    def validate_regex_safety(pattern, row_number)
      # Check for common ReDoS patterns
      redos_patterns = [
        /(\w+\+)+/,           # Excessive backtracking
        /(\w*\*)+/,           # Catastrophic backtracking
        /(\(.+\)\?)+/,        # Nested quantifiers
        /(\\[dws]\+){3,}/,    # Multiple consecutive quantifiers
        /\(\?R\)/            # Recursive patterns
      ]

      redos_patterns.each do |redos_pattern|
        if pattern.match?(redos_pattern)
          @errors << "Row #{row_number}: Potentially dangerous regex pattern detected"
          return
        end
      end

      # Try to compile the regex with timeout
      begin
        Timeout.timeout(0.1) do
          Regexp.new(pattern)
        end
      rescue RegexpError => e
        @errors << "Row #{row_number}: Invalid regex: #{e.message}"
      rescue Timeout::Error
        @errors << "Row #{row_number}: Regex compilation timeout - pattern may be too complex"
      end
    end

    def log_import_success(pattern, row_number)
      Rails.logger.info(
        {
          event: "pattern_imported",
          pattern_id: pattern.id,
          row_number: row_number,
          admin_user: @admin_user.email,
          timestamp: Time.current.iso8601
        }.to_json
      )
    end
  end
end
