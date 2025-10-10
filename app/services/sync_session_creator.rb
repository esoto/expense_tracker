module Services
  class SyncSessionCreator
  attr_reader :params, :validator, :request_info

  def initialize(params = {}, request_info = {})
    @params = params
    @validator = SyncSessionValidator.new
    @request_info = request_info
  end

  def call
    validate_sync_creation!

    sync_session = create_sync_session
    enqueue_sync_job(sync_session)

    Result.new(success: true, sync_session: sync_session)
  rescue SyncSessionValidator::SyncLimitExceeded => e
    Result.new(success: false, error: :sync_limit_exceeded, message: e.message)
  rescue SyncSessionValidator::RateLimitExceeded => e
    Result.new(success: false, error: :rate_limit_exceeded, message: e.message)
  rescue ActiveRecord::RecordNotFound
    Result.new(success: false, error: :account_not_found, message: "Cuenta de email no encontrada o inactiva")
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success: false, error: :validation_error, message: e.message)
  rescue StandardError => e
    Rails.logger.error "Unexpected error creating sync session: #{e.message}"
    Result.new(success: false, error: :unexpected_error, message: "Error inesperado al crear la sincronización")
  end

  private

  def validate_sync_creation!
    validator.validate!
  end

  def create_sync_session
    SyncSession.transaction do
      session = SyncSession.create!(
        metadata: build_metadata
      )

      if params[:email_account_id].present?
        add_single_account(session)
      else
        add_all_accounts(session)
      end

      session
    end
  end

  def build_metadata
    {
      ip_address: request_info[:ip_address],
      user_agent: request_info[:user_agent],
      created_from: request_info[:source] || "web",
      rails_session_id: request_info[:session_id]
    }.compact
  end

  def add_single_account(session)
    account = EmailAccount.active.find(params[:email_account_id])
    session.email_accounts << account
  end

  def add_all_accounts(session)
    accounts = EmailAccount.active.includes(:parsing_rules)

    if accounts.empty?
      session.errors.add(:base, "No hay cuentas de email activas para sincronizar")
      raise ActiveRecord::RecordInvalid.new(session)
    end

    # Batch insert for better performance
    session.email_accounts << accounts
  end

  def enqueue_sync_job(sync_session)
    ProcessEmailsJob.perform_later(
      params[:email_account_id],
      since: params[:since]&.to_date || default_sync_period,
      sync_session_id: sync_session.id
    )
  end

  def default_sync_period
    # Make this configurable
    1.week.ago
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
