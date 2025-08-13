# frozen_string_literal: true

module Services
  module Email
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
        @categorization_engine = options[:categorization_engine] || Categorization::Engine.create
      end

      # Main method to fetch and process new emails
      def process_new_emails(since: 1.week.ago)
        return failure_response("Invalid email account") unless valid_account?

        start_time = Time.current

        begin
          # Fetch emails via IMAP
          emails = fetch_emails(since)
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
      def fetch_only(since: 1.week.ago, limit: 100)
        return [] unless valid_account?

        @options[:limit] = limit
        fetch_emails(since)
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

      def fetch_emails(since)
        emails = []

        with_imap_connection do |imap|
          imap.examine("INBOX")

          # Search for emails from known senders
          message_ids = search_for_transaction_emails(imap, since)

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
        # Skip if already processed
        return { success: true, expenses_created: 0 } if email_already_processed?(email)

        # Skip promotional emails
        return { success: true, expenses_created: 0 } if promotional_email?(email)

        # Parse email for expenses
        expenses_data = parse_email(email)

        return { success: true, expenses_created: 0 } if expenses_data.empty?

        # Create expense records
        expenses_created = 0

        ApplicationRecord.transaction do
          expenses_data.each do |expense_data|
            expense = create_expense(expense_data)
            if expense.persisted?
              expenses_created += 1

              # Log categorization success if auto-categorized
              if options[:auto_categorize] && expense.auto_categorized?
                Rails.logger.info "[EmailProcessing] Auto-categorized expense #{expense.id} " \
                                 "as '#{expense.category&.name}' with #{expense.categorization_confidence} confidence " \
                                 "using #{expense.categorization_method}"
              end
            else
              Rails.logger.warn "[EmailProcessing] Failed to save expense: #{expense.errors.full_messages.join(', ')}"
            end
          end

          # Mark email as processed
          mark_email_processed(email)
        end

        { success: true, expenses_created: expenses_created }
      rescue StandardError => e
        { success: false, error: "Failed to process email: #{e.message}" }
      end

      def with_imap_connection(&block)
        imap = connect_to_imap

        begin
          authenticate_imap(imap)
          yield imap
        ensure
          imap.disconnect if imap && !imap.disconnected?
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
        email_account.oauth_access_token
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

      def search_for_transaction_emails(imap, since)
        search_criteria = build_search_criteria(since)

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

      def build_search_criteria(since)
        date_filter = since.strftime("%d-%b-%Y")

        criteria = []

        # Add criteria for known bank/transaction senders
        known_senders.each do |sender|
          criteria << [ "SINCE", date_filter, "FROM", sender ]
        end

        # Add criteria for transaction keywords
        transaction_keywords.each do |keyword|
          criteria << [ "SINCE", date_filter, "SUBJECT", keyword ]
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

        {
          uid: message.attr["UID"],
          message_id: mail.message_id,
          from: mail.from&.first,
          subject: mail.subject,
          date: mail.date,
          body: extract_body(mail),
          html_body: mail.html_part&.body&.decoded,
          text_body: mail.text_part&.body&.decoded || mail.body&.decoded
        }
      rescue StandardError => e
        Rails.logger.error "Failed to parse email: #{e.message}"
        nil
      end

      def extract_body(mail)
        if mail.multipart?
          mail.text_part&.body&.decoded || mail.html_part&.body&.decoded
        else
          mail.body.decoded
        end
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
          status: "pending"
        )

        # Save expense first
        expense.save!

        # Auto-categorize if enabled (after saving so expense has an ID)
        if options[:auto_categorize]
          category = suggest_category(expense)
          if category
            expense.update!(
              category: category,
              auto_categorized: true,
              categorization_confidence: last_categorization_confidence,
              categorization_method: last_categorization_method,
              categorized_at: Time.current
            )
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
        ::Services::Infrastructure::MonitoringService::ErrorTracker.report(error, context: {
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
          rule = ParsingRule.find_by(
            bank_name: email_account.bank_name,
            active: true
          )

          return [] unless rule

          apply_parsing_rule(rule)
        end

        def parse_with_regex
          expenses = []
          text = email_data[:text_body] || email_data[:body] || ""

          # Common transaction patterns
          patterns = [
            /(?:amount|total|cargo)[:.\s]+\$?([\d,]+\.?\d*)/i,
            /(?:compra|purchase|payment).*?\$?([\d,]+\.?\d*)/i,
            /\$\s?([\d,]+\.?\d*)/
          ]

          patterns.each do |pattern|
            text.scan(pattern) do |match|
              amount = parse_amount(match[0])
              next unless amount > 0

              expenses << {
                amount: amount,
                description: extract_description_near_amount(text, match[0]),
                date: extract_date(text),
                merchant: extract_merchant(text),
                raw_text: text[0..500],
                email_message_id: email_data[:message_id]
              }
            end
          end

          expenses
        end

        def parse_structured_data
          # Look for structured data in HTML emails
          return [] unless email_data[:html_body]

          # This would use Nokogiri or similar to parse HTML tables/structured data
          []
        end

        def apply_parsing_rule(rule)
          text = email_data[:html_body] || email_data[:text_body] || email_data[:body] || ""
          # Fix encoding issues
          text = text.force_encoding("UTF-8") if text.respond_to?(:force_encoding)
          parsed_data = rule.parse_email(text)

          return [] if parsed_data.empty? || !parsed_data[:amount]

          [ {
            amount: parsed_data[:amount],
            description: parsed_data[:description] || extract_description_near_amount(text, parsed_data[:amount].to_s),
            date: parsed_data[:transaction_date] || extract_date(text),
            merchant: parsed_data[:merchant_name] || extract_merchant(text),
            raw_text: text[0..500],
            email_message_id: email_data[:message_id]
          } ]
        end

        def parse_amount(text)
          text.to_s.gsub(/[^\d.]/, "").to_f
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
            /(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},?\s+\d{4}/i
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
            /(?:merchant|comercio|establecimiento)[:.\s]+([^,\n]+)/i,
            /(?:at|en)\s+([A-Z][A-Za-z\s&]+?)(?:\s+on|\s+el)/,
            /^([A-Z][A-Z\s&]+?)\s+/
          ]

          merchant_patterns.each do |pattern|
            if match = text.match(pattern)
              return match[1].strip.titleize
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
end
