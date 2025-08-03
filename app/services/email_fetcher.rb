class EmailFetcher
  attr_reader :email_account, :errors, :imap_service, :email_processor

  def initialize(email_account, imap_service: nil, email_processor: nil)
    @email_account = email_account
    @imap_service = imap_service || ImapConnectionService.new(email_account)
    @email_processor = email_processor || EmailProcessor.new(email_account)
    @errors = []
  end

  def fetch_new_emails(since: 1.week.ago)
    unless valid_account?
      return EmailFetcherResponse.failure(errors: @errors)
    end

    begin
      result = search_and_process_emails(since)
      EmailFetcherResponse.success(
        processed_emails_count: result[:processed_emails_count],
        total_emails_found: result[:total_emails_found],
        errors: @errors
      )
    rescue ImapConnectionService::ConnectionError, ImapConnectionService::AuthenticationError => e
      add_error("IMAP Error: #{e.message}")
      EmailFetcherResponse.failure(errors: @errors)
    rescue StandardError => e
      add_error("Unexpected error: #{e.message}")
      EmailFetcherResponse.failure(errors: @errors)
    end
  end

  def test_connection
    result = imap_service.test_connection
    @errors.concat(imap_service.errors)

    if result
      EmailFetcherResponse.success(errors: @errors)
    else
      EmailFetcherResponse.failure(errors: @errors)
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

  def search_and_process_emails(since)
    # Search for emails from bank domains or with expense-related keywords
    search_criteria = build_search_criteria(since)

    message_ids = imap_service.search_emails(search_criteria)
    @errors.concat(imap_service.errors)

    if message_ids.empty?
      Rails.logger.info "No new emails found for #{email_account.email}"
      return {
        processed_emails_count: 0,
        total_emails_found: 0
      }
    end

    Rails.logger.info "Found #{message_ids.length} emails for #{email_account.email}"

    # Delegate email processing to EmailProcessor
    processing_result = email_processor.process_emails(message_ids, imap_service)
    @errors.concat(email_processor.errors)
    @errors.concat(imap_service.errors)

    {
      processed_emails_count: processing_result[:processed_count],
      total_emails_found: processing_result[:total_count]
    }
  end

  def build_search_criteria(since)
    # Simple search for recent emails - we'll filter by content later
    [ "SINCE", since.strftime("%d-%b-%Y") ]
  end


  def add_error(message)
    @errors << message
    Rails.logger.error "[EmailFetcher] #{email_account.email}: #{message}"
  end
end
