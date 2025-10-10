module Services
  class Services::SyncSessionRetryService
  attr_reader :original_session, :params

  def initialize(original_session, params = {})
    @original_session = original_session
    @params = params
  end

  def call
    return error_result(:invalid_status) unless can_retry?
    return error_result(:rate_limit_exceeded) if rate_limit_exceeded?

    new_session = create_retry_session
    enqueue_sync_job(new_session)

    Result.new(success: true, sync_session: new_session)
  rescue StandardError => e
    Rails.logger.error "Error retrying sync session #{original_session.id}: #{e.message}"
    error_result(:unexpected_error, "Error al reintentar la sincronización")
  end

  private

  def can_retry?
    original_session.failed? || original_session.cancelled?
  end

  def rate_limit_exceeded?
    !SyncSessionValidator.new.can_create_sync?
  end

  def create_retry_session
    SyncSession.transaction do
      new_session = SyncSession.create!

      # Copy email accounts with batch insert
      account_ids = original_session.email_account_ids
      if account_ids.any?
        new_session.email_account_ids = account_ids
      end

      # Track retry relationship if column exists
      if new_session.respond_to?(:retry_of_id=)
        new_session.update_column(:retry_of_id, original_session.id)
      end

      new_session
    end
  end

  def enqueue_sync_job(sync_session)
    ProcessEmailsJob.perform_later(
      nil,
      since: params[:since]&.to_date || default_sync_period,
      sync_session_id: sync_session.id
    )
  end

  def default_sync_period
    1.week.ago
  end

  def error_result(error_type, message = nil)
    message ||= case error_type
    when :invalid_status
      "Solo se pueden reintentar sincronizaciones fallidas o canceladas"
    when :rate_limit_exceeded
      "Has alcanzado el límite de sincronizaciones. Intenta nuevamente en unos minutos."
    else
      "Error al reintentar la sincronización"
    end

    Result.new(success: false, error: error_type, message: message)
  end

  class Result
    attr_reader :sync_session, :error, :message

    def initialize(success:, sync_session: nil, error: nil, message: nil)
      @success = success
      @sync_session = sync_session
      @error = error
      @message = message
    end

    def success?
      @success
    end

    def failure?
      !@success
    end
  end
  end
end
