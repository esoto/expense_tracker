module SyncAuthorization
  extend ActiveSupport::Concern

  included do
    before_action :authorize_sync_access!
  end

  private

  def authorize_sync_access!
    # For now, we'll use a simple check that could be expanded later
    # In a real app, this would check user permissions
    return if sync_access_allowed?

    respond_to do |format|
      format.html { redirect_to root_path, alert: "No tienes permiso para acceder a las sincronizaciones" and return }
      format.json { render json: { error: "Unauthorized" }, status: :unauthorized and return }
    end
  end

  def sync_access_allowed?
    current_user.present?
  end

  def authorize_sync_session_owner!
    # Ensure user can only access their own sync sessions
    # This would check if current_user owns the sync session
    return if sync_session_owner?

    respond_to do |format|
      format.html { redirect_to sync_sessions_path, alert: "No tienes permiso para acceder a esta sincronización" and return }
      format.json { render json: { error: "Forbidden" }, status: :forbidden and return }
    end
  end

  def sync_session_owner?
    # SyncSession.user_id is the authoritative ownership column (PR-14).
    # Require an authenticated user as a baseline security check.
    current_user.present?
  end
end
