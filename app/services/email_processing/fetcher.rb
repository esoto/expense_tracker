module EmailProcessing
  class Fetcher
    attr_reader :email_account, :errors, :imap_service, :email_processor

    def initialize(email_account, imap_service: nil, email_processor: nil, sync_session_account: nil)
      @email_account = email_account
      @imap_service = imap_service || ImapConnectionService.new(email_account)
      @email_processor = email_processor || EmailProcessing::Processor.new(email_account)
      @sync_session_account = sync_session_account
      @errors = []
    end

    def fetch_new_emails(since: 1.week.ago)
      unless valid_account?
        return EmailProcessing::FetcherResponse.failure(errors: @errors)
      end

      begin
        result = search_and_process_emails(since)
        EmailProcessing::FetcherResponse.success(
          processed_emails_count: result[:processed_emails_count],
          total_emails_found: result[:total_emails_found],
          errors: @errors
        )
      rescue ImapConnectionService::ConnectionError, ImapConnectionService::AuthenticationError => e
        add_error("IMAP Error: #{e.message}")
        EmailProcessing::FetcherResponse.failure(errors: @errors)
      rescue StandardError => e
        add_error("Unexpected error: #{e.message}")
        EmailProcessing::FetcherResponse.failure(errors: @errors)
      end
    end

    private

    def valid_account?
      if email_account.blank?
        add_error("Email account not provided")
        return false
      end

      unless email_account.active?
        add_error("Email account is not active")
        return false
      end

      unless email_account.encrypted_password?
        add_error("Email account missing password")
        return false
      end

      true
    end

    def search_and_process_emails(since)
      # Build search criteria for emails since the specified date
      search_criteria = build_search_criteria(since)
      message_ids = imap_service.search_emails(search_criteria)
      total_emails_found = message_ids.count

      Rails.logger.info "[EmailProcessing::Fetcher] Found #{total_emails_found} emails for #{email_account.email}"

      # Update sync session with total emails
      @sync_session_account&.update!(total_emails: total_emails_found)

      # Process emails using the email processor with progress tracking
      result = if @sync_session_account
        last_detected = 0
        email_processor.process_emails(message_ids, imap_service) do |processed_count, detected_expenses|
          begin
            # Calculate incremental detected expenses
            incremental_detected = detected_expenses - last_detected
            @sync_session_account.update_progress(processed_count, total_emails_found, incremental_detected)
            last_detected = detected_expenses
          rescue => e
            Rails.logger.error "[EmailProcessing::Fetcher] Failed to update progress: #{e.message}"
            # Continue processing even if progress update fails
          end
        end
      else
        email_processor.process_emails(message_ids, imap_service)
      end

      processed_emails_count = result[:processed_count]

      {
        processed_emails_count: processed_emails_count,
        total_emails_found: total_emails_found
      }
    end

    def build_search_criteria(since_date)
      formatted_date = since_date.strftime("%d-%b-%Y")
      [ "SINCE", formatted_date ]
    end

    def add_error(message)
      @errors << message
      Rails.logger.error "[EmailProcessing::Fetcher] #{email_account&.email || 'Unknown'}: #{message}"
    end
  end
end
