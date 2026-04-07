module Services::EmailProcessing
  class Processor
    attr_reader :email_account, :errors, :metrics_collector

    def initialize(email_account, metrics_collector: nil, sync_session: nil)
      @email_account = email_account
      @metrics_collector = metrics_collector
      @sync_session = sync_session
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
          detected_expenses_count += 1 if result[:expense_enqueued]
        end

        # Call progress callback if provided
        if progress_callback
          expense_data = result[:expense_enqueued] ? result[:expense_data] : nil
          progress_callback.call(index + 1, detected_expenses_count, expense_data)
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
          Rails.logger.error "[Services::EmailProcessing::Processor] Metrics tracking error: #{e.message}"
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
      conflict_result = detect_and_handle_conflict(email_data)

      if conflict_result.nil?
        # Conflict detected
        { processed: true, expense_created: false, conflict_detected: true }
      else
        # No conflict — pass pre-parsed data if available
        pre_parsed = if conflict_result.is_a?(Hash)
          # Convert BigDecimal amount to String before ActiveJob serialization
          # to avoid Float rounding on financial values
          conflict_result.merge(amount: conflict_result[:amount]&.to_s)
        end
        ProcessEmailJob.perform_later(email_account.id, email_data, @sync_session&.id, pre_parsed)

        {
          processed: true,
          expense_created: false,
          expense_enqueued: true,
          expense_data: email_data.slice(:subject).merge(
            merchant_name: email_data[:body]&.match(/(?:Comercio|comercio|merchant|establecimiento)[\s:]+([^\n\r]+)/i)&.captures&.first&.strip
          )
        }
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
      return "" if html_content.nil? || html_content.empty?

      begin
        # Decode quoted-printable transport encoding before HTML parsing.
        # Nokogiri parses HTML structure but does not handle QP soft line breaks
        # (=\r\n) or QP-encoded byte sequences (=XX) — those must be stripped first.
        decoded = decode_quoted_printable(html_content)

        # Strip C0 control characters (except tab, LF, CR) before handing to
        # Nokogiri. Null bytes (\x00) and other low-value control characters
        # cause libxml2 to abort parsing and return an empty document.
        decoded = decoded.gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")

        # Nokogiri handles tag removal, entity decoding (named + numeric, including
        # all Spanish accented characters), and malformed/partial HTML gracefully.
        doc = Nokogiri::HTML(decoded)

        # Remove nodes that would otherwise leak raw CSS/JS text into the output.
        doc.xpath("//style | //script | //noscript").each(&:remove)

        # Insert a space before block-level elements so adjacent text from
        # separate blocks does not run together when #text collapses the tree.
        doc.xpath("//*[self::p or self::h1 or self::h2 or self::h3 or self::h4 or
                        self::h5 or self::h6 or self::div or self::li or self::td or
                        self::th or self::br]").each do |node|
          node.prepend_child(Nokogiri::XML::Text.new(" ", doc))
        end

        text = doc.text

        # Normalize whitespace to a single space and strip leading/trailing space.
        text.gsub(/\s+/, " ").strip
      rescue Encoding::CompatibilityError, Encoding::UndefinedConversionError => e
        # Fallback: strip tags without entity decoding when Nokogiri cannot parse
        # due to an irrecoverable encoding conflict.
        # Force binary encoding before regex to avoid a second Encoding::CompatibilityError
        # from gsub when html_content itself has an incompatible encoding.
        Rails.logger.warn "[EmailProcessing] Encoding error in HTML extraction: #{e.message}"
        simple_text = html_content.dup
          .force_encoding("BINARY")
          .gsub(/<[^>]+>/, " ")
          .gsub(/\s+/, " ")
          .strip
          .force_encoding("UTF-8")
          .scrub("?")
      end
    end

    # Decodes quoted-printable transport encoding and ensures UTF-8 output.
    # QP is a MIME encoding used by many email servers (especially for HTML parts):
    #   - Soft line breaks: "=\r\n" or "=\n" are transport artefacts and must be removed.
    #   - Encoded bytes:    "=XX" (two hex digits) represent a single raw byte.
    def decode_quoted_printable(content)
      text = content.dup

      unless text.encoding == Encoding::UTF_8
        begin
          text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
          text = text.force_encoding("BINARY").encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
        end
      end

      # Remove soft line breaks inserted by QP encoding.
      text = text.gsub(/=\r?\n/, "")

      # Decode QP byte sequences ("=XX") back to their raw byte values.
      text = text.gsub(/=([0-9A-F]{2})/i) { [ $1 ].pack("H*") }

      # Scrub any invalid byte sequences introduced during QP decoding.
      text.force_encoding("UTF-8").scrub("?")
    end

    def build_from_address(envelope)
      return "unknown@unknown.com" unless envelope.from&.first

      from_addr = envelope.from.first
      "#{from_addr.mailbox}@#{from_addr.host}"
    end

    # Returns:
    #   nil        — conflict detected, processing should stop
    #   Hash       — no conflict, pre-parsed expense data for reuse
    #   false      — parsing failed or no rule, continue without pre-parsed data
    def detect_and_handle_conflict(email_data)
      # Parse expense data from email to extract fields without creating expense
      parsing_rule = ParsingRule.active.for_bank(email_account.bank_name).first
      return false unless parsing_rule

      begin
        parsing_strategy = Services::EmailProcessing::StrategyFactory.create_strategy(parsing_rule, email_content: email_data[:body])
        expense_data = parsing_strategy.parse_email(email_data[:body])
      rescue => e
        Rails.logger.error "[Services::EmailProcessing::Processor] Error parsing email: #{e.message}"
        return false
      end

      return false unless expense_data && expense_data[:amount].present?

      # Add additional fields
      expense_data[:email_account_id] = email_account.id
      expense_data[:raw_email_content] = email_data[:body]
      expense_data[:transaction_date] ||= email_data[:date]

      # Use the explicitly threaded sync session (avoids global lookup race condition)
      sync_session = @sync_session

      if sync_session
        # Use conflict detection service with metrics tracking
        detector = Services::ConflictDetectionService.new(sync_session, metrics_collector: @metrics_collector)
        conflict = detector.detect_conflict_for_expense(expense_data)

        return nil if conflict # Conflict detected — stop processing
      end

      expense_data # No conflict — return parsed data for reuse
    rescue => e
      Rails.logger.error "[Services::EmailProcessing::Processor] Error detecting conflict: #{e.message}"
      false # Continue with normal processing on error
    end

    def add_error(message)
      @errors << message
      Rails.logger.error "[Services::EmailProcessing::Processor] #{email_account.email}: #{message}"
    end
  end
end
