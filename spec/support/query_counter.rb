# frozen_string_literal: true

module QueryCounter
  def count_queries(&block)
    count = 0
    counter = lambda do |*args|
      payload = args.last
      name = payload.is_a?(Hash) ? payload[:name] : nil
      unless %w[SCHEMA TRANSACTION].include?(name) || name&.to_s&.start_with?("CACHE")
        count += 1
      end
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end

RSpec.configure do |config|
  config.include QueryCounter
end
