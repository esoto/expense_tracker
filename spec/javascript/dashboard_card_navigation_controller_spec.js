import { Application } from "@hotwired/stimulus"
import DashboardCardNavigationController from "../../app/javascript/controllers/dashboard_card_navigation_controller"

describe("DashboardCardNavigationController", () => {
  let application
  let element

  beforeEach(() => {
    application = Application.start()
    application.register("dashboard-card-navigation", DashboardCardNavigationController)

    document.body.innerHTML = `
      <div data-controller="dashboard-card-navigation"
           data-dashboard-card-navigation-target="card"
           data-dashboard-card-navigation-period-value="month"
           data-dashboard-card-navigation-date-from-value="2024-01-01"
           data-dashboard-card-navigation-date-to-value="2024-01-31"
           data-dashboard-card-navigation-filter-type-value="dashboard_metric">
        <div class="metric-content">
          <h3>Este Mes</h3>
          <p>₡10,000</p>
        </div>
      </div>
    `

    element = document.querySelector('[data-controller="dashboard-card-navigation"]')
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
  })

  describe("Initialization", () => {
    it("sets up accessibility attributes", () => {
      expect(element.getAttribute("role")).toBe("button")
      expect(element.getAttribute("tabindex")).toBe("0")
      expect(element.getAttribute("aria-label")).toContain("Ver gastos")
    })

    it("sets correct ARIA label based on period", () => {
      // Test month period
      expect(element.getAttribute("aria-label")).toBe("Ver gastos del mes actual")

      // Test other periods
      const periods = {
        day: "Ver gastos de hoy",
        week: "Ver gastos de la semana actual",
        year: "Ver todos los gastos del año"
      }

      Object.entries(periods).forEach(([period, label]) => {
        element.dataset.dashboardCardNavigationPeriodValue = period
        const controller = application.getControllerForElementAndIdentifier(element, "dashboard-card-navigation")
        controller.setupAccessibility()
        expect(element.getAttribute("aria-label")).toBe(label)
      })
    })
  })

  describe("URL Building", () => {
    it("builds correct URL with period parameter", () => {
      const controller = application.getControllerForElementAndIdentifier(element, "dashboard-card-navigation")
      const url = controller.buildFilterUrl()

      expect(url).toContain("/expenses")
      expect(url).toContain("period=month")
      expect(url).toContain("filter_type=dashboard_metric")
      expect(url).toContain("scroll_to=expense_list")
    })

    it("includes date range parameters", () => {
      const controller = application.getControllerForElementAndIdentifier(element, "dashboard-card-navigation")
      const url = controller.buildFilterUrl()

      expect(url).toContain("date_from=2024-01-01")
      expect(url).toContain("date_to=2024-01-31")
    })

    it("handles missing optional parameters", () => {
      element.dataset.dashboardCardNavigationDateFromValue = ""
      element.dataset.dashboardCardNavigationDateToValue = ""
      
      const controller = application.getControllerForElementAndIdentifier(element, "dashboard-card-navigation")
      const url = controller.buildFilterUrl()

      expect(url).toContain("period=month")
      expect(url).not.toContain("date_from=")
      expect(url).not.toContain("date_to=")
    })
  })

  describe("Navigation", () => {
    let mockTurboVisit

    beforeEach(() => {
      // Mock Turbo.visit
      mockTurboVisit = jest.fn()
      window.Turbo = { visit: mockTurboVisit }
    })

    it("navigates on click", () => {
      const event = new MouseEvent("click", { bubbles: true })
      element.dispatchEvent(event)

      expect(mockTurboVisit).toHaveBeenCalledWith(
        expect.stringContaining("/expenses"),
        expect.objectContaining({
          action: "advance",
          frame: "_top"
        })
      )
    })

    it("prevents default action on click", () => {
      const event = new MouseEvent("click", { bubbles: true, cancelable: true })
      const preventDefault = jest.spyOn(event, "preventDefault")
      
      element.dispatchEvent(event)
      
      expect(preventDefault).toHaveBeenCalled()
    })

    it("shows loading state when navigating", () => {
      const controller = application.getControllerForElementAndIdentifier(element, "dashboard-card-navigation")
      controller.showLoadingState()

      expect(element.classList.contains("opacity-75")).toBe(true)
      expect(element.classList.contains("pointer-events-none")).toBe(true)
    })
  })

  describe("Keyboard Navigation", () => {
    let mockTurboVisit

    beforeEach(() => {
      mockTurboVisit = jest.fn()
      window.Turbo = { visit: mockTurboVisit }
    })

    it("navigates on Enter key", () => {
      const event = new KeyboardEvent("keydown", { key: "Enter", bubbles: true })
      element.dispatchEvent(event)

      expect(mockTurboVisit).toHaveBeenCalled()
    })

    it("navigates on Space key", () => {
      const event = new KeyboardEvent("keydown", { key: " ", bubbles: true })
      element.dispatchEvent(event)

      expect(mockTurboVisit).toHaveBeenCalled()
    })

    it("does not navigate on other keys", () => {
      const event = new KeyboardEvent("keydown", { key: "Tab", bubbles: true })
      element.dispatchEvent(event)

      expect(mockTurboVisit).not.toHaveBeenCalled()
    })
  })

  describe("Loading State", () => {
    it("adds loading spinner when navigating", () => {
      const controller = application.getControllerForElementAndIdentifier(element, "dashboard-card-navigation")
      controller.appendLoadingSpinner()

      const spinner = element.querySelector('[data-dashboard-card-navigation-target="loadingIndicator"]')
      expect(spinner).toBeTruthy()
      expect(spinner.innerHTML).toContain("animate-spin")
    })

    it("sets relative positioning when adding spinner", () => {
      const controller = application.getControllerForElementAndIdentifier(element, "dashboard-card-navigation")
      controller.appendLoadingSpinner()

      expect(element.style.position).toBe("relative")
    })

    it("shows existing loading indicator if present", () => {
      // Add a loading indicator to the DOM
      const loadingIndicator = document.createElement("div")
      loadingIndicator.dataset.dashboardCardNavigationTarget = "loadingIndicator"
      loadingIndicator.classList.add("hidden")
      element.appendChild(loadingIndicator)

      const controller = application.getControllerForElementAndIdentifier(element, "dashboard-card-navigation")
      controller.showLoadingState()

      expect(loadingIndicator.classList.contains("hidden")).toBe(false)
    })
  })

  describe("Mouse Events", () => {
    it("changes cursor on mouse enter", () => {
      const controller = application.getControllerForElementAndIdentifier(element, "dashboard-card-navigation")
      controller.handleMouseEnter()

      expect(element.style.cursor).toBe("pointer")
    })

    it("resets cursor on mouse leave", () => {
      const controller = application.getControllerForElementAndIdentifier(element, "dashboard-card-navigation")
      controller.handleMouseEnter()
      controller.handleMouseLeave()

      expect(element.style.cursor).toBe("default")
    })
  })

  describe("Edge Cases", () => {
    it("handles missing card target gracefully", () => {
      document.body.innerHTML = `
        <div data-controller="dashboard-card-navigation"
             data-dashboard-card-navigation-period-value="month">
          <p>No card target</p>
        </div>
      `
      
      const newElement = document.querySelector('[data-controller="dashboard-card-navigation"]')
      const controller = application.getControllerForElementAndIdentifier(newElement, "dashboard-card-navigation")
      
      // Should not throw error
      expect(() => controller.setupAccessibility()).not.toThrow()
      expect(() => controller.showLoadingState()).not.toThrow()
    })

    it("handles undefined period value", () => {
      element.dataset.dashboardCardNavigationPeriodValue = ""
      
      const controller = application.getControllerForElementAndIdentifier(element, "dashboard-card-navigation")
      const url = controller.buildFilterUrl()

      // Should still build valid URL without period
      expect(url).toContain("/expenses")
      expect(url).toContain("filter_type=dashboard_metric")
      expect(url).not.toContain("period=")
    })
  })
})