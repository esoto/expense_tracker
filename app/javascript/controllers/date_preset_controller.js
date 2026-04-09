import { Controller } from "@hotwired/stimulus"

/**
 * Date Preset Controller
 * Quick date range selection pills for expense filtering.
 * Calculates date ranges for common periods and auto-submits the filter form.
 */
export default class extends Controller {
  static targets = ["preset", "startDate", "endDate", "customDates", "form"]

  select(event) {
    const period = event.currentTarget.dataset.datePresetPeriod
    this.highlightPreset(event.currentTarget)

    if (period === "custom") {
      this.customDatesTarget.classList.remove("hidden")
      return
    }

    this.customDatesTarget.classList.add("hidden")
    const { start, end } = this.calculateDates(period)
    this.startDateTarget.value = start
    this.endDateTarget.value = end
    this.formTarget.requestSubmit()
  }

  calculateDates(period) {
    const today = new Date()
    let start, end

    switch (period) {
      case "this_month":
        start = new Date(today.getFullYear(), today.getMonth(), 1)
        end = new Date(today.getFullYear(), today.getMonth() + 1, 0)
        break
      case "last_month":
        start = new Date(today.getFullYear(), today.getMonth() - 1, 1)
        end = new Date(today.getFullYear(), today.getMonth(), 0)
        break
      case "this_quarter": {
        const q = Math.floor(today.getMonth() / 3) * 3
        start = new Date(today.getFullYear(), q, 1)
        end = new Date(today.getFullYear(), q + 3, 0)
        break
      }
      case "year_to_date":
        start = new Date(today.getFullYear(), 0, 1)
        end = today
        break
      default:
        start = today
        end = today
    }

    return {
      start: this.formatDate(start),
      end: this.formatDate(end)
    }
  }

  formatDate(date) {
    return date.toISOString().split("T")[0]
  }

  highlightPreset(active) {
    this.presetTargets.forEach(p => {
      p.className = "px-3 py-1.5 rounded-full text-xs font-medium bg-slate-100 text-slate-700 hover:bg-slate-200 cursor-pointer transition-colors"
    })
    active.className = "px-3 py-1.5 rounded-full text-xs font-medium bg-teal-700 text-white shadow-sm cursor-pointer"
  }
}
