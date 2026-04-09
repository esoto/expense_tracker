import { Controller } from "@hotwired/stimulus"

/**
 * Date Preset Controller
 * Quick date range selection pills for expense filtering.
 * Calculates date ranges for common periods and auto-submits the filter form.
 * Custom date fields are hidden unless "Personalizado" is selected or dates are in URL.
 */
export default class extends Controller {
  static targets = ["preset", "startDate", "endDate", "customDates", "form"]

  connect() {
    // If URL has date params that don't match the default "this_month" preset,
    // detect and highlight the correct preset or show custom dates
    this.syncPresetFromUrl()
  }

  select(event) {
    const period = event.currentTarget.dataset.datePresetPeriod
    this.highlightPreset(event.currentTarget)

    if (period === "custom") {
      this.showCustomDates()
      return
    }

    this.hideCustomDates()
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
    const pad = n => String(n).padStart(2, "0")
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
  }

  highlightPreset(active) {
    this.presetTargets.forEach(p => {
      p.className = "px-3 py-1.5 rounded-full text-xs font-medium bg-slate-100 text-slate-700 hover:bg-slate-200 cursor-pointer transition-colors"
    })
    active.className = "px-3 py-1.5 rounded-full text-xs font-medium bg-teal-700 text-white shadow-sm cursor-pointer"
  }

  showCustomDates() {
    if (this.hasCustomDatesTarget) {
      this.customDatesTarget.classList.remove("hidden")
    }
  }

  hideCustomDates() {
    if (this.hasCustomDatesTarget) {
      this.customDatesTarget.classList.add("hidden")
    }
  }

  /**
   * On connect, check URL params to determine which preset should be active.
   * If dates don't match any preset, highlight "Personalizado" and show date fields.
   */
  syncPresetFromUrl() {
    const params = new URLSearchParams(window.location.search)
    const startDate = params.get("start_date")
    const endDate = params.get("end_date")

    if (!startDate && !endDate) return

    // Check if dates match any preset
    const presets = ["this_month", "last_month", "this_quarter", "year_to_date"]
    let matched = false

    for (const period of presets) {
      const { start, end } = this.calculateDates(period)
      if (startDate === start && endDate === end) {
        const btn = this.presetTargets.find(p => p.dataset.datePresetPeriod === period)
        if (btn) this.highlightPreset(btn)
        matched = true
        break
      }
    }

    if (!matched) {
      // Dates don't match any preset — highlight "Personalizado" and show date fields
      const customBtn = this.presetTargets.find(p => p.dataset.datePresetPeriod === "custom")
      if (customBtn) this.highlightPreset(customBtn)
      this.showCustomDates()
    }
  }
}
