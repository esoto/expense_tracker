class SyncSessionPerformanceOptimizer
  # Query optimizations
  def self.preload_for_index
    SyncSession
      .includes(
        :email_accounts,
        sync_session_accounts: :email_account
      )
      .recent
  end

  def self.preload_for_show(sync_session)
    sync_session.sync_session_accounts
      .includes(:email_account)
      .order(:created_at)
  end

  # Batch operations
  def self.batch_update_progress(sync_session_ids)
    return if sync_session_ids.empty?

    # Use raw SQL for better performance on bulk updates
    sql = <<-SQL
      UPDATE sync_sessions
      SET#{' '}
        total_emails = subquery.total,
        processed_emails = subquery.processed,
        detected_expenses = subquery.detected,
        updated_at = CURRENT_TIMESTAMP
      FROM (
        SELECT#{' '}
          sync_session_id,
          COALESCE(SUM(total_emails), 0) as total,
          COALESCE(SUM(processed_emails), 0) as processed,
          COALESCE(SUM(detected_expenses), 0) as detected
        FROM sync_session_accounts
        WHERE sync_session_id IN (?)
        GROUP BY sync_session_id
      ) AS subquery
      WHERE sync_sessions.id = subquery.sync_session_id
    SQL

    sanitized_sql = ActiveRecord::Base.sanitize_sql_array([ sql, sync_session_ids ])
    ActiveRecord::Base.connection.execute(sanitized_sql)
  end

  # Cache helpers
  def self.cache_key_for_session(sync_session)
    "sync_session/#{sync_session.id}/#{sync_session.updated_at.to_i}"
  end

  def self.cache_key_for_status(sync_session_id)
    "sync_session_status/#{sync_session_id}"
  end

  # Efficient status checking
  def self.active_session_exists?
    Rails.cache.fetch("active_sync_session_exists", expires_in: 30.seconds) do
      SyncSession.active.exists?
    end
  end

  def self.clear_active_session_cache
    Rails.cache.delete("active_sync_session_exists")
  end

  # Performance metrics
  def self.calculate_metrics(sync_session)
    return {} unless sync_session.started_at

    duration = sync_session.duration
    processed = sync_session.processed_emails

    {
      duration_seconds: duration&.to_i,
      emails_per_second: processed > 0 && duration ? (processed / duration).round(2) : 0,
      average_time_per_email: processed > 0 && duration ? (duration / processed).round(2) : nil,
      estimated_completion: estimate_completion_time(sync_session)
    }
  end

  private

  def self.estimate_completion_time(sync_session)
    return nil unless sync_session.running? && sync_session.processed_emails > 0

    rate = sync_session.processed_emails.to_f / (Time.current - sync_session.started_at)
    remaining = sync_session.total_emails - sync_session.processed_emails

    return nil if rate.zero?

    Time.current + (remaining / rate).seconds
  end
end
