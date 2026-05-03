/**
 * spec/javascript/controllers/dashboard_expenses_controller_xss_spec.js
 *
 * XSS hardening specs for H1: dashboard_expenses_controller#showToast (PER-543)
 *
 * NOTE: No JS test runner is configured (no package.json / Jest).
 * These specs are ready to run once Jest + jsdom are set up.
 */

import { Application } from "@hotwired/stimulus"
import DashboardExpensesController from "../../../app/javascript/controllers/dashboard_expenses_controller"

describe("DashboardExpensesController — XSS hardening (PER-543)", () => {
  const XSS_PAYLOAD = '<script>alert(1)</script>'
  let application
  let element
  let controller

  beforeEach(() => {
    document.body.innerHTML = `
      <div data-controller="dashboard-expenses"
           data-dashboard-expenses-view-mode-value="compact"
           data-dashboard-expenses-selected-ids-value="[]">
        <div data-dashboard-expenses-target="container"></div>
      </div>
    `

    const csrfToken = document.createElement("meta")
    csrfToken.name = "csrf-token"
    csrfToken.content = "test-token"
    document.head.appendChild(csrfToken)

    application = Application.start()
    application.register("dashboard-expenses", DashboardExpensesController)

    element = document.querySelector('[data-controller="dashboard-expenses"]')
    controller = application.getControllerForElementAndIdentifier(element, "dashboard-expenses")
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
    document.head.innerHTML = ""
  })

  describe("showToast — H1", () => {
    it("renders XSS payload in message as text, not as DOM elements", () => {
      controller.showToast(XSS_PAYLOAD, "success")

      const toast = document.querySelector('#toast-container > div')
      expect(toast).not.toBeNull()

      // The XSS payload must appear as text content, not as a parsed script element
      expect(toast.textContent).toContain(XSS_PAYLOAD)
      expect(document.querySelector('script')).toBeNull()
    })

    it("does not inject script elements via message", () => {
      controller.showToast(XSS_PAYLOAD, "error")

      // No script elements should exist in the document
      expect(document.querySelectorAll('script').length).toBe(0)
    })

    it("renders complex XSS payload as literal text", () => {
      const complex = '<img src=x onerror=alert(1)><b>injected</b>'
      controller.showToast(complex, "info")

      const toast = document.querySelector('#toast-container > div')
      expect(toast).not.toBeNull()
      expect(toast.textContent).toContain(complex)
      expect(document.querySelector('img')).toBeNull()
    })

    it("uses addEventListener instead of onclick for close button", () => {
      controller.showToast("test message", "success")

      const container = document.getElementById('toast-container')
      const closeButton = container.querySelector('button')
      expect(closeButton).not.toBeNull()
      // No inline onclick attribute should be present
      expect(closeButton.getAttribute('onclick')).toBeNull()
    })
  })
})
