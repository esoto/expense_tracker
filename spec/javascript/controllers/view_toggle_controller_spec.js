import { Application } from "@hotwired/stimulus"
import ViewToggleController from "view_toggle_controller"

describe("ViewToggleController", () => {
  let application
  let controller
  let element

  beforeEach(() => {
    // Set up DOM
    document.body.innerHTML = `
      <div data-controller="view-toggle" 
           data-view-toggle-compact-value="false">
        <button data-view-toggle-target="toggleButton">
          <svg data-view-toggle-target="compactIcon"></svg>
          <svg data-view-toggle-target="expandedIcon" class="hidden"></svg>
          <span data-view-toggle-target="buttonText">Vista Compacta</span>
        </button>
        
        <table data-view-toggle-target="table" class="expanded-mode">
          <thead>
            <tr>
              <th>Fecha</th>
              <th>Comercio</th>
              <th>Categoría</th>
              <th>Monto</th>
              <th data-view-toggle-target="expandedColumns">Banco</th>
              <th data-view-toggle-target="expandedColumns">Estado</th>
              <th data-view-toggle-target="expandedColumns">Acciones</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>01/01/2024</td>
              <td>
                <div>Store ABC</div>
                <div class="expense-description">Purchase description</div>
              </td>
              <td>
                <div data-controller="category-confidence">
                  <span>Food</span>
                  <span class="confidence-badge">95%</span>
                </div>
              </td>
              <td>₡5,000</td>
              <td data-view-toggle-target="expandedColumns">BAC</td>
              <td data-view-toggle-target="expandedColumns">Processed</td>
              <td data-view-toggle-target="expandedColumns">
                <a href="#">Ver</a>
                <a href="#">Editar</a>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    `

    element = document.querySelector('[data-controller="view-toggle"]')
    
    // Initialize Stimulus
    application = Application.start()
    application.register("view-toggle", ViewToggleController)
    
    // Get controller instance
    controller = application.getControllerForElementAndIdentifier(element, "view-toggle")
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
    sessionStorage.clear()
  })

  describe("Initialization", () => {
    it("loads saved preference from sessionStorage", () => {
      sessionStorage.setItem('expenseViewMode', 'compact')
      
      // Re-initialize controller
      const newController = new ViewToggleController()
      newController.element = element
      newController.connect()
      
      expect(newController.compactValue).toBe(true)
    })

    it("defaults to expanded view when no preference is saved", () => {
      expect(controller.compactValue).toBe(false)
      expect(element.querySelector('[data-view-toggle-target="table"]').classList.contains('expanded-mode')).toBe(true)
    })
  })

  describe("Toggle functionality", () => {
    it("toggles between compact and expanded modes", () => {
      const button = element.querySelector('[data-view-toggle-target="toggleButton"]')
      
      // Initial state - expanded
      expect(controller.compactValue).toBe(false)
      
      // Click to toggle to compact
      button.click()
      expect(controller.compactValue).toBe(true)
      
      // Click to toggle back to expanded
      button.click()
      expect(controller.compactValue).toBe(false)
    })

    it("saves preference to sessionStorage", () => {
      const button = element.querySelector('[data-view-toggle-target="toggleButton"]')
      
      button.click()
      expect(sessionStorage.getItem('expenseViewMode')).toBe('compact')
      
      button.click()
      expect(sessionStorage.getItem('expenseViewMode')).toBe('expanded')
    })

    it("dispatches custom event when toggled", (done) => {
      element.addEventListener('view-toggle:toggled', (event) => {
        expect(event.detail.compact).toBe(true)
        done()
      })
      
      const button = element.querySelector('[data-view-toggle-target="toggleButton"]')
      button.click()
    })
  })

  describe("Compact view mode", () => {
    beforeEach(() => {
      controller.compactValue = true
      controller.updateView()
    })

    it("hides expanded columns", () => {
      const expandedColumns = element.querySelectorAll('[data-view-toggle-target="expandedColumns"]')
      expandedColumns.forEach(column => {
        expect(column.classList.contains('hidden')).toBe(true)
      })
    })

    it("hides expense descriptions", () => {
      const descriptions = element.querySelectorAll('.expense-description')
      descriptions.forEach(desc => {
        expect(desc.classList.contains('hidden')).toBe(true)
      })
    })

    it("adds compact-mode class to table", () => {
      const table = element.querySelector('[data-view-toggle-target="table"]')
      expect(table.classList.contains('compact-mode')).toBe(true)
      expect(table.classList.contains('expanded-mode')).toBe(false)
    })

    it("updates button text", () => {
      const buttonText = element.querySelector('[data-view-toggle-target="buttonText"]')
      expect(buttonText.textContent).toBe('Vista Expandida')
    })

    it("shows correct icon", () => {
      const compactIcon = element.querySelector('[data-view-toggle-target="compactIcon"]')
      const expandedIcon = element.querySelector('[data-view-toggle-target="expandedIcon"]')
      
      expect(compactIcon.classList.contains('hidden')).toBe(true)
      expect(expandedIcon.classList.contains('hidden')).toBe(false)
    })
  })

  describe("Expanded view mode", () => {
    beforeEach(() => {
      controller.compactValue = false
      controller.updateView()
    })

    it("shows expanded columns", () => {
      const expandedColumns = element.querySelectorAll('[data-view-toggle-target="expandedColumns"]')
      expandedColumns.forEach(column => {
        expect(column.classList.contains('hidden')).toBe(false)
      })
    })

    it("shows expense descriptions", () => {
      const descriptions = element.querySelectorAll('.expense-description')
      descriptions.forEach(desc => {
        expect(desc.classList.contains('hidden')).toBe(false)
      })
    })

    it("adds expanded-mode class to table", () => {
      const table = element.querySelector('[data-view-toggle-target="table"]')
      expect(table.classList.contains('expanded-mode')).toBe(true)
      expect(table.classList.contains('compact-mode')).toBe(false)
    })

    it("updates button text", () => {
      const buttonText = element.querySelector('[data-view-toggle-target="buttonText"]')
      expect(buttonText.textContent).toBe('Vista Compacta')
    })
  })

  describe("Keyboard shortcuts", () => {
    it("toggles with Ctrl+Shift+V", () => {
      const event = new KeyboardEvent('keydown', {
        key: 'V',
        ctrlKey: true,
        shiftKey: true
      })
      
      expect(controller.compactValue).toBe(false)
      
      controller.handleKeydown(event)
      expect(controller.compactValue).toBe(true)
      
      controller.handleKeydown(event)
      expect(controller.compactValue).toBe(false)
    })

    it("toggles with Cmd+Shift+V on Mac", () => {
      const event = new KeyboardEvent('keydown', {
        key: 'V',
        metaKey: true,
        shiftKey: true
      })
      
      controller.handleKeydown(event)
      expect(controller.compactValue).toBe(true)
    })

    it("ignores other key combinations", () => {
      const event = new KeyboardEvent('keydown', {
        key: 'V',
        ctrlKey: true
      })
      
      const initialValue = controller.compactValue
      controller.handleKeydown(event)
      expect(controller.compactValue).toBe(initialValue)
    })
  })

  describe("Responsive behavior", () => {
    it("auto-switches to compact mode on small screens", () => {
      // Mock mobile viewport
      Object.defineProperty(window, 'innerWidth', {
        writable: true,
        configurable: true,
        value: 375
      })
      
      controller.handleResize()
      expect(controller.compactValue).toBe(true)
    })

    it("maintains user preference on desktop", () => {
      // Mock desktop viewport
      Object.defineProperty(window, 'innerWidth', {
        writable: true,
        configurable: true,
        value: 1400
      })
      
      controller.compactValue = false
      controller.handleResize()
      expect(controller.compactValue).toBe(false)
    })
  })

  describe("Button styling", () => {
    it("applies correct classes in compact mode", () => {
      controller.compactValue = true
      controller.updateToggleButton()
      
      const button = element.querySelector('[data-view-toggle-target="toggleButton"]')
      expect(button.classList.contains('bg-teal-100')).toBe(true)
      expect(button.classList.contains('text-teal-800')).toBe(true)
    })

    it("applies correct classes in expanded mode", () => {
      controller.compactValue = false
      controller.updateToggleButton()
      
      const button = element.querySelector('[data-view-toggle-target="toggleButton"]')
      expect(button.classList.contains('bg-slate-100')).toBe(true)
      expect(button.classList.contains('text-slate-700')).toBe(true)
    })
  })

  describe("Performance", () => {
    it("efficiently updates multiple rows", () => {
      // Add more rows to test performance
      const tbody = element.querySelector('tbody')
      for (let i = 0; i < 50; i++) {
        const row = tbody.querySelector('tr').cloneNode(true)
        tbody.appendChild(row)
      }
      
      const startTime = performance.now()
      controller.toggle()
      const endTime = performance.now()
      
      // Should complete within 100ms even with many rows
      expect(endTime - startTime).toBeLessThan(100)
    })
  })
})