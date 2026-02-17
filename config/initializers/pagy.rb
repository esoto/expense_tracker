# frozen_string_literal: true

# Pagy configuration
# See https://ddnexus.github.io/pagy/
#
# Pagy v9+ uses frozen defaults. Application-specific pagination settings
# (items per page, etc.) are configured at the call site in controllers.
#
# Default items per page for this application: 50
# This is applied in the ExpensesController when creating Pagy instances.
