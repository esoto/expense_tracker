# frozen_string_literal: true

require "set"

module Services::Email
  # ProcessingService consolidates email fetching, parsing, and processing
  # into a single cohesive service. This replaces multiple separate services
  # for better maintainability and clearer interfaces.
  class ProcessingService
    include ActiveModel::Model

    attr_accessor :email_account, :options
    attr_reader :errors, :metrics, :last_categorization_confidence, :last_categorization_method

    def initialize(email_account, options = {})
      @email_account = email_account
      @options = options
      @errors = []
      @metrics = {
        emails_found: 0,
        emails_processed: 0,
        expenses_created: 0,
        processing_time: 0
      }
      # Support dependency injection for categorization engine
      @categorization_engine = options[:categorization_engine] || Services::Categorization::Engine.create
    end

    # Main method to fetch and process new emails
    def process_new_emails(since: 1.week.ago, until_date: nil)
      return failure_response("Invalid email account") unless valid_account?

      start_time = Time.current

      begin
        # Fetch emails via IMAP
        emails = fetch_emails(since, until_date)
        @metrics[:emails_found] = emails.count

        # Process each email
        results = process_emails(emails)

        @metrics[:processing_time] = Time.current - start_time

        success_response(results)
      rescue StandardError => e
        handle_error(e)
        failure_response("Email processing failed: #{e.message}")
      end
    end

    # Fetch emails without processing (for preview/testing)
    def fetch_only(since: 1.week.ago, until_date: nil, limit: 100)
      return [] unless valid_account?

      @options[:limit] = limit
      fetch_emails(since, until_date)
    end

    # Parse a single email for expenses
    def parse_email(email_data)
      parser = EmailParser.new(email_data, email_account)
      parser.extract_expenses
    end

    # Test connection to email server
    def test_connection
      with_imap_connection do |imap|
        imap.examine("INBOX")
        { success: true, message: "Connection successful" }
      end
    rescue StandardError => e
      { success: false, message: e.message }
    end

    private

    def valid_account?
      return false unless email_account

      unless email_account.email?
        add_error("Email address is required")
        return false
      end

      if email_account.password.blank? && !email_account.oauth_configured?
        add_error("Password or OAuth configuration is required")
        return false
      end

      true
      end

    def fetch_emails(since, until_date = nil)
      emails = []

      with_imap_connection do |imap|
        imap.examine("INBOX")

        # Search for emails from known senders
        message_ids = search_for_transaction_emails(imap, since, until_date)

        return [] if message_ids.empty?

        # Fetch email data in batches
        message_ids.each_slice(20) do |batch|
          fetch_data = imap.fetch(batch, [ "RFC822", "UID", "FLAGS" ])

          fetch_data.each do |message|
            emails << parse_raw_email(message)
          end
        end
      end

      emails.compact
    end

    def process_emails(emails)
      results = {
        processed: 0,
        expenses_created: 0,
        errors: []
      }

      emails.each do |email|
        result = process_single_email(email)

        if result[:success]
          results[:processed] += 1
          results[:expenses_created] += result[:expenses_created]
        else
          results[:errors] << result[:error]
        end
      end

      @metrics[:emails_processed] = results[:processed]
      @metrics[:expenses_created] = results[:expenses_created]

      results
    end

    def process_single_email(email)
      Rails.logger.debug "[EmailProcessing] Processing: #{email[:subject]&.slice(0, 60)}"

      # Skip if already processed
      if email_already_processed?(email)
        Rails.logger.debug "[EmailProcessing] Already processed - skipping"
        return { success: true, expenses_created: 0 }
      end

      # Skip promotional emails
      if promotional_email?(email)
        Rails.logger.debug "[EmailProcessing] Promotional email - skipping"
        return { success: true, expenses_created: 0 }
      end

      # Parse email for expenses
      expenses_data = parse_email(email)
      Rails.logger.debug "[EmailProcessing] Found #{expenses_data.count} expense(s) in email"

      if expenses_data.empty?
        Rails.logger.debug "[EmailProcessing] No expenses found in email"
        return { success: true, expenses_created: 0 }
      end

      # Create expense records
      expenses_created = 0

      ApplicationRecord.transaction do
        expenses_data.each do |expense_data|
          Rails.logger.debug "[EmailProcessing] Creating expense: #{expense_data[:merchant]} - #{expense_data[:currency]}#{expense_data[:amount]}"
          expense = create_expense(expense_data)
          if expense.persisted?
            expenses_created += 1
            Rails.logger.info "[EmailProcessing] Created expense ##{expense.id}: #{expense.merchant_name} - #{expense.currency.upcase}#{expense.amount}"

            # Log categorization success if auto-categorized
            if options[:auto_categorize] && expense.auto_categorized?
              Rails.logger.info "[EmailProcessing] Auto-categorized expense ##{expense.id} " \
                               "as '#{expense.category&.name}' (#{expense.categorization_confidence}% confidence) " \
                               "using #{expense.categorization_method}"
            end
          else
            Rails.logger.error "[EmailProcessing] Failed to save expense: #{expense.errors.full_messages.join(', ')}"
          end
        end

        # Mark email as processed
        mark_email_processed(email)
      end

      { success: true, expenses_created: expenses_created }
    rescue StandardError => e
      Rails.logger.error "[EmailProcessing] Error processing email: #{e.message}"
      Rails.logger.error "[EmailProcessing] Error class: #{e.class.name}"
      Rails.logger.error "[EmailProcessing] Backtrace: #{e.backtrace.first(5).join(', ')}"
      { success: false, error: "Failed to process email: #{e.message}" }
    end

    def with_imap_connection(&block)
      imap = connect_to_imap

      begin
        authenticate_imap(imap)
        yield imap
      ensure
        begin
          imap.disconnect if imap && !imap.disconnected?
        rescue StandardError => e
          # Log but don't reraise disconnect errors
          Rails.logger.warn "Failed to disconnect IMAP connection: #{e.message}"
        end
      end
    end

    def connect_to_imap
      require "net/imap"

      imap_config = {
        address: email_account.imap_server || detect_imap_server,
        port: email_account.imap_port || 993,
        enable_ssl: true,
        open_timeout: 5,
        read_timeout: 60
      }

      Net::IMAP.new(
        imap_config[:address],
        port: imap_config[:port],
        ssl: imap_config[:enable_ssl]
      )
    rescue StandardError => e
      raise ConnectionError, "Failed to connect to IMAP server: #{e.message}"
    end

    def authenticate_imap(imap)
      if email_account.oauth_configured?
        authenticate_with_oauth(imap)
      else
        imap.login(email_account.email, email_account.password)
      end
    rescue StandardError => e
      raise AuthenticationError, "IMAP authentication failed: #{e.message}"
    end

    def authenticate_with_oauth(imap)
      # OAuth2 authentication for Gmail/Outlook
      access_token = refresh_oauth_token

      if email_account.email.include?("@gmail.com")
        imap.authenticate("XOAUTH2", email_account.email, access_token)
      else
        # Outlook/Office365 OAuth
        imap.authenticate("XOAUTH2", email_account.email, access_token)
      end
    end

    def refresh_oauth_token
      # Would integrate with OAuth provider to refresh token
      email_account.settings.dig("oauth", "access_token")
    end

    def detect_imap_server
      domain = email_account.email.split("@").last

      case domain
      when "gmail.com", "googlemail.com"
        "imap.gmail.com"
      when "outlook.com", "hotmail.com", "live.com"
        "outlook.office365.com"
      when "yahoo.com"
        "imap.mail.yahoo.com"
      when "icloud.com", "me.com", "mac.com"
        "imap.mail.me.com"
      else
        "imap.#{domain}"
      end
    end

    def search_for_transaction_emails(imap, since, until_date = nil)
      search_criteria = build_search_criteria(since, until_date)

      message_ids = []

      # Search with each criterion
      search_criteria.each do |criterion|
        begin
          ids = imap.search(criterion)
          message_ids.concat(ids)
        rescue StandardError => e
          Rails.logger.warn "Search failed for criterion: #{criterion} - #{e.message}"
        end
      end

      message_ids.uniq.sort.reverse.take(options[:limit] || 100)
    end

    def build_search_criteria(since, until_date = nil)
      since_filter = since.strftime("%d-%b-%Y")

      criteria = []
      base_date_criteria = [ "SINCE", since_filter ]

      # Add BEFORE filter if until_date is provided
      if until_date
        # IMAP BEFORE searches for messages with a date before the given date
        # To include messages ON the until_date, we use the day after
        before_filter = (until_date + 1.day).strftime("%d-%b-%Y")
        base_date_criteria << "BEFORE" << before_filter
      end

      # Add criteria for known bank/transaction senders
      known_senders.each do |sender|
        criteria << base_date_criteria + [ "FROM", sender ]
      end

      # Add criteria for transaction keywords
      transaction_keywords.each do |keyword|
        criteria << base_date_criteria + [ "SUBJECT", keyword ]
      end

      criteria
    end

    def known_senders
      # Could be configurable per account
      [
        "notificacion@notificacionesbaccr.com",
        "alertas@bncr.fi.cr",
        "notificaciones@scotiabank.com",
        "alerts@paypal.com",
        "no-reply@amazon.com"
      ]
    end

    def promotional_senders
      # Exclude promotional/marketing emails
      [
        "promociones@scotiabankca.net",
        "marketing@",
        "promociones@",
        "offers@",
        "newsletter@",
        "noticias@",
        "comunicaciones@"
      ]
    end

    def transaction_keywords
      [ "transaction", "payment", "purchase", "cargo", "compra", "pago", "retiro" ]
    end

    def parse_raw_email(message)
      return nil unless message.attr["RFC822"]

      mail = Mail.read_from_string(message.attr["RFC822"])

      # Extract text body - prefer actual text part, fallback to converting HTML to text
      text_content = if mail.text_part&.body
        mail.text_part.body.decoded
      elsif mail.html_part&.body
        # Convert HTML to plain text by stripping tags
        html = mail.html_part.body.decoded
        html.gsub(/<[^>]*>/, " ").gsub(/\s+/, " ").strip
      elsif !mail.multipart?
        mail.body.decoded
      else
        ""
      end

      {
        uid: message.attr["UID"],
        message_id: mail.message_id,
        from: mail.from&.first,
        subject: Services::Email::EncodingService.safe_decode(mail.subject),
        date: mail.date,
        body: extract_body(mail),
        html_body: Services::Email::EncodingService.safe_decode(mail.html_part&.body&.decoded),
        text_body: Services::Email::EncodingService.safe_decode(text_content)
      }
    rescue StandardError => e
      Rails.logger.error "Failed to parse email: #{e.message}"
      nil
    end

    def extract_body(mail)
      body = if mail.multipart?
        mail.text_part&.body&.decoded || mail.html_part&.body&.decoded
      else
        mail.body.decoded
      end

      Services::Email::EncodingService.safe_decode(body)
    end

    def email_already_processed?(email)
      ProcessedEmail.exists?(
        message_id: email[:message_id],
        email_account: email_account
      )
    end

    def create_expense(expense_data)
      expense = email_account.expenses.build(
        amount: expense_data[:amount],
        description: expense_data[:description],
        transaction_date: expense_data[:date] || Date.current,
        merchant_name: expense_data[:merchant],
        merchant_normalized: expense_data[:merchant]&.downcase&.strip,
        currency: expense_data[:currency]&.downcase || "usd",
        raw_email_content: expense_data[:raw_text],
        bank_name: email_account.bank_name,
        status: "pending"
      )

      # Save expense first
      expense.save!

      # Auto-categorize if enabled (after saving so expense has an ID)
      if options[:auto_categorize]
        category = suggest_category(expense)
        if category
          begin
            expense.reload.update!(
              category: category,
              auto_categorized: true,
              categorization_confidence: last_categorization_confidence,
              categorization_method: last_categorization_method,
              categorized_at: Time.current
            )
          rescue ActiveRecord::StaleObjectError
            # Expense was modified concurrently, skip auto-categorization
            Rails.logger.warn "Skipped auto-categorization for expense #{expense.id} due to concurrent modification"
          end
        end
      end

      expense
    end

    def suggest_category(expense)
      # Use the injected categorization engine
      result = @categorization_engine.categorize(expense)

      if result&.successful? && result.confidence > 0.7
        # Store categorization metadata for expense update
        @last_categorization_confidence = result.confidence
        @last_categorization_method = result.method || "engine"

        result.category
      else
        @last_categorization_confidence = result&.confidence || 0.0
        @last_categorization_method = "low_confidence"
        nil
      end
    rescue => e
      Rails.logger.warn "Categorization failed for expense: #{e.message}"
      @last_categorization_confidence = 0.0
      @last_categorization_method = "error"
      nil
    end

    def promotional_email?(email)
      from_address = email[:from]&.downcase
      return false unless from_address

      promotional_senders.any? { |sender| from_address.include?(sender.downcase) }
    end

    def mark_email_processed(email)
      ProcessedEmail.create!(
        message_id: email[:message_id],
        email_account: email_account,
        processed_at: Time.current,
        uid: email[:uid],
        subject: email[:subject],
        from_address: email[:from]
      )
    end

    def success_response(results)
      {
        success: true,
        metrics: @metrics,
        details: results
      }
    end

    def failure_response(message)
      {
        success: false,
        error: message,
        errors: @errors,
        metrics: @metrics
      }
    end

    def add_error(message)
      @errors << message
      Rails.logger.error "EmailProcessingService Error: #{message}"
    end

    def handle_error(error)
      add_error(error.message)

      # Report to error tracking service
      Services::Infrastructure::MonitoringService::ErrorTracker.report(error, context: {
        email_account_id: email_account.id,
        service: "EmailProcessingService"
      })
    end

    # Custom error classes
    class ConnectionError < StandardError; end
    class AuthenticationError < StandardError; end

    # Inner class for email parsing logic
    class EmailParser
      attr_reader :email_data, :email_account

      def initialize(email_data, email_account)
        @email_data = email_data
        @email_account = email_account
      end

      def extract_expenses
        expenses = []

        # Try bank-specific patterns first
        bank_expenses = parse_with_patterns
        if bank_expenses.any?
          expenses.concat(bank_expenses)
        else
          # Only use fallback methods if bank patterns don't work
          expenses.concat(parse_with_regex)
          expenses.concat(parse_structured_data)
        end

        # Remove duplicates and validate
        expenses.uniq { |e| [ e[:amount], e[:date], e[:description] ] }
                .select { |e| valid_expense?(e) }
      end

      private

      def parse_with_patterns
        # Use parsing rules specific to the bank
        Rails.logger.debug "[EmailProcessing] Looking for parsing rule for bank: #{email_account.bank_name}"
        rule = ParsingRule.find_by(
          bank_name: email_account.bank_name,
          active: true
        )

        if rule
          Rails.logger.debug "[EmailProcessing] Found parsing rule for #{rule.bank_name}"
          result = apply_parsing_rule(rule)
          Rails.logger.debug "[EmailProcessing] Parsing rule returned #{result.count} expense(s)"
          result
        else
          Rails.logger.debug "[EmailProcessing] No parsing rule found for #{email_account.bank_name}"
          []
        end
      end

      def parse_with_regex
        expenses = []
        text = email_data[:text_body] || email_data[:body] || ""

        # Ensure text is UTF-8 to avoid encoding issues with regex
        if text.respond_to?(:force_encoding)
          text = text.dup
          unless text.encoding == Encoding::UTF_8
            text = text.force_encoding("UTF-8")
            # If it's not valid UTF-8, try to clean it up
            unless text.valid_encoding?
              text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
            end
          end
        end

        # Transaction amount patterns
        patterns = [
          /(?:amount|total|cargo|monto|importe)[:.\s]+[₡\$]?([\d,]+\.?\d{0,2})/i,
          /(?:compra|purchase|payment|charge).*?[₡\$]?([\d,]+\.?\d{0,2})/i,
          /(?:processed\s+for|charged|debited)\s+[₡\$]?([\d,]+\.?\d{0,2})/i,  # "processed for $100.00"
          /[₡\$]\s?([\d,]+\.?\d{0,2})(?:\s+(?:at|en|from|was|processed))/i,  # Currency followed by amount and context
          /[₡\$]([\d,]+\.?\d{0,2})(?!\d)/i  # Simple currency + amount not followed by digits
        ]

        # Track found amounts to avoid duplicates
        found_amounts = Set.new

        patterns.each do |pattern|
          text.scan(pattern) do |match|
            amount_text = match[0]
            # Skip if the amount text contains negative indicators
            next if amount_text.to_s =~ /^[-−]/  # Matches dash or minus sign at start

            # Skip if this looks like an authorization/reference number (6+ digits without decimals)
            next if amount_text =~ /^\d{6,}$/ && !amount_text.include?(".")

            # Skip if the surrounding context suggests this is not a transaction amount
            amount_index = text.index(amount_text)
            if amount_index
              # Look at broader context around the amount
              context_start = [ amount_index - 50, 0 ].max
              context_end = [ amount_index + amount_text.length + 50, text.length ].min
              context = text[context_start...context_end]

              # Skip if this is likely a reference number or authorization code
              next if context&.match?(/(?:autorizaci[oó]n|authorization|reference|ref|código|code|número|number|tarjeta.*\*{4}|card.*\*{4})/i)
              # Skip refunds
              next if context&.match?(/refund|reembolso|devoluci[oó]n|-[₡\$][\d,]+|fee.*\$0\.00/i)
            end

            amount = parse_amount(amount_text)
            next unless amount > 0

            # Skip if we've already found this amount (avoid duplicates)
            amount_key = amount.to_f.round(2)
            next if found_amounts.include?(amount_key)
            found_amounts.add(amount_key)

            # Detect currency from context
            currency = detect_currency_from_text(text, amount_index)

            expenses << {
              amount: amount,
              description: extract_description_near_amount(text, amount_text),
              date: extract_date(text),
              merchant: extract_merchant(text),
              currency: currency,
              raw_text: text[0...500],
              email_message_id: email_data[:message_id]
            }
          end
        end

        # Return all valid expenses found
        expenses
      end

      def detect_currency_from_text(text, amount_index = nil)
        # Check around the amount for currency indicators
        if amount_index
          context_start = [ amount_index - 30, 0 ].max
          context_end = [ amount_index + 30, text.length ].min
          context = text[context_start...context_end]

          return "crc" if context =~ /₡|colones|CRC/i
          return "usd" if context =~ /\$|USD|dollars?/i
          return "eur" if context =~ /€|EUR|euros?/i
        end

        # Check the entire text as fallback
        return "crc" if text =~ /₡|colones|CRC/i
        return "usd" if text =~ /\$|USD|dollars?/i
        return "eur" if text =~ /€|EUR|euros?/i

        # Default based on email account bank
        case email_account.bank_name
        when "BAC", "BCR", "Banco Nacional"
          "crc"
        else
          "usd"
        end
      end

      def parse_structured_data
        # Look for structured data in HTML emails
        return [] unless email_data[:html_body]

        # This would use Nokogiri or similar to parse HTML tables/structured data
        []
      end

      def apply_parsing_rule(rule)
        # Prioritize text_body over html_body for better pattern matching
        text = email_data[:text_body] || email_data[:html_body] || email_data[:body] || ""
        # Fix encoding issues - make a copy to avoid modifying frozen strings
        if text.respond_to?(:force_encoding)
          text = text.dup
          unless text.encoding == Encoding::UTF_8
            text = text.force_encoding("UTF-8")
            # If it's not valid UTF-8, try to clean it up
            unless text.valid_encoding?
              text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
            end
          end
        end
        parsed_data = rule.parse_email(text)

        return [] if parsed_data.empty? || !parsed_data[:amount]

        [ {
          amount: parsed_data[:amount],
          description: parsed_data[:description] || extract_description_near_amount(text, parsed_data[:amount].to_s),
          date: parsed_data[:transaction_date] || extract_date(text),
          merchant: parsed_data[:merchant_name] || extract_merchant(text),
          currency: parsed_data[:currency],  # Pass the detected currency
          raw_text: text[0...500],
          email_message_id: email_data[:message_id]
        } ]
      end

      def parse_amount(text)
        # Remove currency symbols and convert commas to dots for decimal parsing
        cleaned = text.to_s.gsub(/[₡\$,\s]/, "").gsub(",", ".")
        cleaned.to_f
      end

      def extract_description_near_amount(text, amount_text)
        # Find context around the amount
        index = text.index(amount_text)
        return "Transaction" unless index

        start_pos = [ index - 100, 0 ].max
        end_pos = [ index + 100, text.length ].min

        context = text[start_pos..end_pos]

        # Clean up and extract meaningful description
        context.gsub(/\s+/, " ")
               .strip
               .truncate(200)
      end

      def extract_date(text)
        # Try to find date patterns
        date_patterns = [
          /(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/,
          /(\d{4}[\/\-]\d{1,2}[\/\-]\d{1,2})/,
          /((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4})/i,
          /(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{4})/i
        ]

        date_patterns.each do |pattern|
          if match = text.match(pattern)
            begin
              return Date.parse(match[0])
            rescue
              next
            end
          end
        end

        # Default to email date or current date
        email_data[:date]&.to_date || Date.current
      end

      def extract_merchant(text)
        # Extract merchant name from common patterns
        merchant_patterns = [
          /(?:merchant|comercio|establecimiento)[:.\s]+([^,\n]+?)(?:\s+Amount|$)/i,
          /(?:at|en)\s+([A-Z][A-Za-z\s&]+?)(?:\s+on|\s+el|\s+Amount)/i,
          /^([A-Z][A-Za-z\s&]+?)(?:\s+charge|\s+Amount)/i
        ]

        merchant_patterns.each do |pattern|
          if match = text.match(pattern)
            merchant_name = match[1].strip
            # Clean up the merchant name - remove trailing words like "Amount"
            merchant_name = merchant_name.gsub(/\s+Amount.*$/i, "")
            return merchant_name.titleize
          end
        end

        nil
      end

      def valid_expense?(expense)
        expense[:amount] &&
        expense[:amount] > 0 &&
        expense[:amount] < 1_000_000 &&
        expense[:date].is_a?(Date)
      end
    end
  end
end
