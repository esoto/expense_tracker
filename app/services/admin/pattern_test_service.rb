# frozen_string_literal: true

module Admin
  # Service for testing patterns with proper input sanitization
  class PatternTestService
    include ActiveModel::Model

    MAX_INPUT_LENGTH = 1000
    MAX_PATTERNS_TO_TEST = 100
    TIMEOUT_SECONDS = 1

    attr_accessor :description, :merchant_name, :amount, :transaction_date
    attr_reader :matching_patterns, :test_expense

    validates :description, length: { maximum: MAX_INPUT_LENGTH }
    validates :merchant_name, length: { maximum: MAX_INPUT_LENGTH }
    validates :amount, numericality: { greater_than_or_equal_to: 0, less_than: 10_000_000 }, allow_nil: true

    def initialize(params = {})
      @description = sanitize_text(params[:description])
      @merchant_name = sanitize_text(params[:merchant_name])
      @amount = sanitize_amount(params[:amount])
      @transaction_date = sanitize_date(params[:transaction_date])
      @matching_patterns = []
    end

    def test_patterns
      return false unless valid?

      build_test_expense
      find_matching_patterns
      sort_by_confidence

      true
    rescue StandardError => e
      Rails.logger.error "Pattern test error: #{e.message}"
      errors.add(:base, "Pattern testing failed: #{e.message}")
      false
    end

    def test_single_pattern(pattern)
      return false unless valid?

      build_test_expense

      Timeout.timeout(TIMEOUT_SECONDS) do
        pattern.matches?(@test_expense)
      end
    rescue Timeout::Error
      Rails.logger.warn "Pattern test timeout for pattern #{pattern.id}"
      errors.add(:base, "Pattern test timed out - pattern may be too complex")
      false
    rescue StandardError => e
      Rails.logger.error "Single pattern test error: #{e.message}"
      errors.add(:base, "Pattern test failed: #{e.message}")
      false
    end

    private

    def sanitize_text(value)
      return nil if value.blank?

      # Remove SQL injection attempts and limit length
      value.to_s
        .gsub(/['";\\]/, "") # Remove common SQL injection characters
        .gsub(/\s+/, " ")    # Normalize whitespace
        .strip
        .slice(0, MAX_INPUT_LENGTH)
    end

    def sanitize_amount(value)
      return nil if value.blank?

      amount = value.to_s.gsub(/[^\d\.]/, "").to_f

      # Validate reasonable amount range
      return nil if amount < 0 || amount >= 10_000_000

      amount
    rescue StandardError
      nil
    end

    def sanitize_date(value)
      return DateTime.current if value.blank?

      date = DateTime.parse(value.to_s)

      # Validate reasonable date range (not more than 10 years in past or future)
      min_date = 10.years.ago
      max_date = 10.years.from_now

      return DateTime.current if date < min_date || date > max_date

      date
    rescue StandardError
      DateTime.current
    end

    def build_test_expense
      @test_expense = OpenStruct.new(
        description: @description,
        merchant_name: @merchant_name,
        amount: @amount,
        transaction_date: @transaction_date
      )
    end

    def find_matching_patterns
      # Use cached patterns if available
      patterns = Rails.cache.fetch("active_patterns", expires_in: 5.minutes) do
        CategorizationPattern.active.includes(:category).limit(MAX_PATTERNS_TO_TEST).to_a
      end

      patterns.each do |pattern|
        begin
          if test_pattern_with_timeout(pattern)
            @matching_patterns << build_match_result(pattern)
          end
        rescue StandardError => e
          Rails.logger.warn "Pattern #{pattern.id} test failed: #{e.message}"
          next
        end
      end
    end

    def test_pattern_with_timeout(pattern)
      Timeout.timeout(TIMEOUT_SECONDS) do
        pattern.matches?(@test_expense)
      end
    rescue Timeout::Error
      Rails.logger.warn "Pattern #{pattern.id} test timeout"
      false
    end

    def build_match_result(pattern)
      {
        pattern: pattern,
        confidence: pattern.effective_confidence,
        category: pattern.category,
        pattern_type: pattern.pattern_type,
        created_at: pattern.created_at
      }
    end

    def sort_by_confidence
      @matching_patterns.sort_by! { |match| -match[:confidence] }
    end
  end
end
