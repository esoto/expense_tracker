# frozen_string_literal: true

# Custom RSpec matcher for counting database queries
# Usage: expect { code }.to make_database_queries(count: 1..2)
RSpec::Matchers.define :make_database_queries do |count:|
  match do |block|
    @query_count = 0

    ActiveSupport::Notifications.subscribed(
      ->(*, payload) { @query_count += 1 unless payload[:name] == "SCHEMA" },
      "sql.active_record",
      &block
    )

    case count
    when Range
      count.include?(@query_count)
    when Integer
      @query_count == count
    else
      false
    end
  end

  failure_message do |block|
    "expected block to make #{count} database queries, but made #{@query_count}"
  end

  failure_message_when_negated do |block|
    "expected block not to make #{count} database queries, but it did"
  end

  supports_block_expectations
end
