import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["timePeriod", "category", "patternType"]

  connect() {
    console.log("Pattern Analytics Filters controller connected")
  }

  updateTimeRange(event) {
    this.updateFilters()
  }

  updateCategory(event) {
    this.updateFilters()
  }

  updatePatternType(event) {
    this.updateFilters()
  }

  updateFilters() {
    const params = new URLSearchParams()
    
    if (this.timePeriodTarget.value) {
      params.append("time_period", this.timePeriodTarget.value)
    }
    
    if (this.categoryTarget.value) {
      params.append("category_id", this.categoryTarget.value)
    }
    
    if (this.patternTypeTarget.value) {
      params.append("pattern_type", this.patternTypeTarget.value)
    }

    const url = `${window.location.pathname}?${params.toString()}`
    
    // Use Turbo to navigate and update the page
    Turbo.visit(url, { action: "replace" })
  }
}