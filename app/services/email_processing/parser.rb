module EmailProcessing
  class Parser
    MAX_EMAIL_SIZE = 50_000  # 50KB threshold
    TRUNCATE_SIZE = 10_000   # Store only 10KB for large emails

    attr_reader :email_account, :email_data, :parsing_rule, :errors

    def initialize(email_account, email_data)
      @email_account = email_account
      @email_data = email_data
      @parsing_rule = find_parsing_rule
      @errors = []
    end

    def parse_expense
      return nil unless parsing_rule

      begin
        parsing_strategy = EmailProcessing::StrategyFactory.create_strategy(parsing_rule, email_content: email_content)
        parsed_data = parsing_strategy.parse_email(email_content)

        if valid_parsed_data?(parsed_data)
          create_expense(parsed_data)
        else
          add_error("Failed to parse essential expense data")
          nil
        end
      rescue StandardError => e
        add_error("Error parsing email: #{e.message}")
        nil
      end
    end

    private

    def find_parsing_rule
      ParsingRule.active.for_bank(email_account.bank_name).first
    end

    def email_content
      @email_content ||= begin
        content = email_data[:body].to_s

        if content.bytesize > MAX_EMAIL_SIZE
          process_large_email(content)
        else
          process_standard_email(content)
        end
      end
    end

    def valid_parsed_data?(parsed_data)
      parsed_data[:amount].present? && parsed_data[:transaction_date].present?
    end

    def create_expense(parsed_data)
      # Check for potential duplicates
      existing_expense = find_duplicate_expense(parsed_data)

      if existing_expense
        existing_expense.update(status: :duplicate)
        add_error("Duplicate expense found")
        return existing_expense
      end

      expense = Expense.new(
        email_account: email_account,
        amount: parsed_data[:amount],
        transaction_date: parsed_data[:transaction_date],
        merchant_name: parsed_data[:merchant_name],
        description: parsed_data[:description],
        raw_email_content: email_content,
        parsed_data: parsed_data.to_json,
        status: :pending,
        email_body: email_data[:body].to_s,
        bank_name: email_account.bank_name
      )

      # Set currency using enum methods
      set_currency(expense, parsed_data)

      # Try to auto-categorize
      expense.category = guess_category(expense)

      if expense.save
        expense.update(status: :processed)
        Rails.logger.info "Created expense: #{expense.formatted_amount} from #{email_account.email}"
        expense
      else
        add_error("Failed to save expense: #{expense.errors.full_messages.join(", ")}")
        nil
      end
    end

    def find_duplicate_expense(parsed_data)
      # Look for expenses with same amount and date from same account within 1 day
      date_range = (parsed_data[:transaction_date] - 1.day)..(parsed_data[:transaction_date] + 1.day)

      Expense.where(
        email_account: email_account,
        amount: parsed_data[:amount],
        transaction_date: date_range
      ).first
    end

    def set_currency(expense, parsed_data)
      currency_detector = CurrencyDetectorService.new(email_content: email_content)
      currency_detector.apply_currency_to_expense(expense, parsed_data)
    end

    def guess_category(expense)
      category_guesser = CategoryGuesserService.new
      category_guesser.guess_category_for_expense(expense)
    end

    def add_error(message)
      @errors << message
      Rails.logger.error "[EmailProcessing::Parser] #{email_account.email}: #{message}"
    end

    def process_large_email(content)
      # Extract only the essential parts for large emails
      Rails.logger.warn "[EmailProcessing] Large email detected: #{content.bytesize} bytes"

      # Process in chunks to avoid memory bloat
      processed = StringIO.new
      content.each_line.first(100).each do |line|  # Process only first 100 lines
        processed << decode_quoted_printable_line(line)
      end

      result = processed.string.force_encoding("UTF-8").scrub
      processed.close
      result
    end

    def process_standard_email(content)
      content = content.gsub(/=\r\n/, "")
      content = content.gsub(/=([A-F0-9]{2})/) { [ $1.hex ].pack("C") }
      content.force_encoding("UTF-8").scrub
    end

    def decode_quoted_printable_line(line)
      line.gsub(/=\r\n/, "")
          .gsub(/=([A-F0-9]{2})/) { [ $1.hex ].pack("C") }
    end
  end
end
