# frozen_string_literal: true

module QueryCounter
  def count_queries(&block)
    count = 0
    counter = ->(*_args) { count += 1 }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end

RSpec.configure do |config|
  config.include QueryCounter
end
