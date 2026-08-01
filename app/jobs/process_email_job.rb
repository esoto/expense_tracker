class ProcessEmailJob < ApplicationJob
  queue_as :email_processing

  # Retry with exponential back-off on transient database contention (overrides ApplicationJob default)
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5

  # Retry on connection loss (e.g. brief DB restart) — not covered by parent class
  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3

  # Discard when job arguments reference a record that no longer exists (inherited, explicit for clarity)
  discard_on ActiveJob::DeserializationError

  TRUNCATE_SIZE = 10_000  # Store only 10KB for large emails

  # Security fix (2026-08 audit): `email_data_or_payload_id` is now either an
  # Integer/String QueuedEmailPayload id (current producer path) or, for
  # deploy-window compatibility, a legacy plaintext Hash (jobs already
  # enqueued by Services::EmailProcessing::Processor before this fix
  # shipped). See #resolve_email_payload for the branch. `legacy_pre_parsed_data`
  # is only ever populated on that legacy Hash path — the current path folds
  # pre_parsed data into the encrypted QueuedEmailPayload record instead.
  def perform(email_account_id, email_data_or_payload_id, sync_session_id = nil, legacy_pre_parsed_data = nil)
    email_account = EmailAccount.find_by(id: email_account_id)

    unless email_account
      Rails.logger.error "EmailAccount not found: #{email_account_id}"
      return
    end

    payload_record, email_data, pre_parsed_data = resolve_email_payload(email_data_or_payload_id, legacy_pre_parsed_data)
    return if email_data.nil?

    Rails.logger.info "Processing individual email for: #{email_account.email}"
    # Do NOT log email_data.inspect — the :body contains plaintext bank PII and is
    # a plain Hash, so filter_parameters/filter_attributes do not redact it.
    Rails.logger.debug "Email data: subject=#{email_data&.dig(:subject).inspect}, message_id=#{email_data&.dig(:message_id).inspect}"

    # Use explicit sync session ID instead of global lookup
    sync_session = sync_session_id ? SyncSession.find_by(id: sync_session_id) : nil
    metrics_collector = Services::SyncMetricsCollector.new(sync_session) if sync_session

    # Track expense detection operation
    result = if metrics_collector
      outcome = metrics_collector.track_operation(:detect_expense, email_account, { email_subject: email_data&.dig(:subject) }) do
        parse_and_save_expense(email_account, email_data, pre_parsed_data)
      end
      metrics_collector.flush_buffer
      outcome
    else
      parse_and_save_expense(email_account, email_data, pre_parsed_data)
    end

    # Only reached once processing has actually completed (success or a
    # handled parsing failure) — if anything above raises, execution never
    # gets here and the record is left unprocessed so a retry_on retry (or a
    # manual re-run) still has data to work with.
    begin
      payload_record&.mark_processed!
    rescue StandardError => e
      # A processed-but-unmarked payload is harmless: QueuedEmailPayload's
      # UNPROCESSED_RETENTION (30 days) purges it eventually regardless. But
      # letting this raise escape would re-trigger this job's own retry_on
      # (e.g. ActiveRecord::Deadlocked), which re-parses the email and, since
      # the expense was already persisted above, flips it to status:
      # :duplicate via Parser's duplicate branch — silent data corruption on
      # an already-successful outcome. Log and swallow instead.
      Rails.logger.error "[ProcessEmailJob] Failed to mark QueuedEmailPayload #{payload_record&.id.inspect} as processed: #{e.class}: #{e.message}"
    end

    result
  end

  private

  # Resolves the (payload_record, email_data, pre_parsed_data) tuple the rest
  # of #perform needs, supporting two argument shapes:
  #
  #   - Integer/String id (current path): looks up the encrypted
  #     QueuedEmailPayload record created by
  #     Services::EmailProcessing::Processor and unpacks its payload_data.
  #   - Hash (legacy path, deploy-window compatibility): jobs enqueued by the
  #     old signature — a plaintext email_data Hash plus pre_parsed_data as
  #     the 4th positional argument — before this fix shipped. In-flight
  #     Solid Queue jobs from before the deploy must still process
  #     successfully, so this path stays supported (it's cheap to keep).
  #
  # A missing/deleted payload record (already processed + purged, or an
  # invalid id) or an unrecognized argument type both return a nil email_data,
  # which #perform treats as "log it, discard, don't crash-loop through the
  # retry budget."
  def resolve_email_payload(email_data_or_payload_id, legacy_pre_parsed_data)
    case email_data_or_payload_id
    when Integer, String
      payload_record = QueuedEmailPayload.find_by(id: email_data_or_payload_id)
      unless payload_record
        Rails.logger.error "[ProcessEmailJob] QueuedEmailPayload #{email_data_or_payload_id.inspect} not found (already processed/purged, or invalid id) — discarding."
        return [ nil, nil, nil ]
      end

      # Replayed/duplicate enqueue of the same payload id (e.g. a retry_on
      # retry after mark_processed! itself failed — see the rescue around
      # mark_processed! in #perform). The record was already fully processed,
      # so re-parsing here would call Parser again on an already-persisted
      # expense, which flips it to status: :duplicate via Parser's duplicate
      # branch. Skip straight to the "nothing to do" tuple instead.
      if payload_record.processed_at.present?
        Rails.logger.warn "[ProcessEmailJob] QueuedEmailPayload #{payload_record.id} already processed at #{payload_record.processed_at} — skipping re-parse on replayed enqueue."
        return [ payload_record, nil, nil ]
      end

      data = payload_record.payload_data
      if data.blank?
        # Distinct from the "not found" branch above: the record exists but
        # its payload came back unreadable (see
        # QueuedEmailPayload#payload_data, which rescues deserialization
        # failures and returns nil instead of raising). Corruption must be
        # observable, not silently swallowed into an empty hash.
        Rails.logger.error "[ProcessEmailJob] QueuedEmailPayload #{payload_record.id} found but payload_data is blank (corrupted/unreadable) — discarding."
        return [ payload_record, nil, nil ]
      end

      [ payload_record, data[:email_data], data[:pre_parsed] ]
    when Hash
      # Legacy branch — deploy-window compatibility only, not a supported
      # long-term argument shape. Removal condition: once Solid Queue's
      # ready/scheduled/failed job tables show zero jobs whose second
      # argument is a Hash (i.e. no pre-deploy enqueues left to drain) — in
      # practice ~30 days post-deploy, matching
      # QueuedEmailPayload::UNPROCESSED_RETENTION, since anything older would
      # already be past its retry budget. Tracked as a follow-up; do not
      # remove this branch until that check has been done.
      Rails.logger.warn "[ProcessEmailJob] Deprecated: received a legacy plaintext email_data Hash directly in job arguments (enqueued before the encrypted-payload fix shipped). Processing for deploy-window compatibility."
      [ nil, email_data_or_payload_id, legacy_pre_parsed_data ]
    else
      Rails.logger.error "[ProcessEmailJob] Unrecognized argument type for email_data_or_payload_id: #{email_data_or_payload_id.class} — discarding."
      [ nil, nil, nil ]
    end
  end

  def parse_and_save_expense(email_account, email_data, pre_parsed_data = nil)
    parser = Services::EmailProcessing::Parser.new(email_account, email_data, pre_parsed_data: pre_parsed_data)
    expense = parser.parse_expense

    if expense
      Rails.logger.info "Successfully created expense: #{expense.id} - #{expense.formatted_amount}"

      # Optionally notify about new expense
      # NotificationJob.perform_later(expense.id) if expense.amount > 100

      # Record the terminal outcome (success or marked-duplicate) so a future
      # re-sync can skip this message via ProcessedEmail.already_processed?
      # instead of re-parsing it. Enqueue time is NOT a terminal outcome — this
      # job could still fail — so recording only happens once we get here.
      record_processed_email(email_account, email_data)
    else
      Rails.logger.warn "Failed to create expense from email: #{parser.errors.join(", ")}"

      # Could save failed parsing attempts for debugging
      save_failed_parsing(email_account, email_data, parser.errors)
    end

    expense
  end

  def save_failed_parsing(email_account, email_data, errors)
    email_body = email_data&.dig(:body).to_s
    truncated = false

    if email_body.bytesize > TRUNCATE_SIZE
      email_body = email_body.byteslice(0, TRUNCATE_SIZE) + "\n... [truncated]"
      truncated = true
    end

    EmailParsingFailure.create!(
      email_account: email_account,
      user: email_account.user,
      bank_name: email_account.bank_name,
      error_messages: errors,
      raw_email_content: email_body,
      original_email_size: email_data&.dig(:body).to_s.bytesize,
      truncated: truncated
    )
  rescue StandardError => e
    Rails.logger.error "Failed to save parsing failure record: #{e.message}"
  end

  # Idempotently records that a message reached a terminal outcome (expense
  # created or marked duplicate). See Services::EmailProcessing::Processor
  # for the same pattern applied to non-transaction and conflict-skip outcomes.
  #
  # Keyed on the RFC822 Message-ID header (email_data[:rfc_message_id]) — the
  # IMAP sequence number in email_data[:message_id] is unstable across
  # sessions (RFC 3501) and must never be used as an idempotency key. A
  # blank/missing header is simply not recorded; the email gets re-processed
  # next sync, which is the safe direction.
  #
  # Never allowed to raise — a failure here just means one wasted re-process
  # on the next sync, which is much cheaper than losing an already-saved expense.
  def record_processed_email(email_account, email_data)
    rfc_message_id = email_data&.dig(:rfc_message_id)
    normalized_id = ProcessedEmail.normalize_message_id(rfc_message_id)
    return if normalized_id.nil?

    ProcessedEmail.find_or_create_by!(message_id: normalized_id, email_account_id: email_account.id) do |processed_email|
      processed_email.user = email_account.user
      processed_email.processed_at = Time.current
      processed_email.subject = email_data[:subject]
      processed_email.from_address = email_data[:from]
    end
  rescue StandardError => e
    Rails.logger.error "Failed to record processed email #{rfc_message_id}: #{e.message}"
  end
end
