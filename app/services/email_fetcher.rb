class EmailFetcher
  attr_reader :email_account, :errors

  def initialize(email_account)
    @email_account = email_account
    @errors = []
  end

  def fetch_new_emails(since: 1.week.ago)
    return false unless valid_account?

    begin
      connect_to_imap do |imap|
        search_and_process_emails(imap, since)
      end
    rescue Net::IMAP::Error => e
      add_error("IMAP Error: #{e.message}")
      false
    rescue StandardError => e
      add_error("Unexpected error: #{e.message}")
      false
    end
  end

  def test_connection
    begin
      connect_to_imap do |imap|
        imap.list("", "*").present?
      end
    rescue Net::IMAP::Error => e
      add_error("Connection failed: #{e.message}")
      false
    rescue StandardError => e
      add_error("Unexpected error: #{e.message}")
      false
    end
  end

  private

  def valid_account?
    unless email_account.active?
      add_error("Email account is not active")
      return false
    end

    unless email_account.encrypted_password.present?
      add_error("Email account missing password")
      return false
    end

    true
  end

  def connect_to_imap
    imap_settings = email_account.imap_settings

    imap = Net::IMAP.new(
      imap_settings[:address],
      port: imap_settings[:port],
      ssl: imap_settings[:enable_ssl]
    )

    imap.login(imap_settings[:user_name], imap_settings[:password])
    imap.select("INBOX")

    result = yield(imap)

    imap.logout
    imap.disconnect

    result
  end

  def search_and_process_emails(imap, since)
    # Search for emails from bank domains or with expense-related keywords
    search_criteria = build_search_criteria(since)

    message_ids = imap.search(search_criteria)

    if message_ids.empty?
      Rails.logger.info "No new emails found for #{email_account.email}"
      return true
    end

    Rails.logger.info "Found #{message_ids.length} emails for #{email_account.email}"

    # Filter emails to find BAC transaction notifications
    bac_emails = 0
    message_ids.each do |message_id|
      envelope = imap.fetch(message_id, "ENVELOPE")[0].attr["ENVELOPE"]
      subject = envelope.subject || ""

      # Check if this is a BAC transaction email
      if subject.include?("transacci") || subject.include?("Notificaci")
        Rails.logger.info "Processing BAC email: #{subject}"
        process_email_message(imap, message_id)
        bac_emails += 1
      end
    end

    Rails.logger.info "Processed #{bac_emails} BAC transaction emails"
    true
  end

  def build_search_criteria(since)
    # Simple search for recent emails - we'll filter by content later
    [ "SINCE", since.strftime("%d-%b-%Y") ]
  end

  def process_email_message(imap, message_id)
    envelope = imap.fetch(message_id, "ENVELOPE")[0].attr["ENVELOPE"]

    # Extract email content from multipart structure
    body_data = nil

    begin
      body_structure = imap.fetch(message_id, "BODYSTRUCTURE")[0].attr["BODYSTRUCTURE"]

      if body_structure.multipart?
        # Look for text/plain first, then HTML
        text_part = find_text_part(body_structure)
        if text_part
          body_data = imap.fetch(message_id, "BODY[#{text_part}]")[0].attr["BODY[#{text_part}]"]
        else
          # No plain text, look for HTML part
          html_part = find_html_part(body_structure)
          if html_part
            html_content = imap.fetch(message_id, "BODY[#{html_part}]")[0].attr["BODY[#{html_part}]"]
            body_data = extract_text_from_html(html_content)
          end
        end
      end

      # Fallback to basic text fetch if multipart parsing fails
      body_data ||= imap.fetch(message_id, "BODY[TEXT]")[0].attr["BODY[TEXT]"]

    rescue StandardError => fetch_error
      Rails.logger.warn "Error fetching email body: #{fetch_error.message}"
      # Try HTML part as last resort
      begin
        html_content = imap.fetch(message_id, "BODY[1]")[0].attr["BODY[1]"]
        body_data = extract_text_from_html(html_content)
      rescue
        body_data = "Failed to fetch email content"
      end
    end

    email_data = {
      message_id: message_id,
      from: envelope.from&.first&.mailbox + "@" + envelope.from&.first&.host,
      subject: envelope.subject,
      date: envelope.date,
      body: body_data
    }

    # Queue job to parse and create expense
    ProcessEmailJob.perform_later(email_account.id, email_data)

  rescue StandardError => e
    Rails.logger.error "Error processing email #{message_id}: #{e.message}"
    add_error("Error processing email: #{e.message}")
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

  def add_error(message)
    @errors << message
    Rails.logger.error "[EmailFetcher] #{email_account.email}: #{message}"
  end
end
