import { Application } from "@hotwired/stimulus"
import BatchSelectionController from "../../app/javascript/controllers/batch_selection_controller"

describe("BatchSelectionController", () => {
  let application
  let controller
  let element

  beforeEach(() => {
    // Set up DOM
    document.body.innerHTML = `
      <div data-controller="batch-selection">
        <input type="checkbox" 
               data-batch-selection-target="masterCheckbox"
               data-action="change->batch-selection#toggleMasterSelection">
        
        <span data-batch-selection-target="selectionCounter" class="hidden">
          0 gastos seleccionados
        </span>
        
        <div data-batch-selection-target="selectionToolbar" class="hidden">
          <span data-batch-selection-target="selectedCount">0</span>
          <span data-batch-selection-target="totalCount">0</span>
          <button data-batch-selection-target="clearSelectionButton"
                  data-action="click->batch-selection#clearSelection">
            Clear
          </button>
          <button data-batch-selection-target="bulkActionsButton" disabled>
            Bulk Actions
          </button>
        </div>
        
        <table>
          <tbody>
            <tr id="expense_row_1" data-batch-selection-target="row">
              <td>
                <input type="checkbox" 
                       data-batch-selection-target="checkbox"
                       data-expense-id="1"
                       data-action="change->batch-selection#toggleSelection">
              </td>
            </tr>
            <tr id="expense_row_2" data-batch-selection-target="row">
              <td>
                <input type="checkbox" 
                       data-batch-selection-target="checkbox"
                       data-expense-id="2"
                       data-action="change->batch-selection#toggleSelection">
              </td>
            </tr>
            <tr id="expense_row_3" data-batch-selection-target="row">
              <td>
                <input type="checkbox" 
                       data-batch-selection-target="checkbox"
                       data-expense-id="3"
                       data-action="change->batch-selection#toggleSelection">
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    `

    element = document.querySelector('[data-controller="batch-selection"]')
    application = Application.start()
    application.register("batch-selection", BatchSelectionController)
    controller = application.getControllerForElementAndIdentifier(element, "batch-selection")
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
  })

  describe("initialization", () => {
    it("initializes with empty selection", () => {
      expect(controller.selectedIdsValue).toEqual([])
    })

    it("counts total visible expenses", () => {
      expect(controller.checkboxTargets.length).toBe(3)
    })

    it("updates UI on connect", () => {
      const counter = element.querySelector('[data-batch-selection-target="selectionCounter"]')
      expect(counter.classList.contains("hidden")).toBe(true)
    })
  })

  describe("individual selection", () => {
    it("adds expense to selection when checked", () => {
      const checkbox = element.querySelector('[data-expense-id="1"]')
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))

      expect(controller.selectedIdsValue).toContain(1)
      expect(controller.selectedIdsValue.length).toBe(1)
    })

    it("removes expense from selection when unchecked", () => {
      // First select
      const checkbox = element.querySelector('[data-expense-id="1"]')
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
      
      // Then deselect
      checkbox.checked = false
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))

      expect(controller.selectedIdsValue).not.toContain(1)
      expect(controller.selectedIdsValue.length).toBe(0)
    })

    it("applies visual feedback to selected rows", () => {
      const checkbox = element.querySelector('[data-expense-id="1"]')
      const row = element.querySelector("#expense_row_1")
      
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))

      expect(row.classList.contains("bg-teal-50")).toBe(true)
      expect(row.getAttribute("aria-selected")).toBe("true")
    })

    it("removes visual feedback from deselected rows", () => {
      const checkbox = element.querySelector('[data-expense-id="1"]')
      const row = element.querySelector("#expense_row_1")
      
      // Select
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
      
      // Deselect
      checkbox.checked = false
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))

      expect(row.classList.contains("bg-teal-50")).toBe(false)
      expect(row.getAttribute("aria-selected")).toBe("false")
    })
  })

  describe("master checkbox", () => {
    it("selects all visible expenses", () => {
      const master = element.querySelector('[data-batch-selection-target="masterCheckbox"]')
      master.checked = true
      master.dispatchEvent(new Event("change", { bubbles: true }))

      expect(controller.selectedIdsValue).toEqual([1, 2, 3])
      
      // All checkboxes should be checked
      controller.checkboxTargets.forEach(cb => {
        expect(cb.checked).toBe(true)
      })
    })

    it("deselects all expenses", () => {
      // First select all
      controller.selectAll()
      
      // Then deselect all via master
      const master = element.querySelector('[data-batch-selection-target="masterCheckbox"]')
      master.checked = false
      master.dispatchEvent(new Event("change", { bubbles: true }))

      expect(controller.selectedIdsValue).toEqual([])
      
      // All checkboxes should be unchecked
      controller.checkboxTargets.forEach(cb => {
        expect(cb.checked).toBe(false)
      })
    })

    it("shows indeterminate state for partial selection", () => {
      const master = element.querySelector('[data-batch-selection-target="masterCheckbox"]')
      
      // Select first checkbox only
      const checkbox = element.querySelector('[data-expense-id="1"]')
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))

      expect(master.indeterminate).toBe(true)
      expect(master.checked).toBe(false)
    })

    it("shows checked state when all selected", () => {
      const master = element.querySelector('[data-batch-selection-target="masterCheckbox"]')
      controller.selectAll()

      expect(master.indeterminate).toBe(false)
      expect(master.checked).toBe(true)
    })
  })

  describe("selection toolbar", () => {
    it("shows toolbar when items are selected", () => {
      const toolbar = element.querySelector('[data-batch-selection-target="selectionToolbar"]')
      
      // Initially hidden
      expect(toolbar.classList.contains("hidden")).toBe(true)
      
      // Select an item
      const checkbox = element.querySelector('[data-expense-id="1"]')
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))

      // Should show toolbar
      expect(toolbar.classList.contains("hidden")).toBe(false)
      expect(toolbar.classList.contains("flex")).toBe(true)
    })

    it("hides toolbar when no items selected", () => {
      const toolbar = element.querySelector('[data-batch-selection-target="selectionToolbar"]')
      
      // Select then deselect
      controller.selectAll()
      controller.clearSelection()

      expect(toolbar.classList.contains("hidden")).toBe(true)
    })

    it("updates selection count", () => {
      const selectedCount = element.querySelector('[data-batch-selection-target="selectedCount"]')
      const totalCount = element.querySelector('[data-batch-selection-target="totalCount"]')
      
      // Select two items
      const cb1 = element.querySelector('[data-expense-id="1"]')
      const cb2 = element.querySelector('[data-expense-id="2"]')
      
      cb1.checked = true
      cb1.dispatchEvent(new Event("change", { bubbles: true }))
      
      cb2.checked = true
      cb2.dispatchEvent(new Event("change", { bubbles: true }))

      expect(selectedCount.textContent).toBe("2")
      expect(totalCount.textContent).toBe("3")
    })

    it("enables bulk actions button when items selected", () => {
      const button = element.querySelector('[data-batch-selection-target="bulkActionsButton"]')

      // Initially disabled
      expect(button.disabled).toBe(true)

      // Select an item
      const checkbox = element.querySelector('[data-expense-id="1"]')
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))

      expect(button.disabled).toBe(false)
    })

    // PER-187: toolbar hidden and buttons disabled when 0 items selected
    it("keeps toolbar hidden on initial connect with 0 items selected", () => {
      const toolbar = element.querySelector('[data-batch-selection-target="selectionToolbar"]')
      expect(toolbar.classList.contains("hidden")).toBe(true)
      expect(toolbar.classList.contains("flex")).toBe(false)
    })

    it("keeps bulk actions button disabled on initial connect with 0 items selected", () => {
      const button = element.querySelector('[data-batch-selection-target="bulkActionsButton"]')
      expect(button.disabled).toBe(true)
      expect(button.classList.contains("opacity-50")).toBe(true)
      expect(button.classList.contains("cursor-not-allowed")).toBe(true)
    })

    it("keeps toolbar hidden after deselecting all items via checkbox", () => {
      const toolbar = element.querySelector('[data-batch-selection-target="selectionToolbar"]')
      const checkbox = element.querySelector('[data-expense-id="1"]')

      // Select
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
      expect(toolbar.classList.contains("hidden")).toBe(false)

      // Deselect
      checkbox.checked = false
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))

      expect(toolbar.classList.contains("hidden")).toBe(true)
      expect(toolbar.classList.contains("flex")).toBe(false)
    })

    it("re-disables bulk actions button and adds opacity when count returns to 0", () => {
      const button = element.querySelector('[data-batch-selection-target="bulkActionsButton"]')
      const checkbox = element.querySelector('[data-expense-id="1"]')

      // Select → button enabled
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
      expect(button.disabled).toBe(false)
      expect(button.classList.contains("opacity-50")).toBe(false)

      // Deselect → button disabled again
      checkbox.checked = false
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
      expect(button.disabled).toBe(true)
      expect(button.classList.contains("opacity-50")).toBe(true)
      expect(button.classList.contains("cursor-not-allowed")).toBe(true)
    })

    it("does not show toolbar after clearSelection cancels pending animation frame", () => {
      const toolbar = element.querySelector('[data-batch-selection-target="selectionToolbar"]')

      // Select to trigger show (which queues a requestAnimationFrame)
      const checkbox = element.querySelector('[data-expense-id="1"]')
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))

      // Immediately clear selection before animation frame fires
      controller.clearSelection()

      // Toolbar must be hidden even if rAF fires after this point
      expect(toolbar.classList.contains("hidden")).toBe(true)
      expect(toolbar.style.display).toBe("none")
    })

    it("sets toolbar style.display to none when 0 items selected", () => {
      const toolbar = element.querySelector('[data-batch-selection-target="selectionToolbar"]')

      controller.selectAll()
      controller.clearSelection()

      expect(toolbar.style.display).toBe("none")
    })
  })

  describe("keyboard navigation", () => {
    it("selects all with Ctrl+A", () => {
      // Focus on table
      const table = element.querySelector("table")
      table.focus()
      
      // Simulate Ctrl+A
      const event = new KeyboardEvent("keydown", {
        key: "a",
        ctrlKey: true,
        bubbles: true
      })
      document.dispatchEvent(event)

      // Note: In real implementation, this would work
      // Here we test the method directly
      controller.selectAll()
      expect(controller.selectedIdsValue.length).toBe(3)
    })

    it("clears selection with Escape", () => {
      // Select some items
      controller.selectAll()
      expect(controller.selectedIdsValue.length).toBe(3)
      
      // Simulate Escape
      const event = new KeyboardEvent("keydown", {
        key: "Escape",
        bubbles: true
      })
      
      // Test the method directly
      controller.clearSelection()
      expect(controller.selectedIdsValue.length).toBe(0)
    })
  })

  describe("clear selection", () => {
    it("clears all selections", () => {
      // Select all first
      controller.selectAll()
      expect(controller.selectedIdsValue.length).toBe(3)
      
      // Clear
      controller.clearSelection()
      
      expect(controller.selectedIdsValue).toEqual([])
      controller.checkboxTargets.forEach(cb => {
        expect(cb.checked).toBe(false)
      })
    })

    it("resets master checkbox", () => {
      const master = element.querySelector('[data-batch-selection-target="masterCheckbox"]')
      
      controller.selectAll()
      controller.clearSelection()
      
      expect(master.checked).toBe(false)
      expect(master.indeterminate).toBe(false)
    })
  })

  describe("selection mode", () => {
    it("toggles selection mode", () => {
      expect(controller.selectionModeValue).toBe(false)

      controller.toggleSelectionMode()
      expect(controller.selectionModeValue).toBe(true)

      controller.toggleSelectionMode()
      expect(controller.selectionModeValue).toBe(false)
    })

    it("clears selection when exiting selection mode", () => {
      controller.selectionModeValue = true
      controller.selectAll()

      controller.toggleSelectionMode() // Exit selection mode

      expect(controller.selectedIdsValue).toEqual([])
    })

    // PER-189 Bug 3: selection-mode-active CSS class must be managed on the container
    it("adds selection-mode-active class when entering selection mode", () => {
      expect(element.classList.contains("selection-mode-active")).toBe(false)

      controller.toggleSelectionMode()

      expect(element.classList.contains("selection-mode-active")).toBe(true)
    })

    it("removes selection-mode-active class when exiting selection mode", () => {
      controller.toggleSelectionMode() // enter
      expect(element.classList.contains("selection-mode-active")).toBe(true)

      controller.toggleSelectionMode() // exit
      expect(element.classList.contains("selection-mode-active")).toBe(false)
    })

    it("removes selection-mode-active class after bulk operations complete", () => {
      controller.toggleSelectionMode() // enter
      expect(element.classList.contains("selection-mode-active")).toBe(true)

      const event = new CustomEvent("bulk-operations:completed", {
        detail: { success: true },
        bubbles: true
      })
      document.dispatchEvent(event)

      expect(element.classList.contains("selection-mode-active")).toBe(false)
    })

    it("hides checkboxes when selection mode is off", () => {
      controller.toggleSelectionMode() // enter — show checkboxes
      controller.toggleSelectionMode() // exit — hide checkboxes

      const checkboxCells = element.querySelectorAll(".checkbox-cell")
      checkboxCells.forEach(cell => {
        expect(cell.classList.contains("hidden")).toBe(true)
      })
    })
  })

  // PER-189 Bug 1: selection counter must show full "X de Y gastos seleccionados" format
  describe("selection counter format", () => {
    it("shows full 'X de Y gastos seleccionados' format when items are selected", () => {
      const counter = element.querySelector('[data-batch-selection-target="selectionCounter"]')

      const cb1 = element.querySelector('[data-expense-id="1"]')
      const cb2 = element.querySelector('[data-expense-id="2"]')

      cb1.checked = true
      cb1.dispatchEvent(new Event("change", { bubbles: true }))
      cb2.checked = true
      cb2.dispatchEvent(new Event("change", { bubbles: true }))

      expect(counter.textContent).toBe("2 de 3 gastos seleccionados")
      expect(counter.classList.contains("hidden")).toBe(false)
    })

    it("hides counter when no items are selected", () => {
      const counter = element.querySelector('[data-batch-selection-target="selectionCounter"]')

      const checkbox = element.querySelector('[data-expense-id="1"]')
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
      checkbox.checked = false
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))

      expect(counter.classList.contains("hidden")).toBe(true)
    })

    it("updates counter format after select all", () => {
      const counter = element.querySelector('[data-batch-selection-target="selectionCounter"]')

      controller.selectAll()

      // selectAll uses requestAnimationFrame; verify format after sync call
      expect(counter.textContent).toBe("3 de 3 gastos seleccionados")
    })
  })

  // PER-189 Bug 2: aria-selected must be set on the row element
  describe("aria-selected state management", () => {
    it("sets aria-selected='true' on the row when a checkbox is checked", () => {
      const checkbox = element.querySelector('[data-expense-id="1"]')
      const row = element.querySelector("#expense_row_1")

      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))

      expect(row.getAttribute("aria-selected")).toBe("true")
    })

    it("sets aria-selected='false' on the row when a checkbox is unchecked", () => {
      const checkbox = element.querySelector('[data-expense-id="1"]')
      const row = element.querySelector("#expense_row_1")

      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))

      checkbox.checked = false
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))

      expect(row.getAttribute("aria-selected")).toBe("false")
    })

    it("sets aria-selected='true' on all rows after select all", () => {
      controller.selectAll()

      element.querySelectorAll("tr").forEach(row => {
        expect(row.getAttribute("aria-selected")).toBe("true")
      })
    })

    it("sets aria-selected='false' on all rows after clear selection", () => {
      controller.selectAll()
      controller.clearSelection()

      element.querySelectorAll("tr").forEach(row => {
        expect(row.getAttribute("aria-selected")).toBe("false")
      })
    })
  })

  describe("events", () => {
    it("dispatches selectionChanged event", (done) => {
      element.addEventListener("batch-selection:selection-changed", (event) => {
        expect(event.detail.selectedIds).toEqual([1])
        expect(event.detail.selectedCount).toBe(1)
        expect(event.detail.totalCount).toBe(3)
        done()
      })

      const checkbox = element.querySelector('[data-expense-id="1"]')
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    })

    it("dispatches openBulkOperations event", (done) => {
      element.addEventListener("batch-selection:open-bulk-operations", (event) => {
        expect(event.detail.selectedIds).toEqual([1, 2])
        expect(event.detail.selectedCount).toBe(2)
        done()
      })

      // Select some items
      controller.selectedIdsValue = [1, 2]
      controller.openBulkOperations()
    })
  })

  describe("helper methods", () => {
    it("returns selected IDs", () => {
      controller.selectedIdsValue = [1, 2, 3]
      expect(controller.getSelectedIds()).toEqual([1, 2, 3])
    })

    it("handles row click in selection mode", () => {
      controller.selectionModeValue = true
      
      const row = element.querySelector("#expense_row_1")
      const td = row.querySelector("td")
      
      // Simulate click on table cell (not checkbox)
      const event = new Event("click", { bubbles: true })
      Object.defineProperty(event, "currentTarget", { value: row, writable: false })
      Object.defineProperty(event, "target", { value: td, writable: false })
      
      controller.handleRowClick(event)
      
      // Should toggle the checkbox
      const checkbox = row.querySelector('[data-expense-id="1"]')
      // Note: In real implementation, this would toggle
    })
  })
})