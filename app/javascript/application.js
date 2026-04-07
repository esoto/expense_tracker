// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import { Chart, registerables } from "chart.js"
// Note: chartjs-adapter-date-fns is intentionally NOT imported here.
// The bundled UMD build (.bundle.min.js) requires window.Chart to be defined globally,
// which is not the case when Chart.js is loaded as an ES module via import maps.
// None of the current chart controllers use type:'time' axes, so the adapter is unused.
// If a future chart needs time-scale support, import the adapter directly in that
// controller using the ESM build:
//   import "chartjs-adapter-date-fns"  (after pinning the +esm URL in importmap.rb)
// The +esm build from jsDelivr is tree-shakeable and requires explicit registration.
// Register all built-in chart types, scales, plugins, and elements so that chartkick
// and any Stimulus chart controllers can use line, bar, pie, doughnut, etc.
Chart.register(...registerables);
// Chartkick's ESM build detects Chart.js via `window.Chart`. When Chart.js is loaded
// as an ES module it does NOT attach to `window` automatically, so we must set it
// explicitly before importing chartkick.
window.Chart = Chart;
import "chartkick"
import AccessibilityManager from "utilities/accessibility_manager"

// Initialize AccessibilityManager once DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  window.accessibilityManager = new AccessibilityManager()
})
