class EmailProcessor
  attr_reader :email_account, :errors

  def initialize(email_account)
    @email_account = email_account
    @errors = []
  end

  def process_emails(message_ids, imap_service)
    return { processed_count: 0, total_count: 0 } if message_ids.empty?

    processed_count = 0
    total_count = message_ids.length

    message_ids.each do |message_id|
      if process_single_email(message_id, imap_service)
        processed_count += 1
      end
    end

    Rails.logger.info "Processed #{processed_count} transaction emails out of #{total_count} total emails"
    {
      processed_count: processed_count,
      total_count: total_count
    }
  end

  private

  def process_single_email(message_id, imap_service)
    envelope = imap_service.fetch_envelope(message_id)
    return false unless envelope

    subject = envelope.subject || ""

    # Check if this is a transaction email based on subject
    unless transaction_email?(subject)
      Rails.logger.debug "Skipping non-transaction email: #{subject}"
      return false
    end

    Rails.logger.info "Processing transaction email: #{subject}"

    # Extract email content and queue for processing
    email_data = extract_email_data(message_id, envelope, imap_service)
    return false unless email_data

    # Queue job to parse and create expense
    ProcessEmailJob.perform_later(email_account.id, email_data)
    true

  rescue StandardError => e
    Rails.logger.error "Error processing email #{message_id}: #{e.message}"
    add_error("Error processing email: #{e.message}")
    false
  end

  def transaction_email?(subject)
    return false if subject.nil?

    # Check for BAC transaction email patterns
    transaction_keywords = [ "transacci", "Notificaci" ]
    transaction_keywords.any? { |keyword| subject.include?(keyword) }
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
      text = text.force_encoding("BINARY") if text.encoding.name == "ASCII-8BIT"

      # Remove quoted-printable encoding first
      text = text.gsub(/=\r?\n/, "")
      text = text.gsub(/=([0-9A-F]{2})/) { [ $1 ].pack("H*") }

      # Now convert to UTF-8
      text = text.force_encoding("UTF-8")

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

  def add_error(message)
    @errors << message
    Rails.logger.error "[EmailProcessor] #{email_account.email}: #{message}"
  end
end