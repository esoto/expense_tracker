require "digest"

module Services::EmailProcessing
  class Parser
    MAX_EMAIL_SIZE = 50_000  # 50KB threshold
    TRUNCATE_SIZE = 10_000   # Store only 10KB for large emails

    attr_reader :email_account, :email_data, :parsing_rule, :errors

    def initialize(email_account, email_data, pre_parsed_data: nil)
      @email_account = email_account
      @email_data = email_data
      @pre_parsed_data = pre_parsed_data
      @parsing_rule = find_parsing_rule
      @errors = []
    end

    def parse_expense
      return nil unless parsing_rule

      begin
        parsed_data = if @pre_parsed_data
          # Convert amount back from String to BigDecimal (serialized as String
          # in Processor to avoid ActiveJob Float rounding on financial values)
          @pre_parsed_data.merge(amount: @pre_parsed_data[:amount] ? BigDecimal(@pre_parsed_data[:amount].to_s) : nil)
        else
          strategy = Services::EmailProcessing::StrategyFactory.create_strategy(parsing_rule, email_content: email_content)
          strategy.parse_email(email_content)
        end

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
      return false unless parsed_data[:amount].present? && parsed_data[:transaction_date].present?

      # Coerce transaction_date to Date — reject if unparseable
      unless parsed_data[:transaction_date].is_a?(Date) || parsed_data[:transaction_date].is_a?(Time)
        begin
          parsed_data[:transaction_date] = parsed_data[:transaction_date].to_date
        rescue NoMethodError, ArgumentError, TypeError
          return false
        end
      end

      true
    end

    def create_expense(parsed_data)
      ActiveRecord::Base.transaction do
        acquire_expense_advisory_lock(parsed_data)

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
        rescue ArgumentError, EncodingError => e
          Rails.logger.warn("[Parser] Currency detection failed: #{e.class.name} - #{e.message}")
          add_error("Currency detection failed: #{e.message}")
        end

        if expense.save
          # Auto-categorize after save (Engine requires persisted expense)
          begin
            categorize_expense(expense)
          rescue Services::Categorization::Engine::CategorizationError,
                 ActiveRecord::RecordNotFound,
                 ActiveRecord::RecordInvalid,
                 ArgumentError => e
            Rails.logger.warn("[Parser] Categorization failed: #{e.class.name} - #{e.message}")
            add_error("Category guess failed: #{e.message}")
          end

          expense.update(status: :processed)
          Rails.logger.info "Created expense: #{expense.formatted_amount} from #{email_account&.email}"
          expense
        else
          add_error("Failed to save expense: #{expense.errors.full_messages.join(", ")}")
          nil
        end
      end
    rescue ActiveRecord::RecordNotUnique
      handle_record_not_unique(parsed_data)
    end

    def handle_record_not_unique(parsed_data)
      existing = Expense.where(
        email_account: email_account,
        amount: parsed_data[:amount],
        transaction_date: parsed_data[:transaction_date],
        merchant_name: parsed_data[:merchant_name],
        deleted_at: nil
      ).first

      if existing
        existing.update(status: :duplicate)
        add_error("Duplicate expense detected via unique constraint")
        existing
      else
        add_error("Duplicate expense conflict but original not found")
        nil
      end
    end

    def advisory_lock_key(email_account_id, amount, transaction_date, merchant_name)
      date_str = begin
        transaction_date&.to_date
      rescue NoMethodError, ArgumentError
        nil
      end || Date.current
      raw = "#{email_account_id}:#{amount}:#{date_str}:#{merchant_name.to_s.downcase.strip}"
      Digest::SHA256.hexdigest(raw).to_i(16) % (2**63 - 1)
    end

    def acquire_expense_advisory_lock(parsed_data)
      return unless email_account

      lock_key = advisory_lock_key(
        email_account.id,
        parsed_data[:amount],
        parsed_data[:transaction_date],
        parsed_data[:merchant_name]
      )
      sanitized = ActiveRecord::Base.sanitize_sql_array(
        [ "SELECT pg_advisory_xact_lock(?)", lock_key ]
      )
      ActiveRecord::Base.connection.execute(sanitized)
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
      currency_detector = Services::CurrencyDetectorService.new(email_content: email_content)
      currency_detector.apply_currency_to_expense(expense, parsed_data)
    end

    def categorize_expense(expense)
      engine = Services::Categorization::Engine.create
      result = engine.categorize(expense, auto_update: false)

      return unless result&.successful?

      expense.update(
        category_id: result.category.id,
        auto_categorized: true,
        categorization_confidence: result.confidence,
        categorization_method: result.method || "engine"
      )
    end

    def add_error(message)
      @errors << message
      email_info = email_account&.email || "unknown"
      Rails.logger.error "[Services::EmailProcessing::Parser] #{email_info}: #{message}"
    end

    def process_large_email(content)
      # Extract only the essential parts for large emails
      Rails.logger.warn "[EmailProcessing] Large email detected: #{content.bytesize} bytes"

      # Process in chunks to avoid memory bloat
      processed = StringIO.new
      # Force to string and handle encoding issues
      content = content.to_s.force_encoding("BINARY")

      bytes_accumulated = 0
      content.each_line do |line|
        # Truncate individual lines if they're too long
        line = line[0...1000] if line.length > 1000

        decoded_line = decode_quoted_printable_line(line)
        # Force to UTF-8 and scrub each line
        final_line = decoded_line.force_encoding("UTF-8").scrub
        processed << final_line
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
