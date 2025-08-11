module SyncErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :handle_validation_error
    if Rails.env.production?
      rescue_from StandardError, with: :handle_unexpected_error
    end
  end

  private

  def handle_not_found
    respond_to do |format|
      format.html { redirect_to sync_sessions_path, alert: "Sincronización no encontrada" }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def handle_validation_error(exception)
    respond_to do |format|
      format.html do
        redirect_to sync_sessions_path, alert: "Error de validación: #{exception.record.errors.full_messages.join(', ')}"
      end
      format.json do
        render json: { errors: exception.record.errors.full_messages }, status: :unprocessable_content
      end
    end
  end

  def handle_unexpected_error(exception)
    Rails.logger.error "Unexpected error in #{controller_name.camelize}: #{exception.message}"
    Rails.logger.error exception.backtrace.join("\n")

    respond_to do |format|
      format.html do
        redirect_to sync_sessions_path, alert: "Ocurrió un error inesperado. Por favor intenta nuevamente."
      end
      format.json do
        render json: { error: "Internal server error" }, status: :internal_server_error
      end
    end
  end

  def handle_sync_limit_exceeded
    respond_to do |format|
      format.json do
        render json: { error: "Sync limit exceeded", message: "Active sync already in progress" }, status: :too_many_requests
      end
      format.html do
        redirect_to sync_sessions_path, alert: "Ya hay una sincronización activa. Espera a que termine antes de iniciar otra."
      end
      format.any do
        redirect_to sync_sessions_path, alert: "Ya hay una sincronización activa. Espera a que termine antes de iniciar otra."
      end
    end
  end

  def handle_rate_limit_exceeded
    respond_to do |format|
      format.json do
        render json: {
          error: "Too many requests",
          message: "You have exceeded the rate limit. Please try again later.",
          retry_after: (Time.current.beginning_of_minute + 5.minutes).to_i.to_s
        }, status: :too_many_requests
      end
      format.html do
        redirect_to sync_sessions_path, alert: "Has alcanzado el límite de sincronizaciones. Intenta nuevamente en unos minutos."
      end
      format.any do
        redirect_to sync_sessions_path, alert: "Has alcanzado el límite de sincronizaciones. Intenta nuevamente en unos minutos."
      end
    end
  end
end
