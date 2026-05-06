/**
 * spec/javascript/controllers/dashboard_inline_actions_controller_xss_spec.js
 *
 * XSS hardening specs for H2: dashboard_inline_actions_controller#showToast (PER-543)
 *
 * NOTE: No JS test runner is configured (no package.json / Jest).
 * These specs are ready to run once Jest + jsdom are set up.
 */

import { Application } from "@hotwired/stimulus"
import DashboardInlineActionsController from "../../../app/javascript/controllers/dashboard_inline_actions_controller"

describe("DashboardInlineActionsController — XSS hardening (PER-543)", () => {
  const XSS_PAYLOAD = '<script>alert(1)</script>'
  const XSS_SVG     = '<svg/onload="window.__xss = true">'
  const XSS_IMG     = '<img src=x onerror="window.__xss = true">'
  const XSS_ENTITY  = '&#60;script&#62;alert(1)&#60;/script&#62;'
  let application
  let element
  let controller

  beforeEach(() => {
    // Sentinel: any DOM payload that gets *executed* (not just inserted as
    // text) sets this flag. Asserting it stays false defeats the
    // "jsdom-doesn't-run-scripts" vacuous-pass concern.
    window.__xss = false

    document.body.innerHTML = `
      <div data-controller="dashboard-inline-actions"
           data-dashboard-inline-actions-expense-id-value="42"
           data-dashboard-inline-actions-current-status-value="pending">
        <div data-dashboard-inline-actions-target="categoryDropdown" class="hidden"></div>
        <div data-dashboard-inline-actions-target="deleteConfirmation" class="hidden"></div>
      </div>
    `

    const csrfToken = document.createElement("meta")
    csrfToken.name = "csrf-token"
    csrfToken.content = "test-token"
    document.head.appendChild(csrfToken)

    application = Application.start()
    application.register("dashboard-inline-actions", DashboardInlineActionsController)

    element = document.querySelector('[data-controller="dashboard-inline-actions"]')
    controller = application.getControllerForElementAndIdentifier(element, "dashboard-inline-actions")
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
    document.head.innerHTML = ""
  })

  describe("showToast — H2", () => {
    it("renders XSS payload in message as text, not as DOM elements", () => {
      controller.showToast(XSS_PAYLOAD, "success")

      const toasts = document.querySelectorAll('body > div[class*="fixed"]')
      const toast = toasts[toasts.length - 1]
      expect(toast).not.toBeNull()
      expect(toast.textContent).toContain(XSS_PAYLOAD)
      expect(document.querySelector('script')).toBeNull()
    })

    it("does not inject script elements via message for error type", () => {
      controller.showToast(XSS_PAYLOAD, "error")
      expect(document.querySelectorAll('script').length).toBe(0)
    })

    it("renders complex XSS payload as literal text for info type", () => {
      const complex = '<img src=x onerror=alert(1)>'
      controller.showToast(complex, "info")

      // No img elements injected
      expect(document.querySelector('img')).toBeNull()
    })

    it("close button uses addEventListener, not onclick attribute", () => {
      controller.showToast("message", "success")

      const toasts = document.querySelectorAll('body > div[class*="fixed"]')
      const toast = toasts[toasts.length - 1]
      const closeBtn = toast.querySelector('button')
      expect(closeBtn).not.toBeNull()
      expect(closeBtn.getAttribute('onclick')).toBeNull()
    })

    it("sentinel: <svg/onload> payload does not execute", () => {
      controller.showToast(XSS_SVG, "warning")
      expect(window.__xss).toBe(false)
    })

    it("sentinel: <img onerror> payload does not execute", () => {
      controller.showToast(XSS_IMG, "warning")
      expect(window.__xss).toBe(false)
    })

    it("HTML-entity-encoded payload renders as literal text (no double-decode)", () => {
      controller.showToast(XSS_ENTITY, "info")

      const toasts = document.querySelectorAll('body > div[class*="fixed"]')
      const toast = toasts[toasts.length - 1]
      expect(toast.textContent).toContain(XSS_ENTITY)
      expect(toast.querySelector('script')).toBeNull()
    })
  })
})
