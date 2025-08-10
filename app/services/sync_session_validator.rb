class SyncSessionValidator
  class SyncLimitExceeded < StandardError; end
  class RateLimitExceeded < StandardError; end

  RATE_LIMIT_WINDOW = 5.minutes
  MAX_SYNCS_PER_WINDOW = 3
  MAX_ACTIVE_SYNCS = 1

  def initialize(user = nil)
    @user = user
  end

  def validate!
    check_active_sync_limit!
    check_rate_limit!
    true
  end

  def can_create_sync?
    !active_sync_exists? && !rate_limit_exceeded?
  end

  def active_sync_exists?
    SyncSession.active.exists?
  end

  def recent_sync_count
    SyncSession.where(created_at: RATE_LIMIT_WINDOW.ago..Time.current).count
  end

  private

  def check_active_sync_limit!
    if SyncSession.active.count >= MAX_ACTIVE_SYNCS
      raise SyncLimitExceeded, "Ya hay una sincronización activa. Espera a que termine antes de iniciar otra."
    end
  end

  def check_rate_limit!
    if rate_limit_exceeded?
      raise RateLimitExceeded, "Has alcanzado el límite de sincronizaciones. Intenta nuevamente en unos minutos."
    end
  end

  def rate_limit_exceeded?
    recent_sync_count >= MAX_SYNCS_PER_WINDOW
  end
end
