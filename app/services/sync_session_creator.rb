module Services
  class SyncSessionCreator
  attr_reader :params, :validator, :request_info, :user

  def initialize(params = {}, request_info = {}, user = nil)
    @params = params
    @validator = SyncSessionValidator.new
    @request_info = request_info
    @user = user
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
        user: resolved_user,
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

  # Resolves the owner for the new SyncSession.
  # Caller (SyncSessionsController) passes scoping_user explicitly.
  # Background/legacy callers that have no auth context pass nil — we derive
  # the user from the requested email_account when available, then fall back
  # to the first admin user (FIXME(PR-7b): thread user through all callers).
  def resolved_user
    return user if user.present?

    # Derive from the requested email_account when an id is provided
    if params[:email_account_id].present?
      account = EmailAccount.find_by(id: params[:email_account_id])
      return account.user if account&.user.present?
    end

    fallback = User.where(role: 1).order(:id).first
    Rails.logger.warn(
      "[SyncSessionCreator] No user provided; falling back to User.admin.first " \
      "(id=#{fallback&.id}). Fix in PR-7b by threading user through background jobs."
    ) if fallback
    fallback or raise(ActiveRecord::RecordInvalid, "No admin User found and no user provided")
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
      before: params[:before]&.to_date,
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
