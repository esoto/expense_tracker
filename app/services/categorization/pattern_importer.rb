# frozen_string_literal: true

module Services::Categorization
  # Service for importing categorization patterns from CSV files.
  #
  # Accepts an ActionDispatch::Http::UploadedFile or any IO-like object with
  # a #path method (e.g. Tempfile, File). Validates the CSV, creates
  # CategorizationPattern records, and returns a result hash.
  #
  # Returns:
  #   { success: true,  imported_count: N }
  #   { success: false, error: "message" }
  class PatternImporter
    REQUIRED_HEADERS = %w[pattern_type pattern_value category_name].freeze
    MAX_FILE_SIZE    = 5.megabytes
    MAX_ROWS         = 10_000

    def import(file)
      return { success: false, error: "No file provided" } if file.nil?

      validate_file_size!(file)
      rows, headers = parse_csv(file)
      validate_headers!(headers)
      import_rows(rows)
    rescue CSV::MalformedCSVError => e
      { success: false, error: "Invalid CSV format: #{e.message}" }
    rescue ImportError => e
      { success: false, error: e.message }
    rescue StandardError => e
      Rails.logger.error "[PatternImporter] Unexpected error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
      { success: false, error: "Import failed: #{e.message}" }
    end

    private

    # Custom error class used only within this service
    class ImportError < StandardError; end

    def validate_file_size!(file)
      size = file.respond_to?(:size) ? file.size : File.size(file.path)
      if size > MAX_FILE_SIZE
        raise ImportError, "File is too large (maximum is #{MAX_FILE_SIZE / 1.megabyte}MB)"
      end
    end

    def parse_csv(file)
      path = file.respond_to?(:path) ? file.path : file.to_s
      rows    = []
      headers = nil

      CSV.foreach(path, headers: true, header_converters: :downcase) do |row|
        headers ||= row.headers
        rows << row
        raise ImportError, "Exceeded maximum row limit of #{MAX_ROWS}" if rows.size > MAX_ROWS
      end

      [ rows, headers || [] ]
    end

    def validate_headers!(headers)
      missing = REQUIRED_HEADERS - Array(headers).map(&:to_s)
      return if missing.empty?

      raise ImportError, "Missing required headers: #{missing.join(', ')}"
    end

    def import_rows(rows)
      return { success: true, imported_count: 0 } if rows.empty?

      imported_count = 0
      errors         = []

      ActiveRecord::Base.transaction do
        rows.each_with_index do |row, idx|
          row_number = idx + 2 # 1-based + header row
          result     = import_row(row, row_number)

          if result[:error]
            errors << result[:error]
          elsif result[:ok]
            imported_count += 1
          end
          # result[:skipped] means duplicate — not an error, not imported
        end

        raise ActiveRecord::Rollback if errors.any?
      end

      if errors.any?
        { success: false, error: errors.first }
      else
        { success: true, imported_count: imported_count }
      end
    end

    def import_row(row, row_number)
      pattern_type  = sanitize_string(row["pattern_type"])
      pattern_value = sanitize_string(row["pattern_value"])
      category_name = sanitize_string(row["category_name"])

      if pattern_type.blank? || pattern_value.blank? || category_name.blank?
        return { error: "Row #{row_number}: pattern_type, pattern_value, and category_name are required" }
      end

      # Normalize pattern_value the same way the model does (before_validation callback
      # in PatternValidation downcases text-based patterns) so duplicate checks are accurate.
      pattern_value = normalize_pattern_value(pattern_type, pattern_value)

      category = Category.find_by(name: category_name)
      return { error: "Row #{row_number}: Category '#{category_name}' not found" } if category.nil?

      if duplicate_pattern?(pattern_type, pattern_value, category.id)
        return { skipped: true }
      end

      confidence_weight = parse_confidence_weight(row["confidence_weight"])
      active            = parse_boolean(row["active"], default: true)

      pattern = CategorizationPattern.new(
        pattern_type:      pattern_type,
        pattern_value:     pattern_value,
        category:          category,
        confidence_weight: confidence_weight,
        active:            active,
        user_created:      true,
        usage_count:       0,
        success_count:     0,
        success_rate:      0.0
      )

      if pattern.save
        { ok: true }
      else
        { error: "Row #{row_number}: #{pattern.errors.full_messages.join(', ')}" }
      end
    rescue StandardError => e
      { error: "Row #{row_number}: #{e.message}" }
    end

    # Mirror the normalization done by PatternValidation#normalize_pattern_value so that
    # duplicate checks and pre-save comparisons use the same canonical form.
    def normalize_pattern_value(type, value)
      return value if value.blank?

      case type
      when "merchant", "keyword", "description", "time"
        value.strip.downcase.gsub(/\s+/, " ")
      when "regex"
        value.strip
      else
        value
      end
    end

    def sanitize_string(value)
      return nil if value.blank?

      value.to_s.strip.gsub(/[\x00-\x1F\x7F]/, "").truncate(255)
    end

    def parse_confidence_weight(value)
      return CategorizationPattern::DEFAULT_CONFIDENCE_WEIGHT if value.blank?

      value.to_f.clamp(
        CategorizationPattern::MIN_CONFIDENCE_WEIGHT,
        CategorizationPattern::MAX_CONFIDENCE_WEIGHT
      )
    end

    def parse_boolean(value, default: false)
      return default if value.blank?

      ActiveModel::Type::Boolean.new.cast(value)
    end

    def duplicate_pattern?(pattern_type, pattern_value, category_id)
      CategorizationPattern.exists?(
        pattern_type:  pattern_type,
        pattern_value: pattern_value,
        category_id:   category_id
      )
    end
  end
end
