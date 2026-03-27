// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "chart.js"
// Note: chartjs-adapter-date-fns is intentionally NOT imported here.
// The bundled UMD build (.bundle.min.js) requires window.Chart to be defined globally,
// which is not the case when Chart.js is loaded as an ES module via import maps.
// None of the current chart controllers use type:'time' axes, so the adapter is unused.
// If a future chart needs time-scale support, import the adapter directly in that
// controller using the ESM build:
//   import "chartjs-adapter-date-fns"  (after pinning the +esm URL in importmap.rb)
import "chartkick"
