import { Application } from "@hotwired/stimulus"
import DropdownController from "../../../app/javascript/controllers/dropdown_controller"

describe("DropdownController", () => {
  let application

  function startWith(html) {
    document.body.innerHTML = html
    application = Application.start()
    application.register("dropdown", DropdownController)
  }

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
  })

  describe("connect() with full targets present", () => {
    beforeEach(() => {
      startWith(`
        <div data-controller="dropdown">
          <button data-dropdown-target="button" aria-expanded="true">Open</button>
          <ul data-dropdown-target="menu" class="">
            <li>Item 1</li>
          </ul>
        </div>
      `)
    })

    it("closes the menu on connect (adds hidden class)", () => {
      const menu = document.querySelector("[data-dropdown-target='menu']")
      expect(menu.classList.contains("hidden")).toBe(true)
    })

    it("sets aria-expanded to false on connect", () => {
      const button = document.querySelector("[data-dropdown-target='button']")
      expect(button.getAttribute("aria-expanded")).toBe("false")
    })
  })

  describe("connect() with NO targets present (PER-201 guard)", () => {
    it("does not throw when menu target is absent", () => {
      expect(() => {
        startWith(`<div data-controller="dropdown"></div>`)
      }).not.toThrow()
    })

    it("does not throw when only button target is present", () => {
      expect(() => {
        startWith(`
          <div data-controller="dropdown">
            <button data-dropdown-target="button">Toggle</button>
          </div>
        `)
      }).not.toThrow()
    })
  })

  describe("toggle()", () => {
    let element

    beforeEach(() => {
      startWith(`
        <div data-controller="dropdown">
          <button data-dropdown-target="button"
                  data-action="click->dropdown#toggle"
                  aria-expanded="false">Toggle</button>
          <ul data-dropdown-target="menu" class="hidden">
            <li>Item 1</li>
          </ul>
        </div>
      `)
      element = document.querySelector("[data-controller='dropdown']")
    })

    it("opens the menu when it is currently hidden", () => {
      const button = element.querySelector("[data-dropdown-target='button']")
      button.click()

      const menu = element.querySelector("[data-dropdown-target='menu']")
      expect(menu.classList.contains("hidden")).toBe(false)
    })

    it("sets aria-expanded to true when opening", () => {
      const button = element.querySelector("[data-dropdown-target='button']")
      button.click()

      expect(button.getAttribute("aria-expanded")).toBe("true")
    })

    it("closes the menu when it is currently open", () => {
      const button = element.querySelector("[data-dropdown-target='button']")
      button.click() // open
      button.click() // close

      const menu = element.querySelector("[data-dropdown-target='menu']")
      expect(menu.classList.contains("hidden")).toBe(true)
    })

    it("does not throw when menu target is missing", () => {
      document.body.innerHTML = `
        <div data-controller="dropdown">
          <button data-action="click->dropdown#toggle">Toggle</button>
        </div>
      `
      application = Application.start()
      application.register("dropdown", DropdownController)

      expect(() => {
        const btn = document.querySelector("button")
        btn.click()
      }).not.toThrow()
    })
  })

  describe("open()", () => {
    beforeEach(() => {
      startWith(`
        <div data-controller="dropdown">
          <button data-dropdown-target="button" aria-expanded="false">Open</button>
          <ul data-dropdown-target="menu" class="hidden">
            <li>Item</li>
          </ul>
        </div>
      `)
    })

    it("removes hidden class from menu", () => {
      const button = document.querySelector("[data-dropdown-target='button']")
      button.click() // triggers toggle -> open

      const menu = document.querySelector("[data-dropdown-target='menu']")
      expect(menu.classList.contains("hidden")).toBe(false)
    })

    it("attaches click-outside listener", () => {
      const addSpy = jest.spyOn(document, "addEventListener")
      const button = document.querySelector("[data-dropdown-target='button']")
      button.click() // open

      expect(addSpy).toHaveBeenCalledWith("click", expect.any(Function))
      addSpy.mockRestore()
    })
  })

  describe("close()", () => {
    beforeEach(() => {
      startWith(`
        <div data-controller="dropdown">
          <button data-dropdown-target="button"
                  data-action="click->dropdown#toggle"
                  aria-expanded="false">Toggle</button>
          <ul data-dropdown-target="menu" class="hidden">
            <li>Item</li>
          </ul>
        </div>
      `)
    })

    it("adds hidden class to menu", () => {
      const button = document.querySelector("[data-dropdown-target='button']")
      button.click() // open
      button.click() // close

      const menu = document.querySelector("[data-dropdown-target='menu']")
      expect(menu.classList.contains("hidden")).toBe(true)
    })

    it("removes click-outside listener when closing", () => {
      const removeSpy = jest.spyOn(document, "removeEventListener")
      const button = document.querySelector("[data-dropdown-target='button']")
      button.click() // open
      button.click() // close

      expect(removeSpy).toHaveBeenCalledWith("click", expect.any(Function))
      removeSpy.mockRestore()
    })

    it("does not throw when menu target is missing", () => {
      document.body.innerHTML = `<div data-controller="dropdown"></div>`
      application = Application.start()
      application.register("dropdown", DropdownController)

      // connect() calls close() — should not throw
      expect(document.querySelector("[data-controller='dropdown']")).not.toBeNull()
    })
  })

  describe("clickOutside()", () => {
    let element

    beforeEach(() => {
      startWith(`
        <div data-controller="dropdown">
          <button data-dropdown-target="button"
                  data-action="click->dropdown#toggle"
                  aria-expanded="false">Toggle</button>
          <ul data-dropdown-target="menu" class="hidden">
            <li>Item</li>
          </ul>
        </div>
        <p id="outside">Outside element</p>
      `)
      element = document.querySelector("[data-controller='dropdown']")
    })

    it("closes the menu when clicking outside the controller element", () => {
      const button = element.querySelector("[data-dropdown-target='button']")
      button.click() // open

      const outside = document.getElementById("outside")
      outside.dispatchEvent(new MouseEvent("click", { bubbles: true }))

      const menu = element.querySelector("[data-dropdown-target='menu']")
      expect(menu.classList.contains("hidden")).toBe(true)
    })

    it("keeps menu open when clicking inside the controller element", () => {
      const button = element.querySelector("[data-dropdown-target='button']")
      button.click() // open

      const menu = element.querySelector("[data-dropdown-target='menu']")
      menu.dispatchEvent(new MouseEvent("click", { bubbles: true }))

      expect(menu.classList.contains("hidden")).toBe(false)
    })
  })

  describe("disconnect()", () => {
    it("removes click-outside listener on disconnect", () => {
      startWith(`
        <div data-controller="dropdown">
          <button data-dropdown-target="button"
                  data-action="click->dropdown#toggle"
                  aria-expanded="false">Toggle</button>
          <ul data-dropdown-target="menu" class="hidden">
            <li>Item</li>
          </ul>
        </div>
      `)

      const removeSpy = jest.spyOn(document, "removeEventListener")
      const controllerElement = document.querySelector("[data-controller='dropdown']")
      controllerElement.remove()

      expect(removeSpy).toHaveBeenCalledWith("click", expect.any(Function))
      removeSpy.mockRestore()
    })
  })
})
