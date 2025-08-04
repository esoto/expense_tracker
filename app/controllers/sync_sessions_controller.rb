class SyncSessionsController < ApplicationController
  before_action :set_sync_session, only: [ :show, :cancel, :retry ]

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
    @sync_session = SyncSession.create!

    if params[:email_account_id].present?
      # Single account sync
      account = EmailAccount.find(params[:email_account_id])
      @sync_session.email_accounts << account
    else
      # All accounts sync
      @sync_session.email_accounts << EmailAccount.active
    end

    # Update the ProcessEmailsJob to accept sync_session_id
    ProcessEmailsJob.perform_later(
      params[:email_account_id],
      since: 1.week.ago,
      sync_session_id: @sync_session.id
    )

    redirect_to sync_sessions_path, notice: "Sincronización iniciada exitosamente"
  end

  def cancel
    if @sync_session.active?
      @sync_session.cancel!
      # TODO: Cancel associated jobs
      redirect_to sync_sessions_path, notice: "Sincronización cancelada"
    else
      redirect_to sync_sessions_path, alert: "No se puede cancelar esta sincronización"
    end
  end

  def retry
    if @sync_session.failed? || @sync_session.cancelled?
      # Create a new sync session with same accounts
      new_session = SyncSession.create!
      new_session.email_accounts << @sync_session.email_accounts

      ProcessEmailsJob.perform_later(
        nil,
        since: 1.week.ago,
        sync_session_id: new_session.id
      )

      redirect_to sync_sessions_path, notice: "Sincronización reiniciada"
    else
      redirect_to sync_sessions_path, alert: "No se puede reintentar esta sincronización"
    end
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

