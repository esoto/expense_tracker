import { Application } from "@hotwired/stimulus"
import MobileNavController from "../../app/javascript/controllers/mobile_nav_controller"

describe("MobileNavController", () => {
  let application
  let controller
  let element

  beforeEach(() => {
    document.body.innerHTML = `
      <nav data-controller="mobile-nav">
        <div class="flex justify-between items-center">
          <a href="/">Expense Tracker</a>
          <div class="hidden md:flex items-center space-x-4">
            <a href="/expenses">Gastos</a>
            <a href="/expenses/dashboard">Dashboard</a>
          </div>
          <button type="button"
                  class="md:hidden"
                  aria-label="Abrir menú de navegación"
                  aria-expanded="false"
                  aria-controls="mobile-menu"
                  data-mobile-nav-target="button"
                  data-action="click->mobile-nav#toggle">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"></path>
            </svg>
          </button>
        </div>
        <div id="mobile-menu"
             class="hidden md:hidden"
             data-mobile-nav-target="menu"
             role="menu"
             aria-label="Menú de navegación móvil">
          <a href="/expenses/dashboard" role="menuitem">Dashboard</a>
          <a href="/expenses" role="menuitem">Gastos</a>
          <a href="/bulk_categorizations" role="menuitem">Categorizar</a>
          <a href="/expenses/new" role="menuitem">Nuevo Gasto</a>
        </div>
      </nav>
    `

    element = document.querySelector('[data-controller="mobile-nav"]')
    application = Application.start()
    application.register("mobile-nav", MobileNavController)
    controller = application.getControllerForElementAndIdentifier(element, "mobile-nav")
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
  })

  describe("initialization", () => {
    it("starts with menu closed", () => {
      const menu = element.querySelector('[data-mobile-nav-target="menu"]')
      expect(menu.classList.contains("hidden")).toBe(true)
    })

    it("sets aria-expanded to false on connect", () => {
      const button = element.querySelector('[data-mobile-nav-target="button"]')
      expect(button.getAttribute("aria-expanded")).toBe("false")
    })

    it("identifies button and menu targets", () => {
      expect(controller.buttonTarget).toBeTruthy()
      expect(controller.menuTarget).toBeTruthy()
    })
  })

  describe("toggle", () => {
    it("opens the menu when closed", () => {
      controller.toggle()

      const menu = element.querySelector('[data-mobile-nav-target="menu"]')
      expect(menu.classList.contains("hidden")).toBe(false)
    })

    it("closes the menu when open", () => {
      controller.open()
      controller.toggle()

      const menu = element.querySelector('[data-mobile-nav-target="menu"]')
      expect(menu.classList.contains("hidden")).toBe(true)
    })

    it("updates aria-expanded to true when opened", () => {
      controller.toggle()

      const button = element.querySelector('[data-mobile-nav-target="button"]')
      expect(button.getAttribute("aria-expanded")).toBe("true")
    })

    it("updates aria-expanded to false when closed", () => {
      controller.open()
      controller.toggle()

      const button = element.querySelector('[data-mobile-nav-target="button"]')
      expect(button.getAttribute("aria-expanded")).toBe("false")
    })
  })

  describe("open", () => {
    it("shows the mobile menu", () => {
      controller.open()

      const menu = element.querySelector('[data-mobile-nav-target="menu"]')
      expect(menu.classList.contains("hidden")).toBe(false)
    })

    it("sets aria-expanded to true", () => {
      controller.open()

      const button = element.querySelector('[data-mobile-nav-target="button"]')
      expect(button.getAttribute("aria-expanded")).toBe("true")
    })

    it("sets isOpen flag to true", () => {
      controller.open()
      expect(controller.isOpen).toBe(true)
    })

    it("focuses the first link in the menu", () => {
      controller.open()

      const firstLink = element.querySelector('[data-mobile-nav-target="menu"] a')
      expect(document.activeElement).toBe(firstLink)
    })
  })

  describe("close", () => {
    beforeEach(() => {
      controller.open()
    })

    it("hides the mobile menu", () => {
      controller.close()

      const menu = element.querySelector('[data-mobile-nav-target="menu"]')
      expect(menu.classList.contains("hidden")).toBe(true)
    })

    it("sets aria-expanded to false", () => {
      controller.close()

      const button = element.querySelector('[data-mobile-nav-target="button"]')
      expect(button.getAttribute("aria-expanded")).toBe("false")
    })

    it("sets isOpen flag to false", () => {
      controller.close()
      expect(controller.isOpen).toBe(false)
    })
  })

  describe("click outside", () => {
    it("closes the menu when clicking outside", () => {
      controller.open()

      // Simulate click outside the nav element
      const outsideElement = document.createElement("div")
      document.body.appendChild(outsideElement)
      const event = new Event("click", { bubbles: true })
      outsideElement.dispatchEvent(event)

      expect(controller.isOpen).toBe(false)
      const menu = element.querySelector('[data-mobile-nav-target="menu"]')
      expect(menu.classList.contains("hidden")).toBe(true)
    })

    it("does not close the menu when clicking inside the nav", () => {
      controller.open()

      const insideElement = element.querySelector("a")
      const event = new Event("click", { bubbles: true })
      insideElement.dispatchEvent(event)

      expect(controller.isOpen).toBe(true)
    })

    it("does not close the menu if already closed", () => {
      // Menu is already closed by default
      const outsideElement = document.createElement("div")
      document.body.appendChild(outsideElement)
      const event = new Event("click", { bubbles: true })
      outsideElement.dispatchEvent(event)

      const menu = element.querySelector('[data-mobile-nav-target="menu"]')
      expect(menu.classList.contains("hidden")).toBe(true)
    })
  })

  describe("keyboard navigation", () => {
    it("closes the menu on Escape key", () => {
      controller.open()

      const event = new KeyboardEvent("keydown", {
        key: "Escape",
        bubbles: true
      })
      document.dispatchEvent(event)

      expect(controller.isOpen).toBe(false)
      const menu = element.querySelector('[data-mobile-nav-target="menu"]')
      expect(menu.classList.contains("hidden")).toBe(true)
    })

    it("returns focus to the hamburger button on Escape", () => {
      controller.open()

      const event = new KeyboardEvent("keydown", {
        key: "Escape",
        bubbles: true
      })
      document.dispatchEvent(event)

      const button = element.querySelector('[data-mobile-nav-target="button"]')
      expect(document.activeElement).toBe(button)
    })

    it("does not respond to Escape when menu is closed", () => {
      const button = element.querySelector('[data-mobile-nav-target="button"]')
      button.focus()

      const event = new KeyboardEvent("keydown", {
        key: "Escape",
        bubbles: true
      })
      document.dispatchEvent(event)

      // Should remain in its current state (closed)
      expect(controller.isOpen).toBe(false)
    })

    it("does not respond to other keys", () => {
      controller.open()

      const event = new KeyboardEvent("keydown", {
        key: "Enter",
        bubbles: true
      })
      document.dispatchEvent(event)

      // Menu should still be open
      expect(controller.isOpen).toBe(true)
    })
  })

  describe("disconnect", () => {
    it("removes event listeners on disconnect", () => {
      controller.open()
      controller.disconnect()

      // After disconnect, clicking outside should NOT close the menu
      const outsideElement = document.createElement("div")
      document.body.appendChild(outsideElement)
      const event = new Event("click", { bubbles: true })
      outsideElement.dispatchEvent(event)

      // isOpen state should still be true since listener was removed
      expect(controller.isOpen).toBe(true)
    })
  })

  describe("accessibility", () => {
    it("has aria-controls pointing to the mobile menu id", () => {
      const button = element.querySelector('[data-mobile-nav-target="button"]')
      expect(button.getAttribute("aria-controls")).toBe("mobile-menu")
    })

    it("has aria-label on the hamburger button", () => {
      const button = element.querySelector('[data-mobile-nav-target="button"]')
      expect(button.getAttribute("aria-label")).toBe("Abrir menú de navegación")
    })

    it("has role=menu on the mobile menu container", () => {
      const menu = element.querySelector('[data-mobile-nav-target="menu"]')
      expect(menu.getAttribute("role")).toBe("menu")
    })

    it("has role=menuitem on menu links", () => {
      const menuItems = element.querySelectorAll('[role="menuitem"]')
      expect(menuItems.length).toBeGreaterThan(0)
    })

    it("has aria-hidden=true on the hamburger SVG icon", () => {
      const svg = element.querySelector('[data-mobile-nav-target="button"] svg')
      expect(svg.getAttribute("aria-hidden")).toBe("true")
    })
  })
})
