class ProcessEmailsJob < ApplicationJob
  queue_as :email_processing

  # Add retry logic
  retry_on Services::ImapConnectionService::ConnectionError, wait: 10.seconds, attempts: 3
  retry_on Net::ReadTimeout, wait: 5.seconds, attempts: 2

  # Add performance monitoring
  around_perform do |job, block|
    start_time = Time.current
    account_id = job.arguments.first

    Rails.logger.info "[ProcessEmailsJob] Starting for account #{account_id}"

    block.call

    duration = Time.current - start_time
    Rails.logger.info "[ProcessEmailsJob] Completed in #{duration.round(2)}s"

    # Alert on slow processing
    if duration > 30.seconds
      Rails.logger.warn "[ProcessEmailsJob] Slow processing: #{duration.round(2)}s for account #{account_id}"
    end
  end

  def perform(email_account_id = nil, since: 1.week.ago, sync_session_id: nil)
    @sync_session = sync_session_id ? SyncSession.find_by(id: sync_session_id) : nil
    @metrics_collector = Services::SyncMetricsCollector.new(@sync_session) if @sync_session

    # Validate sync session state
    if @sync_session
      unless @sync_session.pending? || @sync_session.running?
        Rails.logger.warn "Attempted to process sync session #{sync_session_id} in invalid state: #{@sync_session.status}"
        return
      end

      @sync_session.start! if @sync_session.pending?
    end

    # Track overall job performance
    if @metrics_collector
      @metrics_collector.track_operation(:sync_account, nil, { job_type: "batch" }) do
        if email_account_id
          process_single_account(email_account_id, since)
        else
          process_all_accounts(since)
        end
      end
    else
      if email_account_id
        process_single_account(email_account_id, since)
      else
        process_all_accounts(since)
      end
    end

    if @sync_session && !email_account_id
      # Record session metrics before monitoring
      @metrics_collector&.record_session_metrics
      @metrics_collector&.flush_buffer

      # Start monitoring job to track completion
      SyncSessionMonitorJob.set(wait: 5.seconds).perform_later(@sync_session.id)
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "ProcessEmailsJob: Record not found - #{e.message}"
    @sync_session&.fail!("Registro no encontrado: #{e.message}")
  rescue StandardError => e
    Rails.logger.error "ProcessEmailsJob: Unexpected error - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    @sync_session&.fail!("Error inesperado: #{e.message}")
    raise # Re-raise for job retry mechanism
  ensure
    @metrics_collector&.flush_buffer
  end

  private

  def process_single_account(email_account_id, since)
    email_account = EmailAccount.find_by(id: email_account_id)
    session_account = find_or_create_session_account(email_account) if @sync_session

    # Store job ID in session account if available
    if session_account && self.class.respond_to?(:current_job_id)
      session_account.update(job_id: self.class.current_job_id)
    end

    unless email_account
      Rails.logger.error "EmailAccount not found: #{email_account_id}"
      session_account&.fail!("Email account not found")
      return
    end

    unless email_account.active?
      Rails.logger.info "Skipping inactive email account: #{email_account.email}"
      session_account&.fail!("Email account is inactive")
      return
    end

    Rails.logger.info "Processing emails for: #{email_account.email}"
    session_account&.start_processing!

    begin
      # Pass metrics collector to fetcher
      fetcher = Services::EmailProcessing::Fetcher.new(
        email_account,
        sync_session_account: session_account,
        metrics_collector: @metrics_collector
      )
      result = fetcher.fetch_new_emails(since: since)

      if result.success?
        Rails.logger.info "Successfully processed emails for: #{email_account.email} - " \
                         "Found: #{result.total_emails_found}, Processed: #{result.processed_emails_count}"
        if result.has_errors?
          Rails.logger.warn "Warnings during processing: #{result.error_messages}"
        end
        session_account&.complete!
      else
        Rails.logger.error "Failed to process emails for #{email_account.email}: #{result.error_messages}"
        session_account&.fail!(result.error_messages)
      end
    rescue => e
      Rails.logger.error "Error processing account #{email_account.email}: #{e.message}"
      session_account&.fail!("Error procesando cuenta: #{e.message}")
      raise if @sync_session.nil? # Re-raise only for standalone jobs
    end
  end

  def find_or_create_session_account(email_account)
    return nil unless @sync_session && email_account

    @sync_session.sync_session_accounts.find_or_create_by(email_account: email_account)
  end

  def process_all_accounts(since)
    email_accounts = EmailAccount.active

    Rails.logger.info "Processing emails for #{email_accounts.count} active accounts"

    email_accounts.find_each do |email_account|
      # Process each account in a separate job to isolate failures
      job = ProcessEmailsJob.perform_later(email_account.id, since: since, sync_session_id: @sync_session&.id)

      # Track job ID if we have a sync session
      if @sync_session && job.respond_to?(:provider_job_id)
        @sync_session.add_job_id(job.provider_job_id)
      end
    end
  end

  def process_all_accounts_in_batches(since)
    EmailAccount.active.find_in_batches(batch_size: 5) do |batch|
      batch.each do |email_account|
        ProcessEmailsJob.perform_later(email_account.id, since: since)
      end

      # Prevent IMAP server overload
      sleep(1) if batch.size == 5
    end
  end
end
