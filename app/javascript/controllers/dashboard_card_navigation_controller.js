import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { shouldSuppressShortcut } from "../utilities/keyboard_shortcut_helpers"

/**
 * Dashboard Card Navigation Controller
 * Handles clickable metric cards that navigate to filtered expense views
 * Supports keyboard navigation and loading states
 */
export default class extends Controller {
  static targets = ["loadingIndicator"]
  static values = {
    period: String,
    dateFrom: String,
    dateTo: String,
    filterType: { type: String, default: "dashboard_metric" }
  }

  connect() {
    // The element itself is the card, no need for a separate target
    this.setupAccessibility()
    this.bindKeyboardEvents()
  }

  disconnect() {
    this.unbindKeyboardEvents()
  }

  /**
   * Setup ARIA attributes for accessibility
   */
  setupAccessibility() {
    // Only set attributes if they're not already present
    if (!this.element.hasAttribute("role")) {
      this.element.setAttribute("role", "button")
    }
    if (!this.element.hasAttribute("tabindex")) {
      this.element.setAttribute("tabindex", "0")
    }
    if (!this.element.hasAttribute("aria-label")) {
      this.element.setAttribute("aria-label", this.getAriaLabel())
    }
  }

  /**
   * Get appropriate ARIA label based on period
   */
  getAriaLabel() {
    const periodLabels = {
      year: "Ver todos los gastos del año",
      month: "Ver gastos del mes actual",
      week: "Ver gastos de la semana actual",
      day: "Ver gastos de hoy"
    }
    return periodLabels[this.periodValue] || "Ver gastos filtrados"
  }

  /**
   * Bind keyboard events for accessibility
   */
  bindKeyboardEvents() {
    this.keydownHandler = this.handleKeydown.bind(this)
    this.element.addEventListener("keydown", this.keydownHandler)
  }

  /**
   * Unbind keyboard events on disconnect
   */
  unbindKeyboardEvents() {
    if (this.keydownHandler) {
      this.element.removeEventListener("keydown", this.keydownHandler)
    }
  }

  /**
   * Handle keyboard navigation (Enter and Space keys)
   */
  handleKeydown(event) {
    // Don't fire shortcuts when typing in form fields
    if (shouldSuppressShortcut(event)) return

    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      this.navigate(event)
    }
  }

  /**
   * Navigate to filtered expense view when card is clicked
   */
  navigate(event) {
    event.preventDefault()
    
    // Show loading state
    this.showLoadingState()
    
    // Build URL with filter parameters
    const url = this.buildFilterUrl()
    
    // Navigate using Turbo for smooth transition
    Turbo.visit(url, {
      action: "advance",
      frame: "_top"
    })
  }

  /**
   * Build the filter URL with appropriate parameters
   */
  buildFilterUrl() {
    const params = new URLSearchParams()
    
    // Add period filter
    if (this.periodValue) {
      params.append("period", this.periodValue)
    }
    
    // Add date range filters
    if (this.dateFromValue) {
      params.append("date_from", this.dateFromValue)
    }
    
    if (this.dateToValue) {
      params.append("date_to", this.dateToValue)
    }
    
    // Add filter type to identify source
    params.append("filter_type", this.filterTypeValue)
    
    // Add scroll target
    params.append("scroll_to", "expense_list")
    
    // Build complete URL
    const baseUrl = "/expenses"
    return `${baseUrl}?${params.toString()}`
  }

  /**
   * Show loading state on the card
   */
  showLoadingState() {
    // Add loading class to card
    this.element.classList.add("opacity-75", "pointer-events-none")
    
    // Add loading spinner if target exists
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.remove("hidden")
    } else {
      // Create and append loading spinner
      this.appendLoadingSpinner()
    }
  }

  /**
   * Create and append a loading spinner to the card
   */
  appendLoadingSpinner() {
    const spinner = document.createElement("div")
    spinner.className = "absolute inset-0 flex items-center justify-center bg-white/80 rounded-xl"
    spinner.innerHTML = `
      <svg class="animate-spin h-8 w-8 text-teal-700" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
    `
    spinner.dataset.dashboardCardNavigationTarget = "loadingIndicator"
    
    // Make card position relative if not already
    if (!this.element.style.position || this.element.style.position === "static") {
      this.element.style.position = "relative"
    }
    this.element.appendChild(spinner)
  }

  /**
   * Handle hover state for visual feedback
   */
  handleMouseEnter() {
    this.element.style.cursor = "pointer"
  }

  /**
   * Handle mouse leave state
   */
  handleMouseLeave() {
    this.element.style.cursor = "default"
  }
}