class SyncSessionsController < ApplicationController
  include SyncAuthorization
  include SyncErrorHandling

  before_action :set_sync_session, only: [ :show, :cancel, :retry ]
  before_action :authorize_sync_session_owner!, only: [ :show, :cancel, :retry ]

  def index
    @active_session = SyncSession.active.includes(:sync_session_accounts, :email_accounts).first
    @recent_sessions = SyncSessionPerformanceOptimizer.preload_for_index.limit(10)
    @email_accounts = EmailAccount.active.order(:bank_name, :email)
    # Additional data for enhanced UI
    @active_accounts_count = EmailAccount.active.count
    @today_sync_count = SyncSession.where(created_at: Date.current.beginning_of_day..Date.current.end_of_day).count
    @monthly_expenses_detected = SyncSession.completed
                                          .where(completed_at: Date.current.beginning_of_month..Date.current.end_of_month)
                                          .sum(:detected_expenses)
    @last_completed_session = SyncSession.completed.recent.first
  end

  def show
    @session_accounts = SyncSessionPerformanceOptimizer.preload_for_show(@sync_session)
  end

  def create
    result = SyncSessionCreator.new(sync_params, request_info).call

    if result.success?
      @sync_session = result.sync_session
      # Store sync session ID in Rails session for authorization
      session[:sync_session_id] = @sync_session.id

      respond_to do |format|
        format.turbo_stream {
          # For dashboard, redirect to sync_sessions page
          if request.referer&.include?("dashboard")
            redirect_to sync_sessions_path, notice: "Sincronización iniciada exitosamente"
          else
            redirect_to sync_sessions_path, notice: "Sincronización iniciada exitosamente"
          end
        }
        format.html { redirect_to sync_sessions_path, notice: "Sincronización iniciada exitosamente" }
        format.json { render json: { id: @sync_session.id, status: @sync_session.status }, status: :created }
      end
    else
      handle_creation_error(result)
    end
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
    result = SyncSessionRetryService.new(@sync_session, retry_params).call

    if result.success?
      new_session = result.sync_session
      respond_to do |format|
        format.html { redirect_to sync_sessions_path, notice: "Sincronización reiniciada exitosamente" }
        format.json { render json: { id: new_session.id, status: new_session.status }, status: :created }
      end
    else
      handle_retry_error(result)
    end
  end

  def status
    session = SyncSession.find_by(id: params[:sync_session_id])

    if session
      # Use caching for frequently accessed status
      status_data = Rails.cache.fetch(
        SyncSessionPerformanceOptimizer.cache_key_for_status(session.id),
        expires_in: 5.seconds,
        race_condition_ttl: 2.seconds
      ) do
        build_status_response(session)
      end

      render json: status_data
    else
      render json: { error: "Session not found" }, status: :not_found
    end
  end

  private

  def set_sync_session
    @sync_session = SyncSession.find(params[:id])
  end

  def sync_params
    params.permit(:email_account_id, :since)
  end

  def request_info
    {
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      session_id: session.id.to_s,
      source: "web"
    }
  end

  def retry_params
    params.permit(:since)
  end

  def handle_creation_error(result)
    case result.error
    when :sync_limit_exceeded
      handle_sync_limit_exceeded
    when :rate_limit_exceeded
      handle_rate_limit_exceeded
    when :account_not_found
      redirect_to sync_sessions_path, alert: result.message
    else
      redirect_to sync_sessions_path, alert: result.message || "Error al crear la sincronización"
    end
  end

  def handle_retry_error(result)
    case result.error
    when :rate_limit_exceeded
      handle_rate_limit_exceeded
    else
      redirect_to sync_sessions_path, alert: result.message
    end
  end

  def build_status_response(session)
    # Preload accounts with their email accounts
    accounts = session.sync_session_accounts.includes(:email_account)

    {
      status: session.status,
      progress_percentage: session.progress_percentage,
      processed_emails: session.processed_emails,
      total_emails: session.total_emails,
      detected_expenses: session.detected_expenses,
      time_remaining: session.estimated_time_remaining,
      metrics: SyncSessionPerformanceOptimizer.calculate_metrics(session),
      accounts: accounts.map do |account|
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
  end
end
