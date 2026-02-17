import { Application } from "@hotwired/stimulus"
import FlashController from "../../app/javascript/controllers/flash_controller"

describe("FlashController", () => {
  let application
  let element

  beforeEach(() => {
    jest.useFakeTimers()

    document.body.innerHTML = `
      <div data-controller="flash"
           data-flash-delay-value="5000"
           role="alert"
           class="bg-emerald-50 border border-emerald-200 text-emerald-700 px-4 py-3 rounded-lg relative">
        <div class="flex items-center justify-between">
          <span class="block sm:inline">Test flash message</span>
          <button type="button"
                  data-action="click->flash#dismiss"
                  aria-label="Cerrar notificación"
                  class="ml-4 inline-flex text-emerald-500 hover:text-emerald-700">
            <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"></path>
            </svg>
          </button>
        </div>
      </div>
    `

    application = Application.start()
    application.register("flash", FlashController)
    element = document.querySelector('[data-controller="flash"]')
  })

  afterEach(() => {
    jest.useRealTimers()
    application.stop()
    document.body.innerHTML = ""
  })

  describe("connect", () => {
    it("sets up auto-dismiss timeout on connect", () => {
      // The controller should set a timeout when connected
      expect(setTimeout).toHaveBeenCalledWith(expect.any(Function), 5000)
    })
  })

  describe("auto-dismiss behavior", () => {
    it("adds opacity transition classes after delay", () => {
      jest.advanceTimersByTime(5000)

      expect(element.classList.contains("opacity-0")).toBe(true)
      expect(element.classList.contains("transition-opacity")).toBe(true)
      expect(element.classList.contains("duration-300")).toBe(true)
    })

    it("removes element from DOM after fade-out animation completes", () => {
      jest.advanceTimersByTime(5000) // trigger dismiss
      jest.advanceTimersByTime(300) // wait for fade-out animation

      expect(document.querySelector('[data-controller="flash"]')).toBeNull()
    })

    it("does not dismiss before the delay expires", () => {
      jest.advanceTimersByTime(4999)

      expect(element.classList.contains("opacity-0")).toBe(false)
      expect(document.querySelector('[data-controller="flash"]')).not.toBeNull()
    })
  })

  describe("manual dismiss", () => {
    it("dismisses immediately when close button is clicked", () => {
      const closeButton = element.querySelector('button[data-action="click->flash#dismiss"]')
      closeButton.click()

      expect(element.classList.contains("opacity-0")).toBe(true)
      expect(element.classList.contains("transition-opacity")).toBe(true)
    })

    it("removes element after animation when manually dismissed", () => {
      const closeButton = element.querySelector('button[data-action="click->flash#dismiss"]')
      closeButton.click()

      jest.advanceTimersByTime(300)

      expect(document.querySelector('[data-controller="flash"]')).toBeNull()
    })
  })

  describe("disconnect cleanup", () => {
    it("clears timeout when controller disconnects", () => {
      // Disconnect the controller by removing the element
      element.remove()

      // Verify clearTimeout was called (no lingering timers)
      expect(clearTimeout).toHaveBeenCalled()
    })
  })

  describe("custom delay value", () => {
    beforeEach(() => {
      document.body.innerHTML = `
        <div data-controller="flash"
             data-flash-delay-value="3000"
             role="alert"
             class="bg-rose-50 border border-rose-200 text-rose-700 px-4 py-3 rounded-lg relative">
          <div class="flex items-center justify-between">
            <span>Custom delay message</span>
            <button type="button"
                    data-action="click->flash#dismiss"
                    aria-label="Cerrar notificación">X</button>
          </div>
        </div>
      `

      application = Application.start()
      application.register("flash", FlashController)
    })

    it("uses the custom delay value for auto-dismiss", () => {
      expect(setTimeout).toHaveBeenCalledWith(expect.any(Function), 3000)
    })
  })

  describe("default delay value", () => {
    beforeEach(() => {
      document.body.innerHTML = `
        <div data-controller="flash"
             role="alert"
             class="bg-emerald-50 border border-emerald-200 text-emerald-700 px-4 py-3 rounded-lg relative">
          <span>Default delay message</span>
        </div>
      `

      application = Application.start()
      application.register("flash", FlashController)
    })

    it("falls back to 5000ms default when no delay value is specified", () => {
      expect(setTimeout).toHaveBeenCalledWith(expect.any(Function), 5000)
    })
  })
})
