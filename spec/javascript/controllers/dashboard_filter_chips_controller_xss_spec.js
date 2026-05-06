/**
 * spec/javascript/controllers/dashboard_filter_chips_controller_xss_spec.js
 *
 * XSS hardening specs for H5: dashboard_filter_chips_controller#updateExpenseList (PER-543)
 *
 * NOTE: No JS test runner is configured (no package.json / Jest).
 * These specs are ready to run once Jest + jsdom are set up.
 */

import { Application } from "@hotwired/stimulus"
import DashboardFilterChipsController from "../../../app/javascript/controllers/dashboard_filter_chips_controller"

describe("DashboardFilterChipsController — XSS hardening (PER-543)", () => {
  const XSS_SCRIPT_TAG = '<script>window.__xss = true</script>'
  let application
  let element
  let controller

  beforeEach(() => {
    document.body.innerHTML = `
      <div data-controller="dashboard-filter-chips"
           data-dashboard-filter-chips-active-filters-value='{"categories":[],"statuses":[],"period":null}'
           data-dashboard-filter-chips-dashboard-url-value="/expenses/dashboard">
        <div data-dashboard-filter-chips-target="expenseContainer"></div>
      </div>
    `

    application = Application.start()
    application.register("dashboard-filter-chips", DashboardFilterChipsController)

    element = document.querySelector('[data-controller="dashboard-filter-chips"]')
    controller = application.getControllerForElementAndIdentifier(element, "dashboard-filter-chips")
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
    delete window.__xss
  })

  describe("updateExpenseList — H5", () => {
    it("does not execute inline scripts from server HTML via DOMParser", async () => {
      // H5: html comes from the server (fetch response.text()). Even when the server
      // returns HTML containing a script tag, DOMParser does not execute it.
      window.__xss = false

      await controller.updateExpenseList(
        `<div class="expense-row">Safe content</div>${XSS_SCRIPT_TAG}`
      )

      // Script should NOT have executed
      expect(window.__xss).toBe(false)
    })

    it("renders trusted server HTML content safely", async () => {
      await controller.updateExpenseList('<div class="expense-item">Expense #1</div>')

      const container = document.querySelector('[data-dashboard-filter-chips-target="expenseContainer"]')
      expect(container.querySelector('.expense-item')).not.toBeNull()
      expect(container.textContent).toContain('Expense #1')
    })

    it("replaces container children, not appending", async () => {
      const container = document.querySelector('[data-dashboard-filter-chips-target="expenseContainer"]')
      container.innerHTML = '<div class="old-content">old</div>'

      await controller.updateExpenseList('<div class="new-content">new</div>')

      expect(container.querySelector('.old-content')).toBeNull()
      expect(container.querySelector('.new-content')).not.toBeNull()
    })
  })

  describe("showError — additional XSS site in this file", () => {
    it("renders XSS payload in error message as text, not DOM elements", () => {
      const XSS_PAYLOAD = '<script>alert(1)</script>'
      controller.showError(XSS_PAYLOAD)

      const toasts = document.querySelectorAll('body > div[class*="fixed"]')
      const toast = toasts[toasts.length - 1]
      expect(toast).not.toBeNull()
      expect(toast.textContent).toContain(XSS_PAYLOAD)
      expect(document.querySelector('script')).toBeNull()
    })
  })
})
