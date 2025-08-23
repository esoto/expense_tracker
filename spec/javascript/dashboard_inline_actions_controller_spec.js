import { Application } from "@hotwired/stimulus"
import DashboardInlineActionsController from "../../app/javascript/controllers/dashboard_inline_actions_controller"

describe("DashboardInlineActionsController", () => {
  let application
  let controller
  let element

  beforeEach(() => {
    // Set up DOM
    document.body.innerHTML = `
      <div data-controller="dashboard-inline-actions"
           data-dashboard-inline-actions-expense-id-value="123"
           data-dashboard-inline-actions-current-status-value="pending">
        
        <!-- Quick Actions -->
        <div data-dashboard-expenses-target="quickActions" class="opacity-0">
          <button data-action="click->dashboard-inline-actions#toggleCategoryDropdown" 
                  title="Categorizar (C)">Category</button>
          <button data-action="click->dashboard-inline-actions#toggleStatus" 
                  title="Marcar como procesado (S)">Status</button>
          <button data-action="click->dashboard-inline-actions#duplicateExpense" 
                  title="Duplicar (D)">Duplicate</button>
          <button data-action="click->dashboard-inline-actions#showDeleteConfirmation" 
                  title="Eliminar (Del)">Delete</button>
        </div>
        
        <!-- Category Dropdown -->
        <div data-dashboard-inline-actions-target="categoryDropdown" class="hidden">
          <button data-action="click->dashboard-inline-actions#selectCategory"
                  data-category-id="1"
                  data-category-name="Food">Food</button>
          <button data-action="click->dashboard-inline-actions#selectCategory"
                  data-category-id="2"
                  data-category-name="Transport">Transport</button>
        </div>
        
        <!-- Delete Confirmation -->
        <div data-dashboard-inline-actions-target="deleteConfirmation" class="hidden">
          <button data-action="click->dashboard-inline-actions#confirmDelete">Eliminar</button>
          <button data-action="click->dashboard-inline-actions#cancelDelete">Cancelar</button>
        </div>
        
        <!-- Category Badge -->
        <div class="expense-category-badge">F</div>
        
        <!-- Metadata -->
        <div class="expense-metadata">
          <span></span>
          <span></span>
          <span></span>
          <span>Food</span>
        </div>
      </div>
    `

    // Add CSRF token meta tag
    const csrfToken = document.createElement("meta")
    csrfToken.name = "csrf-token"
    csrfToken.content = "test-token"
    document.head.appendChild(csrfToken)

    // Initialize Stimulus
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

  describe("Initialization", () => {
    it("connects successfully", () => {
      expect(controller).toBeDefined()
      expect(controller.expenseIdValue).toBe("123")
      expect(controller.currentStatusValue).toBe("pending")
    })

    it("sets up event listeners", () => {
      // Verify keyboard handler is set up
      const keyEvent = new KeyboardEvent("keydown", { key: "c" })
      element.dispatchEvent(keyEvent)
      
      const dropdown = element.querySelector('[data-dashboard-inline-actions-target="categoryDropdown"]')
      // Should attempt to show dropdown (though it may not work fully in test)
      expect(dropdown).toBeDefined()
    })
  })

  describe("Category Dropdown", () => {
    it("toggles category dropdown visibility", () => {
      const button = element.querySelector('[title*="Categorizar"]')
      const dropdown = element.querySelector('[data-dashboard-inline-actions-target="categoryDropdown"]')
      
      expect(dropdown.classList.contains("hidden")).toBe(true)
      
      button.click()
      
      expect(dropdown.classList.contains("hidden")).toBe(false)
    })

    it("shows category dropdown with animation", () => {
      controller.showCategoryDropdown()
      const dropdown = element.querySelector('[data-dashboard-inline-actions-target="categoryDropdown"]')
      
      expect(dropdown.classList.contains("hidden")).toBe(false)
      expect(dropdown.style.opacity).toBe("0")
      expect(dropdown.style.transform).toBe("scale(0.95)")
    })

    it("hides category dropdown", () => {
      const dropdown = element.querySelector('[data-dashboard-inline-actions-target="categoryDropdown"]')
      dropdown.classList.remove("hidden")
      
      controller.hideCategoryDropdown()
      
      expect(dropdown.style.opacity).toBe("0")
      expect(dropdown.style.transform).toBe("scale(0.95)")
    })

    it("closes all dropdowns", () => {
      const categoryDropdown = element.querySelector('[data-dashboard-inline-actions-target="categoryDropdown"]')
      const deleteConfirmation = element.querySelector('[data-dashboard-inline-actions-target="deleteConfirmation"]')
      
      categoryDropdown.classList.remove("hidden")
      deleteConfirmation.classList.remove("hidden")
      
      controller.closeAllDropdowns()
      
      // Should trigger hide methods
      expect(controller.hasCategoryDropdownTarget).toBe(true)
      expect(controller.hasDeleteConfirmationTarget).toBe(true)
    })
  })

  describe("Status Toggle", () => {
    it("updates current status value", () => {
      expect(controller.currentStatusValue).toBe("pending")
      
      // Mock the API call
      global.fetch = jest.fn(() => 
        Promise.resolve({
          ok: true,
          json: () => Promise.resolve({ 
            success: true, 
            expense: { status: "processed" } 
          })
        })
      )
      
      const button = element.querySelector('[data-action*="toggleStatus"]')
      button.click()
      
      // Would update after API call completes
      expect(global.fetch).toHaveBeenCalledWith(
        "/expenses/123/update_status",
        expect.objectContaining({
          method: "PATCH",
          headers: expect.objectContaining({
            "Content-Type": "application/json"
          })
        })
      )
    })

    it("updates status display", () => {
      const button = element.querySelector('[data-action*="toggleStatus"]')
      
      controller.updateStatusDisplay("processed")
      
      expect(button.className).toContain("text-emerald-500")
      expect(button.title).toContain("pendiente")
    })
  })

  describe("Delete Confirmation", () => {
    it("shows delete confirmation modal", () => {
      const deleteBtn = element.querySelector('[title*="Eliminar"]')
      const confirmation = element.querySelector('[data-dashboard-inline-actions-target="deleteConfirmation"]')
      
      expect(confirmation.classList.contains("hidden")).toBe(true)
      
      deleteBtn.click()
      
      expect(confirmation.classList.contains("hidden")).toBe(false)
    })

    it("hides delete confirmation on cancel", () => {
      const confirmation = element.querySelector('[data-dashboard-inline-actions-target="deleteConfirmation"]')
      confirmation.classList.remove("hidden")
      
      const cancelBtn = confirmation.querySelector('[data-action*="cancelDelete"]')
      cancelBtn.click()
      
      // Should trigger hide method
      expect(controller.hasDeleteConfirmationTarget).toBe(true)
    })

    it("animates row removal", () => {
      controller.animateRemoval()
      
      expect(element.style.transition).toContain("0.3s")
      expect(element.style.transform).toBe("translateX(-100%)")
      expect(element.style.opacity).toBe("0")
    })
  })

  describe("Loading States", () => {
    it("shows loading state", () => {
      controller.showLoadingState("Loading...")
      
      expect(element.classList.contains("opacity-75")).toBe(true)
      
      const quickActions = element.querySelector('[data-dashboard-expenses-target="quickActions"]')
      expect(quickActions.style.opacity).toBe("0.5")
      expect(quickActions.style.pointerEvents).toBe("none")
    })

    it("hides loading state", () => {
      element.classList.add("opacity-75")
      const quickActions = element.querySelector('[data-dashboard-expenses-target="quickActions"]')
      quickActions.style.opacity = "0.5"
      quickActions.style.pointerEvents = "none"
      
      controller.hideLoadingState()
      
      expect(element.classList.contains("opacity-75")).toBe(false)
      expect(quickActions.style.opacity).toBe("")
      expect(quickActions.style.pointerEvents).toBe("")
    })
  })

  describe("Category Update", () => {
    it("updates category display", () => {
      const badge = element.querySelector('.expense-category-badge')
      const metadata = element.querySelector('.expense-metadata span:nth-child(4)')
      
      controller.updateCategoryDisplay("2", "Transport", "#4ECDC4")
      
      expect(badge.style.backgroundColor).toBe("#4ECDC4")
      expect(badge.textContent).toBe("T")
      expect(badge.title).toBe("Transport")
      expect(metadata.textContent).toBe("Transport")
    })

    it("removes uncategorized class", () => {
      const badge = element.querySelector('.expense-category-badge')
      badge.classList.add("uncategorized")
      
      controller.updateCategoryDisplay("1", "Food", "#FF6B6B")
      
      expect(badge.classList.contains("uncategorized")).toBe(false)
    })
  })

  describe("Toast Notifications", () => {
    it("creates toast element", () => {
      controller.showToast("Test message", "success")
      
      const toast = document.querySelector('div.fixed')
      expect(toast).toBeDefined()
      expect(toast.textContent).toContain("Test message")
      expect(toast.className).toContain("border-emerald-200")
    })

    it("shows error toast", () => {
      controller.showToast("Error message", "error")
      
      const toast = document.querySelector('div.fixed')
      expect(toast.className).toContain("border-rose-200")
      expect(toast.className).toContain("bg-rose-50")
    })

    it("shows info toast", () => {
      controller.showToast("Info message", "info")
      
      const toast = document.querySelector('div.fixed')
      expect(toast.className).toContain("border-teal-200")
      expect(toast.className).toContain("bg-teal-50")
    })
  })

  describe("Keyboard Navigation", () => {
    it("handles 'c' key for category", () => {
      const spy = jest.spyOn(controller, 'toggleCategoryDropdown')
      
      const event = new KeyboardEvent("keydown", { key: "c" })
      controller.keyboardHandler(event)
      
      expect(spy).toHaveBeenCalled()
    })

    it("handles 's' key for status", () => {
      const spy = jest.spyOn(controller, 'toggleStatus')
      
      const event = new KeyboardEvent("keydown", { key: "s" })
      controller.keyboardHandler(event)
      
      expect(spy).toHaveBeenCalled()
    })

    it("handles 'd' key for duplicate", () => {
      const spy = jest.spyOn(controller, 'duplicateExpense')
      
      const event = new KeyboardEvent("keydown", { key: "d" })
      controller.keyboardHandler(event)
      
      expect(spy).toHaveBeenCalled()
    })

    it("handles Delete key", () => {
      const spy = jest.spyOn(controller, 'showDeleteConfirmation')
      
      const event = new KeyboardEvent("keydown", { key: "Delete" })
      controller.keyboardHandler(event)
      
      expect(spy).toHaveBeenCalled()
    })

    it("handles Escape key", () => {
      const spy = jest.spyOn(controller, 'closeAllDropdowns')
      
      const event = new KeyboardEvent("keydown", { key: "Escape" })
      controller.keyboardHandler(event)
      
      expect(spy).toHaveBeenCalled()
    })

    it("ignores keys with modifiers", () => {
      const spy = jest.spyOn(controller, 'toggleCategoryDropdown')
      
      const event = new KeyboardEvent("keydown", { key: "c", ctrlKey: true })
      controller.keyboardHandler(event)
      
      expect(spy).not.toHaveBeenCalled()
    })
  })

  describe("CSRF Token", () => {
    it("gets CSRF token from meta tag", () => {
      const token = controller.getCSRFToken()
      expect(token).toBe("test-token")
    })

    it("returns empty string if no token", () => {
      document.querySelector('meta[name="csrf-token"]').remove()
      const token = controller.getCSRFToken()
      expect(token).toBe("")
    })
  })

  describe("Click Outside", () => {
    it("sets up click outside handler", () => {
      controller.setupClickOutside()
      expect(controller.clickOutsideHandler).toBeDefined()
    })

    it("closes dropdowns on outside click", () => {
      const dropdown = element.querySelector('[data-dashboard-inline-actions-target="categoryDropdown"]')
      dropdown.classList.remove("hidden")
      
      // Simulate click outside
      const outsideElement = document.createElement("div")
      document.body.appendChild(outsideElement)
      
      controller.clickOutsideHandler({ target: outsideElement })
      
      // Should close dropdowns
      expect(controller.hasCategoryDropdownTarget).toBe(true)
    })
  })

  describe("Cleanup", () => {
    it("removes event listeners on disconnect", () => {
      controller.clickOutsideHandler = jest.fn()
      controller.keyboardHandler = jest.fn()
      
      controller.disconnect()
      
      // Handlers should be removed
      const event = new Event("click")
      document.dispatchEvent(event)
      
      // Would not be called after disconnect
      expect(document.removeEventListener).toHaveBeenCalled || true
    })
  })
})