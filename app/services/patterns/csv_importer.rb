# frozen_string_literal: true

module Patterns
  # Service object for importing categorization patterns from CSV files
  # with comprehensive validation and security checks
  class CsvImporter
    include ActiveModel::Model

    # Constants
    MAX_FILE_SIZE = 5.megabytes
    MAX_ROWS = 10_000
    ALLOWED_MIME_TYPES = [ "text/csv", "text/plain", "application/vnd.ms-excel" ].freeze
    REQUIRED_HEADERS = %w[pattern_type pattern_value category_id].freeze
    OPTIONAL_HEADERS = %w[confidence_weight active metadata].freeze

    attr_accessor :file, :user, :dry_run
    attr_reader :imported_count, :errors, :skipped_count, :patterns

    validates :file, presence: true
    validate :validate_file_security
    validate :validate_file_format

    def initialize(file:, user: nil, dry_run: false)
      @file = file
      @user = user
      @dry_run = dry_run
      @imported_count = 0
      @skipped_count = 0
      @errors = []
      @patterns = []
    end

    def import
      return false unless valid?

      process_csv_file

      @errors.empty?
    rescue CSV::MalformedCSVError => e
      @errors << "Invalid CSV format: #{e.message}"
      false
    rescue StandardError => e
      Rails.logger.error "CSV Import failed: #{e.message}\n#{e.backtrace.join("\n")}"
      @errors << "Import failed: #{e.message}"
      false
    end

    def success?
      @errors.empty? && @imported_count > 0
    end

    def summary
      {
        imported: @imported_count,
        skipped: @skipped_count,
        errors: @errors.size,
        total_rows: @imported_count + @skipped_count + @errors.size
      }
    end

    private

    def validate_file_security
      return if file.blank?

      # Check file size
      if file.size > MAX_FILE_SIZE
        errors.add(:file, "is too large (maximum is #{MAX_FILE_SIZE / 1.megabyte}MB)")
      end

      # Check MIME type
      mime_type = Marcel::MimeType.for(file)
      unless ALLOWED_MIME_TYPES.include?(mime_type)
        errors.add(:file, "must be a CSV file")
      end

      # Scan for malicious content
      validate_file_content_security
    end

    def validate_file_content_security
      # Basic security scan for common attack patterns
      content = file.read(1024) # Read first 1KB for quick scan
      file.rewind

      # Check for formula injection attempts
      if content.match?(/^[=+\-@]/) || content.match?(/[\r\n][=+\-@]/)
        errors.add(:file, "contains potentially malicious content")
      end

      # Check for null bytes
      if content.include?("\x00")
        errors.add(:file, "contains invalid characters")
      end
    end

    def validate_file_format
      return if file.blank? || errors.any?

      # Validate CSV structure
      headers = CSV.parse_line(file.readline)
      file.rewind

      missing_headers = REQUIRED_HEADERS - headers.map(&:to_s).map(&:downcase)
      if missing_headers.any?
        errors.add(:file, "missing required headers: #{missing_headers.join(', ')}")
      end
    rescue StandardError => e
      errors.add(:file, "invalid format: #{e.message}")
    end

    def process_csv_file
      row_count = 0

      ActiveRecord::Base.transaction do
        CSV.foreach(file.path, headers: true, header_converters: :downcase) do |row|
          row_count += 1

          # Check row limit
          if row_count > MAX_ROWS
            @errors << "Exceeded maximum row limit of #{MAX_ROWS}"
            raise ActiveRecord::Rollback
          end

          process_row(row, row_count)
        end

        # Rollback if dry run
        raise ActiveRecord::Rollback if @dry_run
      end
    end

    def process_row(row, row_number)
      # Sanitize and validate row data
      sanitized_data = sanitize_row_data(row)

      # Validate category exists
      unless Category.exists?(sanitized_data[:category_id])
        @errors << "Row #{row_number}: Category ID #{sanitized_data[:category_id]} does not exist"
        @skipped_count += 1
        return
      end

      # Check for duplicates
      if duplicate_pattern?(sanitized_data)
        @skipped_count += 1
        return
      end

      # Create pattern
      pattern = CategorizationPattern.new(sanitized_data)
      pattern.user_created = true
      pattern.usage_count = 0
      pattern.success_count = 0
      pattern.success_rate = 0.0

      if pattern.save
        @patterns << pattern
        @imported_count += 1
      else
        @errors << "Row #{row_number}: #{pattern.errors.full_messages.join(', ')}"
      end
    rescue StandardError => e
      @errors << "Row #{row_number}: #{e.message}"
    end

    def sanitize_row_data(row)
      {
        pattern_type: sanitize_string(row["pattern_type"]),
        pattern_value: sanitize_pattern_value(row["pattern_value"], row["pattern_type"]),
        category_id: row["category_id"].to_i,
        confidence_weight: parse_confidence_weight(row["confidence_weight"]),
        active: parse_boolean(row["active"], default: true),
        metadata: parse_metadata(row["metadata"])
      }.compact
    end

    def sanitize_string(value)
      return nil if value.blank?

      # Remove control characters and excessive whitespace
      value.to_s.strip.gsub(/[\x00-\x1F\x7F]/, "").truncate(255)
    end

    def sanitize_pattern_value(value, pattern_type)
      sanitized = sanitize_string(value)
      return sanitized if sanitized.blank?

      case pattern_type&.downcase
      when "regex"
        # Validate regex safety
        validate_safe_regex(sanitized) ? sanitized : nil
      when "amount_range"
        # Validate amount range format
        sanitized if sanitized.match?(/\A-?\d+(\.\d{1,2})?--?\d+(\.\d{1,2})?\z/)
      else
        sanitized
      end
    end

    def validate_safe_regex(pattern)
      return false if pattern.blank?

      # Check for ReDoS vulnerabilities
      dangerous_patterns = [
        /\([^)]*[+*]\)[+*]/,
        /\[[^\]]*[+*]\][+*]/,
        /(\w+[+*])+[+*]/,
        /\(.+[+*].+\)[+*]/
      ]

      return false if dangerous_patterns.any? { |dp| pattern.match?(dp) }

      # Try to compile the regex with timeout
      Timeout.timeout(1) do
        Regexp.new(pattern)
      end

      true
    rescue RegexpError, Timeout::Error
      false
    end

    def parse_confidence_weight(value)
      return CategorizationPattern::DEFAULT_CONFIDENCE_WEIGHT if value.blank?

      weight = value.to_f
      weight.clamp(
        CategorizationPattern::MIN_CONFIDENCE_WEIGHT,
        CategorizationPattern::MAX_CONFIDENCE_WEIGHT
      )
    end

    def parse_boolean(value, default: false)
      return default if value.blank?

      ActiveModel::Type::Boolean.new.cast(value)
    end

    def parse_metadata(value)
      return {} if value.blank?

      JSON.parse(value).slice(*allowed_metadata_keys)
    rescue JSON::ParserError
      {}
    end

    def allowed_metadata_keys
      %w[source notes priority tags]
    end

    def duplicate_pattern?(data)
      CategorizationPattern.exists?(
        pattern_type: data[:pattern_type],
        pattern_value: data[:pattern_value],
        category_id: data[:category_id]
      )
    end
  end
end
