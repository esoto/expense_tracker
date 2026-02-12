# frozen_string_literal: true

require "ostruct"

module Services::Patterns
  # Service object for testing categorization patterns against expenses
  # with caching and performance optimization
  class PatternTester
    include ActiveModel::Model

    attr_accessor :description, :merchant_name, :amount, :transaction_date
    attr_reader :matching_patterns, :test_expense

    validates :description, presence: true, length: { maximum: 500 }
    validates :amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validate :validate_inputs_security

    def initialize(params = {})
      @description = sanitize_input(params[:description])
      @merchant_name = sanitize_input(params[:merchant_name])
      @amount = parse_amount(params[:amount])
      @transaction_date = parse_date(params[:transaction_date])
      @matching_patterns = []
    end

    def test
      return false unless valid?

      build_test_expense
      find_matching_patterns
      sort_by_confidence

      true
    end

    def best_match
      @matching_patterns.first
    end

    def confidence_for_category(category_id)
      matches = @matching_patterns.select { |m| m[:category].id == category_id }
      return 0.0 if matches.empty?

      # Combine confidence scores for same category
      matches.map { |m| m[:confidence] }.max
    end

    def categories_with_confidence
      @matching_patterns
        .group_by { |m| m[:category] }
        .map do |category, matches|
          {
            category: category,
            confidence: matches.map { |m| m[:confidence] }.max,
            pattern_count: matches.size,
            patterns: matches.map { |m| m[:pattern] }
          }
        end
        .sort_by { |c| -c[:confidence] }
    end

    private

    def validate_inputs_security
      # Check for potential XSS or injection attempts
      [ @description, @merchant_name ].compact.each do |input|
        if contains_suspicious_content?(input)
          errors.add(:base, "Input contains potentially malicious content")
        end
      end
    end

    def contains_suspicious_content?(text)
      return false if text.blank?

      # Check for script tags or javascript
      return true if text.match?(/<script|javascript:|data:text\/html/i)

      # Check for SQL injection patterns
      return true if text.match?(/(\b(union|select|insert|update|delete|drop|create|alter)\b.*\b(from|into|where|table)\b)/i)

      false
    end

    def sanitize_input(value)
      return nil if value.blank?

      # Remove HTML tags and dangerous characters
      ActionController::Base.helpers.sanitize(value.to_s, tags: [])
        .strip
        .truncate(500)
    end

    def parse_amount(value)
      return nil if value.blank?

      # Clean and parse amount
      cleaned = value.to_s.gsub(/[^\d.-]/, "")
      amount = cleaned.to_f

      # Validate reasonable range for financial amounts
      return nil if amount < -1_000_000 || amount > 1_000_000

      amount
    end

    def parse_date(value)
      return DateTime.current if value.blank?

      case value
      when DateTime, Time
        value
      when Date
        value.to_datetime
      when String
        DateTime.parse(value)
      else
        DateTime.current
      end
    rescue ArgumentError
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
      # Use optimized scope with includes to prevent N+1
      patterns = CategorizationPattern
        .active
        .includes(:category)
        .for_matching

      # Process in batches for memory efficiency
      patterns.find_in_batches(batch_size: 100) do |batch|
        batch.each do |pattern|
          if pattern.matches?(@test_expense)
            @matching_patterns << {
              pattern: pattern,
              confidence: pattern.effective_confidence,
              category: pattern.category,
              match_type: pattern.pattern_type
            }
          end
        end
      end
    end

    def sort_by_confidence
      @matching_patterns.sort_by! { |m| -m[:confidence] }
    end
  end
end
