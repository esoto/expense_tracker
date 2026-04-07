# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/utilities", under: "utilities"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin "services/i18n", to: "services/i18n.js"
pin "services/sync_cable_consumer", to: "services/sync_cable_consumer.js"
pin "services/error_messages", to: "services/error_messages.js"
pin "services/sync_error_classifier", to: "services/sync_error_classifier.js"
pin "services/sync_state_cache", to: "services/sync_state_cache.js"
pin "mixins/sync_channel_mixin", to: "mixins/sync_channel_mixin.js"
pin "mixins/sync_connection_mixin", to: "mixins/sync_connection_mixin.js"
pin "chart.js", to: "https://cdn.jsdelivr.net/npm/chart.js@4.4.0/+esm"
# chartjs-adapter-date-fns is NOT pinned here.
# The old .bundle.min.js variant is a UMD build that relies on window.Chart, which is
# never set when Chart.js loads as an ESM module. This caused a TypeError on page load.
# The +esm variant from jsDelivr hardcodes an import to chart.js@4.0.1, creating a
# duplicate Chart.js instance that breaks Chart.register().
# Resolution: none of our controllers use type:'time' chart axes, so the adapter is unused.
# To re-enable in the future, pin the ESM build AND ensure its internal import resolves
# to the same chart.js instance (requires a CDN that rewrites bare specifiers, e.g. esm.sh).
pin "chartkick", to: "https://cdn.jsdelivr.net/npm/chartkick@5.0.1/dist/chartkick.esm.js"
