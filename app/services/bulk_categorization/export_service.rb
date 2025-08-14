# frozen_string_literal: true

require "csv"

module Services::BulkCategorization
  # Service to export categorization reports in various formats
  class ExportService
    attr_reader :start_date, :end_date, :format

    def initialize(start_date: nil, end_date: nil, format: "csv")
      @start_date = parse_date(start_date) || 30.days.ago.to_date
      @end_date = parse_date(end_date) || Date.current
      @format = format
    end

    def to_csv
      CSV.generate(headers: true) do |csv|
        csv << csv_headers

        categorization_data.each do |row|
          csv << format_csv_row(row)
        end
      end
    end

    def to_xlsx
      # For Excel export, you would need to add the 'axlsx' gem
      # This is a placeholder implementation
      raise NotImplementedError, "Excel export requires the axlsx gem"
    end

    def to_json
      {
        report: {
          generated_at: Time.current,
          period: {
            start: start_date,
            end: end_date
          },
          summary: generate_summary,
          categorizations: categorization_data.map { |row| format_json_row(row) }
        }
      }
    end

    private

    def parse_date(date_string)
      return nil if date_string.blank?
      Date.parse(date_string)
    rescue ArgumentError
      nil
    end

    def categorization_data
      @categorization_data ||= begin
        expenses = Expense
          .includes(:category, :email_account)
          .where(transaction_date: start_date..end_date)
          .where.not(categorized_at: nil)
          .order(categorized_at: :desc)

        expenses.map do |expense|
          {
            expense: expense,
            category: expense.category,
            email_account: expense.email_account,
            categorized_at: expense.categorized_at,
            method: expense.categorization_method,
            confidence: expense.categorization_confidence,
            auto: expense.auto_categorized
          }
        end
      end
    end

    def generate_summary
      total_expenses = categorization_data.count
      auto_categorized = categorization_data.count { |d| d[:auto] }
      manual_categorized = total_expenses - auto_categorized

      categories_used = categorization_data.map { |d| d[:category]&.id }.uniq.compact

      confidence_breakdown = {
        high: categorization_data.count { |d| (d[:confidence] || 0) > 0.8 },
        medium: categorization_data.count { |d| (d[:confidence] || 0).between?(0.6, 0.8) },
        low: categorization_data.count { |d| (d[:confidence] || 0) < 0.6 }
      }

      {
        total_categorized: total_expenses,
        auto_categorized: auto_categorized,
        manual_categorized: manual_categorized,
        unique_categories: categories_used.count,
        average_confidence: calculate_average_confidence,
        confidence_breakdown: confidence_breakdown,
        total_amount: categorization_data.sum { |d| d[:expense].amount },
        methods_used: categorization_data.map { |d| d[:method] }.uniq.compact
      }
    end

    def calculate_average_confidence
      confidences = categorization_data.map { |d| d[:confidence] }.compact
      return 0 if confidences.empty?

      (confidences.sum / confidences.count.to_f).round(3)
    end

    def csv_headers
      [
        "Transaction Date",
        "Amount",
        "Currency",
        "Description",
        "Merchant",
        "Bank",
        "Category",
        "Parent Category",
        "Categorized At",
        "Categorization Method",
        "Confidence",
        "Auto Categorized"
      ]
    end

    def format_csv_row(data)
      expense = data[:expense]
      category = data[:category]

      [
        expense.transaction_date.strftime("%Y-%m-%d"),
        expense.amount,
        expense.currency,
        expense.description,
        expense.merchant_name,
        expense.bank_name,
        category&.name,
        category&.parent&.name,
        data[:categorized_at]&.strftime("%Y-%m-%d %H:%M:%S"),
        data[:method],
        data[:confidence]&.round(3),
        data[:auto] ? "Yes" : "No"
      ]
    end

    def format_json_row(data)
      expense = data[:expense]
      category = data[:category]

      {
        expense_id: expense.id,
        transaction_date: expense.transaction_date,
        amount: expense.amount,
        currency: expense.currency,
        description: expense.description,
        merchant: expense.merchant_name,
        bank: expense.bank_name,
        category: {
          id: category&.id,
          name: category&.name,
          parent: category&.parent&.name
        },
        categorization: {
          categorized_at: data[:categorized_at],
          method: data[:method],
          confidence: data[:confidence]&.round(3),
          auto: data[:auto]
        }
      }
    end
  end
end
