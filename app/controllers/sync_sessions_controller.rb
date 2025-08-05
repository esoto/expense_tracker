class SyncSessionsController < ApplicationController
  include SyncAuthorization
  include SyncErrorHandling

  before_action :set_sync_session, only: [ :show, :cancel, :retry ]
  before_action :authorize_sync_session_owner!, only: [ :show, :cancel, :retry ]

  def index
    @active_session = SyncSession.active.includes(:sync_session_accounts, :email_accounts).first
    @recent_sessions = SyncSession.recent.includes(:email_accounts).limit(10)
    @email_accounts = EmailAccount.active.order(:bank_name, :email)
  end

  def show
    @session_accounts = @sync_session.sync_session_accounts
                                    .includes(:email_account)
                                    .order(:created_at)
  end

  def create
    # Validate sync can be created
    validator = SyncSessionValidator.new

    begin
      validator.validate!
    rescue SyncSessionValidator::SyncLimitExceeded
      return handle_sync_limit_exceeded
    rescue SyncSessionValidator::RateLimitExceeded
      return handle_rate_limit_exceeded
    end

    # Create sync session with transaction
    @sync_session = SyncSession.transaction do
      session = SyncSession.create!

      if params[:email_account_id].present?
        # Single account sync - verify ownership/access
        account = EmailAccount.active.find(params[:email_account_id])
        session.email_accounts << account
      else
        # All accounts sync
        accounts = EmailAccount.active
        if accounts.empty?
          raise ActiveRecord::RecordInvalid.new(session), "No hay cuentas de email activas para sincronizar"
        end
        session.email_accounts << accounts
      end

      session
    end

    # Start sync job
    ProcessEmailsJob.perform_later(
      params[:email_account_id],
      since: params[:since]&.to_date || 1.week.ago,
      sync_session_id: @sync_session.id
    )

    respond_to do |format|
      format.html { redirect_to sync_sessions_path, notice: "Sincronización iniciada exitosamente" }
      format.json { render json: { id: @sync_session.id, status: @sync_session.status }, status: :created }
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to sync_sessions_path, alert: "Cuenta de email no encontrada o inactiva"
  end

  def cancel
    unless @sync_session.active?
      return redirect_to sync_sessions_path, alert: "Esta sincronización no está activa"
    end

    @sync_session.cancel!

    respond_to do |format|
      format.html { redirect_to sync_sessions_path, notice: "Sincronización cancelada exitosamente" }
      format.json { render json: { status: @sync_session.status }, status: :ok }
    end
  rescue => e
    Rails.logger.error "Error cancelling sync session #{@sync_session.id}: #{e.message}"
    redirect_to sync_sessions_path, alert: "Error al cancelar la sincronización"
  end

  def retry
    unless @sync_session.failed? || @sync_session.cancelled?
      return redirect_to sync_sessions_path, alert: "Solo se pueden reintentar sincronizaciones fallidas o canceladas"
    end

    # Check rate limit for retry
    validator = SyncSessionValidator.new
    unless validator.can_create_sync?
      return handle_rate_limit_exceeded
    end

    # Create a new sync session with same accounts
    new_session = SyncSession.transaction do
      session = SyncSession.create!
      session.email_accounts << @sync_session.email_accounts
      session
    end

    # Track retry in the new session
    new_session.update!(retry_of_id: @sync_session.id) if new_session.respond_to?(:retry_of_id=)

    ProcessEmailsJob.perform_later(
      nil,
      since: params[:since]&.to_date || 1.week.ago,
      sync_session_id: new_session.id
    )

    respond_to do |format|
      format.html { redirect_to sync_sessions_path, notice: "Sincronización reiniciada exitosamente" }
      format.json { render json: { id: new_session.id, status: new_session.status }, status: :created }
    end
  rescue => e
    Rails.logger.error "Error retrying sync session #{@sync_session.id}: #{e.message}"
    redirect_to sync_sessions_path, alert: "Error al reintentar la sincronización"
  end

  def status
    session = SyncSession.find_by(id: params[:sync_session_id])

    if session
      render json: {
        status: session.status,
        progress_percentage: session.progress_percentage,
        processed_emails: session.processed_emails,
        total_emails: session.total_emails,
        detected_expenses: session.detected_expenses,
        time_remaining: session.estimated_time_remaining,
        accounts: session.sync_session_accounts.map do |account|
          {
            id: account.id,
            email: account.email_account.email,
            bank: account.email_account.bank_name,
            status: account.status,
            progress: account.progress_percentage,
            processed: account.processed_emails,
            total: account.total_emails,
            detected: account.detected_expenses
          }
        end
      }
    else
      render json: { error: "Session not found" }, status: :not_found
    end
  end

  private

  def set_sync_session
    @sync_session = SyncSession.find(params[:id])
  end
end
