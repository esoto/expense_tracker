// spec/javascript/controllers/bulk_actions_controller_spec.js
import { Application } from "@hotwired/stimulus"
import BulkActionsController from "../../../app/javascript/controllers/bulk_actions_controller"

describe("BulkActionsController", () => {
  let application
  let controller
  let element

  function buildDOM({ conflictCount = 3, allCanResolve = true } = {}) {
    const rows = Array.from({ length: conflictCount }, (_, i) => {
      const checkbox = allCanResolve
        ? `<input type="checkbox"
                  data-bulk-actions-target="checkbox"
                  data-action="change->bulk-actions#checkboxChanged"
                  data-conflict-id="${i + 1}"
                  class="h-4 w-4">`
        : ""
      return `<tr id="conflict_${i + 1}"><td>${checkbox}</td></tr>`
    }).join("")

    document.body.innerHTML = `
      <div data-controller="bulk-actions"
           data-bulk-actions-url-value="/sync_conflicts/bulk_resolve">

        <button data-action="click->bulk-actions#selectAll">
          Seleccionar todo
        </button>

        <button data-bulk-actions-target="resolveButton"
                data-action="click->bulk-actions#bulkResolve"
                class="hidden"
                disabled>
          Resolver seleccionados
        </button>

        <table>
          <thead>
            <tr>
              <th>
                <input type="checkbox"
                       data-bulk-actions-target="selectAll"
                       data-action="change->bulk-actions#selectAll">
              </th>
            </tr>
          </thead>
          <tbody>${rows}</tbody>
        </table>
      </div>
    `

    element = document.querySelector('[data-controller="bulk-actions"]')
    application = Application.start()
    application.register("bulk-actions", BulkActionsController)
    controller = application.getControllerForElementAndIdentifier(element, "bulk-actions")
  }

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
  })

  describe("connect()", () => {
    beforeEach(() => buildDOM())

    it("initializes with resolve button hidden and disabled", () => {
      const resolveButton = element.querySelector('[data-bulk-actions-target="resolveButton"]')
      expect(resolveButton.classList.contains("hidden")).toBe(true)
      expect(resolveButton.disabled).toBe(true)
    })
  })

  describe("selectAll() — toolbar button", () => {
    beforeEach(() => buildDOM())

    it("checks all row checkboxes when none are checked", () => {
      const button = element.querySelector('[data-action="click->bulk-actions#selectAll"]')
      button.click()

      const checkboxes = element.querySelectorAll('[data-bulk-actions-target="checkbox"]')
      checkboxes.forEach(cb => expect(cb.checked).toBe(true))
    })

    it("unchecks all row checkboxes when all are already checked", () => {
      const checkboxes = element.querySelectorAll('[data-bulk-actions-target="checkbox"]')
      checkboxes.forEach(cb => { cb.checked = true })

      const button = element.querySelector('[data-action="click->bulk-actions#selectAll"]')
      button.click()

      checkboxes.forEach(cb => expect(cb.checked).toBe(false))
    })

    it("shows and enables the resolve button after selecting all", () => {
      const button = element.querySelector('[data-action="click->bulk-actions#selectAll"]')
      button.click()

      const resolveButton = element.querySelector('[data-bulk-actions-target="resolveButton"]')
      expect(resolveButton.classList.contains("hidden")).toBe(false)
      expect(resolveButton.disabled).toBe(false)
    })

    it("hides resolve button after deselecting all", () => {
      const checkboxes = element.querySelectorAll('[data-bulk-actions-target="checkbox"]')
      checkboxes.forEach(cb => { cb.checked = true })

      const button = element.querySelector('[data-action="click->bulk-actions#selectAll"]')
      button.click()

      const resolveButton = element.querySelector('[data-bulk-actions-target="resolveButton"]')
      expect(resolveButton.classList.contains("hidden")).toBe(true)
    })

    it("updates header selectAll checkbox to reflect all-checked state", () => {
      const button = element.querySelector('[data-action="click->bulk-actions#selectAll"]')
      button.click()

      const headerCheckbox = element.querySelector('[data-bulk-actions-target="selectAll"]')
      expect(headerCheckbox.checked).toBe(true)
    })

    it("includes selected count in resolve button text", () => {
      const button = element.querySelector('[data-action="click->bulk-actions#selectAll"]')
      button.click()

      const resolveButton = element.querySelector('[data-bulk-actions-target="resolveButton"]')
      expect(resolveButton.textContent).toContain("3")
    })
  })

  describe("selectAll() — header checkbox", () => {
    beforeEach(() => buildDOM())

    it("checks all row checkboxes when header checkbox is checked", () => {
      const headerCheckbox = element.querySelector('[data-bulk-actions-target="selectAll"]')
      headerCheckbox.checked = true
      headerCheckbox.dispatchEvent(new Event("change"))

      const checkboxes = element.querySelectorAll('[data-bulk-actions-target="checkbox"]')
      checkboxes.forEach(cb => expect(cb.checked).toBe(true))
    })

    it("unchecks all row checkboxes when header checkbox is unchecked", () => {
      const checkboxes = element.querySelectorAll('[data-bulk-actions-target="checkbox"]')
      checkboxes.forEach(cb => { cb.checked = true })

      const headerCheckbox = element.querySelector('[data-bulk-actions-target="selectAll"]')
      headerCheckbox.checked = false
      headerCheckbox.dispatchEvent(new Event("change"))

      checkboxes.forEach(cb => expect(cb.checked).toBe(false))
    })

    it("enables resolve button when header checkbox is checked", () => {
      const headerCheckbox = element.querySelector('[data-bulk-actions-target="selectAll"]')
      headerCheckbox.checked = true
      headerCheckbox.dispatchEvent(new Event("change"))

      const resolveButton = element.querySelector('[data-bulk-actions-target="resolveButton"]')
      expect(resolveButton.classList.contains("hidden")).toBe(false)
      expect(resolveButton.disabled).toBe(false)
    })
  })

  describe("checkboxChanged() — individual row checkbox", () => {
    beforeEach(() => buildDOM())

    it("shows resolve button when one checkbox is checked", () => {
      const firstCheckbox = element.querySelector('[data-bulk-actions-target="checkbox"]')
      firstCheckbox.checked = true
      firstCheckbox.dispatchEvent(new Event("change"))

      const resolveButton = element.querySelector('[data-bulk-actions-target="resolveButton"]')
      expect(resolveButton.classList.contains("hidden")).toBe(false)
      expect(resolveButton.disabled).toBe(false)
    })

    it("hides resolve button when all checkboxes are unchecked", () => {
      const checkboxes = element.querySelectorAll('[data-bulk-actions-target="checkbox"]')

      // Check all then uncheck all
      checkboxes.forEach(cb => {
        cb.checked = true
        cb.dispatchEvent(new Event("change"))
      })
      checkboxes.forEach(cb => {
        cb.checked = false
        cb.dispatchEvent(new Event("change"))
      })

      const resolveButton = element.querySelector('[data-bulk-actions-target="resolveButton"]')
      expect(resolveButton.classList.contains("hidden")).toBe(true)
    })

    it("sets header checkbox to indeterminate when some but not all are checked", () => {
      const checkboxes = element.querySelectorAll('[data-bulk-actions-target="checkbox"]')
      checkboxes[0].checked = true
      checkboxes[0].dispatchEvent(new Event("change"))

      const headerCheckbox = element.querySelector('[data-bulk-actions-target="selectAll"]')
      expect(headerCheckbox.indeterminate).toBe(true)
      expect(headerCheckbox.checked).toBe(false)
    })

    it("sets header checkbox to checked when all row checkboxes are checked", () => {
      const checkboxes = element.querySelectorAll('[data-bulk-actions-target="checkbox"]')
      checkboxes.forEach(cb => {
        cb.checked = true
        cb.dispatchEvent(new Event("change"))
      })

      const headerCheckbox = element.querySelector('[data-bulk-actions-target="selectAll"]')
      expect(headerCheckbox.checked).toBe(true)
      expect(headerCheckbox.indeterminate).toBe(false)
    })
  })

  describe("selectedConflictIds()", () => {
    beforeEach(() => buildDOM())

    it("returns empty array when nothing is checked", () => {
      expect(controller.selectedConflictIds()).toEqual([])
    })

    it("returns conflict IDs for checked checkboxes", () => {
      const checkboxes = element.querySelectorAll('[data-bulk-actions-target="checkbox"]')
      checkboxes[0].checked = true
      checkboxes[2].checked = true

      const ids = controller.selectedConflictIds()
      expect(ids).toContain("1")
      expect(ids).toContain("3")
      expect(ids).not.toContain("2")
    })
  })

  describe("with no resolvable conflicts", () => {
    beforeEach(() => buildDOM({ allCanResolve: false }))

    it("has no checkbox targets when rows have no checkboxes", () => {
      expect(controller.checkboxTargets).toHaveLength(0)
    })

    it("does not show resolve button after clicking selectAll button", () => {
      const button = element.querySelector('[data-action="click->bulk-actions#selectAll"]')
      button.click()

      const resolveButton = element.querySelector('[data-bulk-actions-target="resolveButton"]')
      expect(resolveButton.classList.contains("hidden")).toBe(true)
    })
  })
})
