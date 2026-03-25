# frozen_string_literal: true

# Enable ExpenseFilterService result caching.
# The cache key is derived from filter parameters and the Expense table's
# maximum updated_at timestamp, so it automatically invalidates whenever
# any expense record changes (see Expense#CACHE_RELEVANT_ATTRIBUTES callbacks).
Rails.application.config.expense_filter_cache_enabled = true
