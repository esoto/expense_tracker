import { Application } from "@hotwired/stimulus"
import InlineActionsController from "../../../app/javascript/controllers/inline_actions_controller"

describe("InlineActionsController", () => {
  let application
  let controller
  
  beforeEach(() => {
    document.body.innerHTML = `
      <tr data-controller="inline-actions"
          data-inline-actions-expense-id-value="1"
          data-inline-actions-current-status-value="pending">
        <td>
          <div data-inline-actions-target="actionsContainer" class="opacity-0 invisible">
            <button data-action="click->inline-actions#toggleCategoryDropdown">Category</button>
            <div data-inline-actions-target="categoryDropdown" class="hidden">
              <button data-action="click->inline-actions#selectCategory"
                      data-category-id="1"
                      data-category-name="Food">Food</button>
            </div>
            <button data-inline-actions-target="statusButton"
                    data-action="click->inline-actions#toggleStatus">Status</button>
            <button data-inline-actions-target="duplicateButton"
                    data-action="click->inline-actions#duplicateExpense">Duplicate</button>
            <button data-action="click->inline-actions#showDeleteConfirmation">Delete</button>
            <div data-inline-actions-target="deleteConfirmation" class="hidden">
              <button data-action="click->inline-actions#confirmDelete">Confirm</button>
              <button data-action="click->inline-actions#cancelDelete">Cancel</button>
            </div>
          </div>
        </td>
      </tr>
    `
    
    application = Application.start()
    application.register("inline-actions", InlineActionsController)
    
    controller = application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller="inline-actions"]'),
      "inline-actions"
    )
  })
  
  afterEach(() => {
    application.stop()
  })
  
  describe("#showActions", () => {
    it("shows the actions container", () => {
      const container = controller.actionsContainerTarget
      expect(container.classList.contains("opacity-0")).toBe(true)
      
      controller.showActions({ type: "focus" })
      
      expect(container.classList.contains("opacity-0")).toBe(false)
      expect(container.classList.contains("opacity-100")).toBe(true)
    })
    
    it("doesn't show actions in compact mode on mouseenter", () => {
      const table = document.createElement("table")
      table.classList.add("compact-mode")
      document.querySelector("tr").parentNode.appendChild(table)
      table.appendChild(document.querySelector("tr"))
      
      controller.showActions({ type: "mouseenter" })
      
      const container = controller.actionsContainerTarget
      expect(container.classList.contains("opacity-0")).toBe(true)
    })
  })
  
  describe("#toggleCategoryDropdown", () => {
    it("toggles the category dropdown visibility", () => {
      const dropdown = controller.categoryDropdownTarget
      const event = { preventDefault: () => {}, stopPropagation: () => {} }
      
      expect(dropdown.classList.contains("hidden")).toBe(true)
      
      controller.toggleCategoryDropdown(event)
      expect(dropdown.classList.contains("hidden")).toBe(false)
      
      controller.toggleCategoryDropdown(event)
      expect(dropdown.classList.contains("hidden")).toBe(true)
    })
  })
  
  describe("#showDeleteConfirmation", () => {
    it("shows the delete confirmation modal", () => {
      const confirmation = controller.deleteConfirmationTarget
      const event = { preventDefault: () => {}, stopPropagation: () => {} }
      
      expect(confirmation.classList.contains("hidden")).toBe(true)
      
      controller.showDeleteConfirmation(event)
      expect(confirmation.classList.contains("hidden")).toBe(false)
    })
  })
  
  describe("#cancelDelete", () => {
    it("hides the delete confirmation modal", () => {
      const confirmation = controller.deleteConfirmationTarget
      const event = { preventDefault: () => {} }
      
      confirmation.classList.remove("hidden")
      
      controller.cancelDelete(event)
      expect(confirmation.classList.contains("hidden")).toBe(true)
    })
  })
  
  describe("#positionDropdown", () => {
    it("positions dropdown to avoid viewport clipping", () => {
      const dropdown = controller.categoryDropdownTarget
      
      // Mock getBoundingClientRect
      dropdown.getBoundingClientRect = () => ({
        bottom: 100,
        right: 100
      })
      
      dropdown.parentElement.getBoundingClientRect = () => ({
        bottom: 100,
        right: 100
      })
      
      controller.positionDropdown(dropdown)
      
      expect(dropdown.style.zIndex).toBe("9999")
      expect(dropdown.style.position).toBe("absolute")
    })
  })
})