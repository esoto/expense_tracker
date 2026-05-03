/**
 * spec/javascript/controllers/undo_manager_controller_xss_spec.js
 *
 * XSS hardening specs for H3: undo_manager_controller#showToast (PER-543)
 *
 * NOTE: No JS test runner is configured (no package.json / Jest).
 * These specs are ready to run once Jest + jsdom are set up.
 */

import { Application } from "@hotwired/stimulus"
import UndoManagerController from "../../../app/javascript/controllers/undo_manager_controller"

describe("UndoManagerController — XSS hardening (PER-543)", () => {
  const XSS_PAYLOAD = '<script>alert(1)</script>'
  let application
  let element
  let controller

  beforeEach(() => {
    document.body.innerHTML = `
      <div data-controller="undo-manager"
           data-undo-manager-undo-id-value="99"
           data-undo-manager-time-remaining-value="300">
        <span data-undo-manager-target="message"></span>
        <span data-undo-manager-target="timer">300</span>
        <button data-undo-manager-target="undoButton">Deshacer</button>
        <div data-undo-manager-target="progressBar"></div>
      </div>
    `

    application = Application.start()
    application.register("undo-manager", UndoManagerController)

    element = document.querySelector('[data-controller="undo-manager"]')
    controller = application.getControllerForElementAndIdentifier(element, "undo-manager")
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
    if (controller && controller.timerInterval) clearInterval(controller.timerInterval)
  })

  describe("showToast — H3", () => {
    it("renders XSS payload in success toast as text, not as DOM elements", () => {
      controller.showToast(XSS_PAYLOAD, "success")

      const toasts = document.querySelectorAll('body > div[style*="fixed"]')
      const toast = toasts[toasts.length - 1]
      expect(toast).not.toBeNull()
      expect(toast.textContent).toContain(XSS_PAYLOAD)
      expect(document.querySelector('script')).toBeNull()
    })

    it("renders XSS payload in error toast as text, not as DOM elements", () => {
      controller.showToast(XSS_PAYLOAD, "error")
      expect(document.querySelectorAll('script').length).toBe(0)
    })

    it("does not inject img elements via XSS payload", () => {
      controller.showToast('<img src=x onerror=alert(1)>', "success")
      expect(document.querySelector('img')).toBeNull()
    })
  })
})
