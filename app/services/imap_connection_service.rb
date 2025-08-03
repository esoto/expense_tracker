class ImapConnectionService
  class ConnectionError < StandardError; end
  class AuthenticationError < StandardError; end
  class SearchError < StandardError; end

  attr_reader :email_account, :errors

  def initialize(email_account)
    @email_account = email_account
    @errors = []
  end

  def test_connection
    with_connection do |imap|
      imap.list("", "*").present?
    end
  rescue Net::IMAP::Error => e
    add_error("Connection failed: #{e.message}")
    false
  end

  def search_emails(criteria)
    with_connection do |imap|
      imap.search(criteria)
    end
  rescue Net::IMAP::Error => e
    add_error("Search failed: #{e.message}")
    []
  end

  def fetch_envelope(message_id)
    with_connection do |imap|
      result = imap.fetch(message_id, "ENVELOPE")
      result&.first&.attr&.dig("ENVELOPE")
    end
  rescue Net::IMAP::Error => e
    add_error("Failed to fetch envelope for message #{message_id}: #{e.message}")
    nil
  end

  def fetch_body_structure(message_id)
    with_connection do |imap|
      result = imap.fetch(message_id, "BODYSTRUCTURE")
      result&.first&.attr&.dig("BODYSTRUCTURE")
    end
  rescue Net::IMAP::Error => e
    add_error("Failed to fetch body structure for message #{message_id}: #{e.message}")
    nil
  end

  def fetch_body_part(message_id, part_number)
    with_connection do |imap|
      part_spec = "BODY[#{part_number}]"
      result = imap.fetch(message_id, part_spec)
      result&.first&.attr&.dig(part_spec)
    end
  rescue Net::IMAP::Error => e
    add_error("Failed to fetch body part #{part_number} for message #{message_id}: #{e.message}")
    nil
  end

  def fetch_text_body(message_id)
    with_connection do |imap|
      result = imap.fetch(message_id, "BODY[TEXT]")
      result&.first&.attr&.dig("BODY[TEXT]")
    end
  rescue Net::IMAP::Error => e
    add_error("Failed to fetch text body for message #{message_id}: #{e.message}")
    nil
  end

  def with_connection
    validate_account!

    imap = create_connection
    authenticate_connection(imap)
    select_inbox(imap)

    result = yield(imap)

    cleanup_connection(imap)
    result
  rescue ConnectionError
    # Re-raise our own connection errors without modification
    raise
  rescue Net::IMAP::NoResponseError => e
    cleanup_connection(imap) if imap
    raise AuthenticationError, "Authentication failed: #{e.message}"
  rescue Net::IMAP::Error => e
    cleanup_connection(imap) if imap
    raise ConnectionError, "IMAP error: #{e.message}"
  rescue StandardError => e
    cleanup_connection(imap) if imap
    raise ConnectionError, "Unexpected error: #{e.message}"
  end

  private

  def validate_account!
    unless email_account.active?
      raise ConnectionError, "Email account is not active"
    end

    unless email_account.encrypted_password.present?
      raise ConnectionError, "Email account missing password"
    end
  end

  def create_connection
    settings = email_account.imap_settings

    Net::IMAP.new(
      settings[:address],
      port: settings[:port],
      ssl: settings[:enable_ssl]
    )
  end

  def authenticate_connection(imap)
    settings = email_account.imap_settings
    imap.login(settings[:user_name], settings[:password])
  end

  def select_inbox(imap)
    imap.select("INBOX")
  end

  def cleanup_connection(imap)
    return unless imap

    begin
      imap.logout if imap.respond_to?(:logout)
    rescue Net::IMAP::Error
      # Ignore logout errors - connection might already be closed
    end

    begin
      imap.disconnect if imap.respond_to?(:disconnect)
    rescue StandardError
      # Ignore disconnect errors
    end
  end

  def add_error(message)
    @errors << message
    Rails.logger.error "[ImapConnectionService] #{email_account.email}: #{message}"
  end
end
