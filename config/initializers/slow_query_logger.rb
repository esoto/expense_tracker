# Log slow queries in development and staging
if Rails.env.development? || Rails.env.staging?
  ActiveSupport::Notifications.subscribe "sql.active_record" do |name, start, finish, id, payload|
    duration = (finish - start) * 1000  # Convert to milliseconds

    if duration > 100  # Log queries slower than 100ms
      Rails.logger.warn "[SLOW QUERY] #{duration.round(2)}ms: #{payload[:sql]}"
    end
  end
end
