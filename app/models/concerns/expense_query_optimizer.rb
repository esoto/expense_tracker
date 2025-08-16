# frozen_string_literal: true

# ExpenseQueryOptimizer provides optimized database queries for expense filtering
# Uses covering indexes and efficient scopes to achieve <50ms query performance
module ExpenseQueryOptimizer
  extend ActiveSupport::Concern

  included do
    # Optimized scopes using indexes
    scope :for_list_display, -> {
      includes(:category, :email_account)
        .where(deleted_at: nil)
    }

    scope :with_filters, ->(filters) {
      query = for_list_display
      query = query.by_date_range(filters[:start_date], filters[:end_date]) if filters[:start_date].present?
      query = query.by_categories(filters[:category_ids]) if filters[:category_ids].present?
      query = query.by_banks(filters[:banks]) if filters[:banks].present?
      query = query.by_amount_range(filters[:min_amount], filters[:max_amount]) if filters[:min_amount].present?
      query = query.by_status(filters[:status]) if filters[:status].present?
      query = query.search_merchant(filters[:search]) if filters[:search].present?
      query
    }

    scope :by_categories, ->(category_ids) {
      if category_ids.include?(nil) || category_ids.include?("uncategorized")
        where(category_id: category_ids.compact).or(where(category_id: nil))
      else
        where(category_id: category_ids)
      end
    }

    scope :by_banks, ->(banks) {
      where(bank_name: banks)
    }

    scope :by_amount_range, ->(min_amount, max_amount) {
      query = current_scope || where(nil)
      query = query.where("amount >= ?", min_amount.to_f) if min_amount.present?
      query = query.where("amount <= ?", max_amount.to_f) if max_amount.present?
      query
    }

    scope :search_merchant, ->(term) {
      return current_scope || where(nil) if term.blank?
      # Use trigram search for fuzzy matching if available
      if connection.extension_enabled?("pg_trgm")
        where("merchant_normalized % ?", term)
      else
        where("LOWER(merchant_normalized) LIKE ?", "%#{term.downcase}%")
      end
    }

    # Additional optimized scopes
    scope :not_deleted, -> { where(deleted_at: nil) }
    scope :deleted, -> { where.not(deleted_at: nil) }
    scope :with_category, -> { where.not(category_id: nil) }
    scope :without_category, -> { where(category_id: nil) }
  end

  class_methods do
    def list_display_columns
      %w[
        expenses.id
        expenses.amount
        expenses.description
        expenses.transaction_date
        expenses.merchant_name
        expenses.category_id
        expenses.status
        expenses.bank_name
        expenses.currency
        expenses.created_at
        expenses.updated_at
        expenses.deleted_at
        expenses.lock_version
      ]
    end

    # Batch loading with cursor-based pagination for large datasets
    def cursor_paginate(cursor: nil, limit: 50, direction: :forward)
      query = self.for_list_display.order(transaction_date: :desc, id: :desc)

      if cursor
        begin
          decoded = decode_cursor(cursor)
          # Validate cursor data
          raise ArgumentError, "Invalid cursor: missing date" unless decoded[:date]
          raise ArgumentError, "Invalid cursor: missing id" unless decoded[:id]

          if direction == :forward
            query = query.where("(transaction_date, id) < (?, ?)", decoded[:date], decoded[:id])
          else
            query = query.where("(transaction_date, id) > (?, ?)", decoded[:date], decoded[:id])
          end
        rescue ArgumentError => e
          Rails.logger.warn "Invalid cursor provided: #{e.message}"
          # Return unpaginated query on invalid cursor
        end
      end

      query.limit([ limit.to_i, 100 ].min) # Cap at 100 for safety
    end

    # Optimized aggregation queries
    def aggregate_by_category(start_date: nil, end_date: nil)
      query = not_deleted
      query = query.by_date_range(start_date, end_date) if start_date && end_date

      query
        .group(:category_id)
        .pluck(
          Arel.sql("category_id"),
          Arel.sql("COUNT(*) as count"),
          Arel.sql("SUM(amount) as total"),
          Arel.sql("AVG(amount) as average")
        )
        .map do |row|
          {
            category_id: row[0],
            count: row[1],
            total: row[2].to_f,
            average: row[3].to_f
          }
        end
    end

    def aggregate_by_period(period: :month, start_date: nil, end_date: nil)
      query = not_deleted
      query = query.by_date_range(start_date, end_date) if start_date && end_date

      date_trunc = case period
      when :day then "DATE_TRUNC('day', transaction_date)"
      when :week then "DATE_TRUNC('week', transaction_date)"
      when :month then "DATE_TRUNC('month', transaction_date)"
      when :year then "DATE_TRUNC('year', transaction_date)"
      else "DATE_TRUNC('month', transaction_date)"
      end

      query
        .group(Arel.sql(date_trunc))
        .pluck(
          Arel.sql(date_trunc),
          Arel.sql("COUNT(*) as count"),
          Arel.sql("SUM(amount) as total")
        )
        .map do |row|
          {
            period: row[0],
            count: row[1],
            total: row[2].to_f
          }
        end
    end

    # Check if indexes are being used (for monitoring)
    def explain_query(scope)
      scope.explain
    end

    # Generate cursor for pagination
    def encode_cursor(expense)
      Base64.strict_encode64({
        date: expense.transaction_date.iso8601,
        id: expense.id
      }.to_json)
    end

    private

    def decode_cursor(cursor)
      return nil if cursor.blank?

      decoded = Base64.strict_decode64(cursor)
      parsed = JSON.parse(decoded).symbolize_keys

      # Validate cursor structure
      unless parsed[:date] && parsed[:id]
        raise ArgumentError, "Invalid cursor structure"
      end

      # Parse and validate date
      parsed[:date] = Time.parse(parsed[:date]) if parsed[:date].is_a?(String)
      parsed[:id] = parsed[:id].to_i

      parsed
    rescue JSON::ParserError, ArgumentError => e
      raise ArgumentError, "Invalid cursor: #{e.message}"
    end

    # Extension helper to check if PostgreSQL extension is enabled
    def connection
      ActiveRecord::Base.connection
    end
  end

  # Instance methods for performance optimization
  def cache_key_with_version
    "#{model_name.cache_key}/#{id}-#{updated_at.to_i}-#{lock_version}"
  end

  def soft_delete!(user_id = nil)
    transaction do
      self.deleted_at = Time.current
      self.deleted_by_id = user_id if respond_to?(:deleted_by_id=)
      self.lock_version = (lock_version || 0) + 1
      save!(validate: false)
    end
  end

  def restore!
    transaction do
      self.deleted_at = nil
      self.deleted_by_id = nil if respond_to?(:deleted_by_id=)
      self.lock_version = (lock_version || 0) + 1
      save!(validate: false)
    end
  end

  def deleted?
    deleted_at.present?
  end
end
