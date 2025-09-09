module EmailProcessing
  class Processor
    attr_reader :email_account, :errors, :metrics_collector

    def initialize(email_account, metrics_collector: nil)
      @email_account = email_account
      @metrics_collector = metrics_collector
      @errors = []
    end

    def process_emails(message_ids, imap_service, &progress_callback)
      return { processed_count: 0, total_count: 0, detected_expenses_count: 0 } if message_ids.empty?

      processed_count = 0
      detected_expenses_count = 0
      total_count = message_ids.length

      message_ids.each_with_index do |message_id, index|
        result = process_single_email(message_id, imap_service)
        if result[:processed]
          processed_count += 1
          detected_expenses_count += 1 if result[:expense_created]
        end

        # Call progress callback if provided
        if progress_callback
          progress_callback.call(index + 1, detected_expenses_count)
        end
      end

      Rails.logger.info "Processed #{processed_count} transaction emails out of #{total_count} total emails"
      {
        processed_count: processed_count,
        total_count: total_count,
        detected_expenses_count: detected_expenses_count
      }
    end

    private

    def process_single_email(message_id, imap_service)
      if @metrics_collector
        begin
          result = @metrics_collector.track_operation(:parse_email, @email_account, { message_id: message_id }) do
            process_email_with_metrics(message_id, imap_service)
          end
          # Handle nil return from metrics collector
          result || { processed: false, expense_created: false }
        rescue StandardError => e
          # Log metrics errors but continue processing
          Rails.logger.error "[EmailProcessing::Processor] Metrics tracking error: #{e.message}"
          # Still process the email even if metrics fail
          process_email_with_metrics(message_id, imap_service)
        end
      else
        process_email_with_metrics(message_id, imap_service)
      end
    end

    def process_email_with_metrics(message_id, imap_service)
      envelope = imap_service.fetch_envelope(message_id)
      return { processed: false, expense_created: false } unless envelope

      subject = envelope.subject || ""

      # Check if this is a transaction email based on subject
      unless transaction_email?(subject)
        Rails.logger.info "[SKIP] Non-transaction email: #{subject}"
        return { processed: false, expense_created: false }
      end

      Rails.logger.info "[PROCESS] Transaction email detected: #{subject}"

      # Extract email content and queue for processing
      email_data = extract_email_data(message_id, envelope, imap_service)
      return { processed: false, expense_created: false } unless email_data

      # Check for conflicts before creating expense
      if detect_and_handle_conflict(email_data)
        { processed: true, expense_created: false, conflict_detected: true }
      else
        # Queue job to parse and create expense
        ProcessEmailJob.perform_later(email_account.id, email_data)

        # For now, we assume transaction emails will create expenses
        # In a real implementation, we'd track this through the job
        { processed: true, expense_created: true }
      end

    rescue StandardError => e
      Rails.logger.error "Error processing email #{message_id}: #{e.message}"
      add_error("Error processing email: #{e.message}")
      { processed: false, expense_created: false }
    end

    def transaction_email?(subject)
      return false if subject.nil?

      # Check for transaction notification emails
      # Primary pattern: "Notificación de transacción"
      if subject.downcase.include?("notificación de transacción")
        return true
      end

      # Fallback patterns for other banks or variations
      transaction_keywords = [ "transacción", "notificación de compra", "cargo a su cuenta" ]
      transaction_keywords.any? { |keyword| subject.downcase.include?(keyword.downcase) }
    end

    def extract_email_data(message_id, envelope, imap_service)
      # Extract email content from multipart structure
      body_data = extract_email_body(message_id, imap_service)
      return nil unless body_data

      {
        message_id: message_id,
        from: build_from_address(envelope),
        subject: envelope.subject,
        date: envelope.date,
        body: body_data
      }
    end

    def extract_email_body(message_id, imap_service)
      body_structure = imap_service.fetch_body_structure(message_id)

      if body_structure&.multipart?
        extract_multipart_body(message_id, body_structure, imap_service)
      else
        # Fallback to basic text fetch
        imap_service.fetch_text_body(message_id)
      end

    rescue StandardError => e
      Rails.logger.warn "Error extracting email body: #{e.message}"
      # Try HTML part as last resort
      begin
        html_content = imap_service.fetch_body_part(message_id, "1")
        html_content ? extract_text_from_html(html_content) : "Failed to fetch email content"
      rescue
        "Failed to fetch email content"
      end
    end

    def extract_multipart_body(message_id, body_structure, imap_service)
      # Look for text/plain first, then HTML
      text_part = find_text_part(body_structure)
      if text_part
        return imap_service.fetch_body_part(message_id, text_part)
      end

      # No plain text, look for HTML part
      html_part = find_html_part(body_structure)
      if html_part
        html_content = imap_service.fetch_body_part(message_id, html_part)
        return extract_text_from_html(html_content) if html_content
      end

      # Fallback to basic text fetch
      imap_service.fetch_text_body(message_id)
    end

    def find_text_part(body_structure)
      # Simple approach: look for first text/plain part
      if body_structure.media_type == "TEXT" && body_structure.subtype == "PLAIN"
        return "1"
      elsif body_structure.multipart?
        body_structure.parts.each_with_index do |part, index|
          if part.media_type == "TEXT" && part.subtype == "PLAIN"
            return (index + 1).to_s
          end
        end
      end
      nil
    end

    def find_html_part(body_structure)
      # Look for text/html part
      if body_structure.media_type == "TEXT" && body_structure.subtype == "HTML"
        return "1"
      elsif body_structure.multipart?
        body_structure.parts.each_with_index do |part, index|
          if part.media_type == "TEXT" && part.subtype == "HTML"
            return (index + 1).to_s
          end
        end
      end
      nil
    end

    def extract_text_from_html(html_content)
      begin
        # Handle encoding properly
        text = html_content.dup

        # Convert to UTF-8 if not already, handling various encodings
        unless text.encoding == Encoding::UTF_8
          # Try to convert to UTF-8 from the current encoding
          begin
            text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
          rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
            # Force to binary then to UTF-8 with replacement
            text = text.force_encoding("BINARY").encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
          end
        end

        # Remove quoted-printable encoding first
        text = text.gsub(/=\r?\n/, "")
        text = text.gsub(/=([0-9A-F]{2})/i) { [ $1 ].pack("H*") }

        # Ensure text is valid UTF-8 after quoted-printable decode
        text = text.force_encoding("UTF-8").scrub("?")

        # Remove HTML tags but preserve important content
        text = text.gsub(/<style[^>]*>.*?<\/style>/mi, "")
        text = text.gsub(/<script[^>]*>.*?<\/script>/mi, "")
        text = text.gsub(/<[^>]+>/, " ")

        # Decode HTML entities (comprehensive list for Spanish)
        text = text.gsub(/&nbsp;/, " ")
        text = text.gsub(/&amp;/, "&")
        text = text.gsub(/&lt;/, "<")
        text = text.gsub(/&gt;/, ">")
        text = text.gsub(/&quot;/, '"')
        text = text.gsub(/&#39;/, "'")
        text = text.gsub(/&aacute;/, "á")
        text = text.gsub(/&eacute;/, "é")
        text = text.gsub(/&iacute;/, "í")
        text = text.gsub(/&oacute;/, "ó")
        text = text.gsub(/&uacute;/, "ú")
        text = text.gsub(/&ntilde;/, "ñ")
        text = text.gsub(/&Aacute;/, "Á")
        text = text.gsub(/&Eacute;/, "É")
        text = text.gsub(/&Iacute;/, "Í")
        text = text.gsub(/&Oacute;/, "Ó")
        text = text.gsub(/&Uacute;/, "Ú")
        text = text.gsub(/&Ntilde;/, "Ñ")
        text = text.gsub(/&iexcl;/, "¡")
        text = text.gsub(/&iquest;/, "¿")

        # Decode numeric HTML entities (decimal)
        text = text.gsub(/&#(\d+);/) { [ $1.to_i ].pack("U*") }

        # Decode numeric HTML entities (hexadecimal)
        text = text.gsub(/&#x([0-9A-Fa-f]+);/) { [ $1.to_i(16) ].pack("U*") }

        # Normalize whitespace
        text = text.gsub(/\s+/, " ").strip

        text
      rescue Encoding::CompatibilityError, Encoding::UndefinedConversionError => e
        # Fallback: just remove HTML tags without decoding entities
        Rails.logger.warn "HTML encoding error: #{e.message}"
        simple_text = html_content.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
        simple_text.force_encoding("UTF-8")
      end
    end

    def build_from_address(envelope)
      return "unknown@unknown.com" unless envelope.from&.first

      from_addr = envelope.from.first
      "#{from_addr.mailbox}@#{from_addr.host}"
    end

    def detect_and_handle_conflict(email_data)
      # Parse expense data from email to extract fields without creating expense
      parsing_rule = ParsingRule.active.for_bank(email_account.bank_name).first
      return false unless parsing_rule

      begin
        parsing_strategy = EmailProcessing::StrategyFactory.create_strategy(parsing_rule, email_content: email_data[:body])
        expense_data = parsing_strategy.parse_email(email_data[:body])
      rescue => e
        Rails.logger.error "[EmailProcessing::Processor] Error parsing email: #{e.message}"
        return false
      end

      return false unless expense_data && expense_data[:amount].present?

      # Add additional fields
      expense_data[:email_account_id] = email_account.id
      expense_data[:raw_email_content] = email_data[:body]
      expense_data[:transaction_date] ||= email_data[:date]

      # Get current sync session (if any)
      sync_session = SyncSession.active.last

      if sync_session
        # Use conflict detection service with metrics tracking
        detector = ConflictDetectionService.new(sync_session, metrics_collector: @metrics_collector)
        conflict = detector.detect_conflict_for_expense(expense_data)

        return true if conflict # Conflict detected and handled
      end

      false # No conflict detected
    rescue => e
      Rails.logger.error "[EmailProcessing::Processor] Error detecting conflict: #{e.message}"
      false # Continue with normal processing on error
    end

    def add_error(message)
      @errors << message
      Rails.logger.error "[EmailProcessing::Processor] #{email_account.email}: #{message}"
    end
  end
end
