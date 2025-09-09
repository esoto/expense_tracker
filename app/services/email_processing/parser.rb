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
      return nil unless email_account
      ParsingRule.active.for_bank(email_account.bank_name).first
    end

    def email_content
      @email_content ||= begin
        # This will raise NoMethodError if email_data is nil
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
      begin
        # Check for potential duplicates
        existing_expense = find_duplicate_expense(parsed_data)
      rescue ActiveRecord::RecordNotFound, ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementTimeout => e
        add_error("Database error during duplicate check: #{e.message}")
        return nil
      end

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
        bank_name: email_account&.bank_name
      )

      # Set currency using enum methods
      begin
        set_currency(expense, parsed_data)
      rescue StandardError => e
        add_error("Currency detection failed: #{e.message}")
        # Don't re-raise, continue with expense creation
      end

      # Try to auto-categorize
      begin
        expense.category = guess_category(expense)
      rescue StandardError => e
        add_error("Category guess failed: #{e.message}")
        # Don't re-raise, continue with expense creation
      end

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
      email_info = email_account&.email || "unknown"
      Rails.logger.error "[EmailProcessing::Parser] #{email_info}: #{message}"
    end

    def process_large_email(content)
      # Extract only the essential parts for large emails
      Rails.logger.warn "[EmailProcessing] Large email detected: #{content.bytesize} bytes"

      # Process in chunks to avoid memory bloat
      processed = StringIO.new
      # Force to string and handle encoding issues
      content = content.to_s.force_encoding("BINARY")

      lines_processed = 0
      bytes_accumulated = 0
      content.each_line do |line|
        break if lines_processed >= 100  # Process only first 100 lines

        # Truncate individual lines if they're too long
        line = line[0...1000] if line.length > 1000

        decoded_line = decode_quoted_printable_line(line)
        # Force to UTF-8 and scrub each line
        final_line = decoded_line.force_encoding("UTF-8").scrub
        processed << final_line
        lines_processed += 1
        bytes_accumulated += final_line.bytesize

        # Safety check: if we've accumulated way too much, stop
        break if bytes_accumulated > 100_000  # 100KB absolute max
      end

      result = processed.string
      processed.close
      result
    end

    def process_standard_email(content)
      # Convert to string and dup to avoid frozen string issues
      content = content.to_s.dup
      # Force to binary first to handle any encoding issues
      content = content.force_encoding("BINARY")
      # Remove soft line breaks
      content = content.gsub(/=\r\n/, "")
      # Decode quoted-printable (handle both uppercase and lowercase hex)
      content = content.gsub(/=([A-Fa-f0-9]{2})/i) { [ $1.hex ].pack("C") }
      # Force to UTF-8 and scrub invalid sequences
      content.force_encoding("UTF-8").scrub
    end

    def decode_quoted_printable_line(line)
      line.gsub(/=\r\n/, "")
          .gsub(/=([A-Fa-f0-9]{2})/i) { [ $1.hex ].pack("C") }
    end
  end
end
