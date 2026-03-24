import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { shouldSuppressShortcut } from "../utilities/keyboard_shortcut_helpers"

// Dashboard Expenses Controller for Epic 3 Task 3.2
// Manages view toggle between compact and expanded modes with responsive behavior
export default class extends Controller {
  static targets = [
    "container",
    "list",
    "table",
    "tableBody",
    "expenseRow",
    "expandedColumns",
    "expandedDetails",
    "quickActions",
    "selectionContainer",
    "selectionCheckbox",
    "selectionToolbar",
    "selectedCount",
    "selectAllCheckbox",
    "compactButton",
    "expandedButton",
    "viewToggleGroup"
  ]
  
  static values = {
    viewMode: { type: String, default: "compact" },
    page: { type: Number, default: 1 },
    selectedIds: { type: Array, default: [] },
    isMobile: { type: Boolean, default: false },
    selectionMode: { type: Boolean, default: false },
    lastSelectedIndex: { type: Number, default: -1 }
  }
  
  connect() {
    this.initializeViewMode()
    this.initializeResponsiveDesign()
    this.loadPreferences()
    this.applyViewMode()
    this.initializeBatchSelection()
    this.initializeKeyboardNavigation()
    this.initializeKeyboardShortcuts()
    this.initializeAriaLiveRegion()
    
    // Log performance metrics in development
    if (this.element.dataset.environment === "development") {
      console.log("Dashboard Expenses Widget initialized", {
        viewMode: this.viewModeValue,
        rowCount: this.expenseRowTargets.length,
        isMobile: this.isMobileValue,
        selectionMode: this.selectionModeValue,
        hasTargets: {
          selectionToolbar: this.hasSelectionToolbarTarget,
          selectionCheckbox: this.hasSelectionCheckboxTarget,
          selectAllCheckbox: this.hasSelectAllCheckboxTarget
        }
      })
    }
  }
  
  disconnect() {
    // Clean up resize observer
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
    }
    // Remove keyboard shortcut listener
    if (this.keyboardShortcutHandler) {
      document.removeEventListener("keydown", this.keyboardShortcutHandler)
    }
    // Remove ARIA live region
    if (this.ariaLiveRegion) {
      this.ariaLiveRegion.remove()
    }
    // CRITICAL FIX: Clean up any lingering modals and toasts
    this.cleanupModalsAndToasts()
  }
  
  // Initialize view mode from sessionStorage or data attribute
  initializeViewMode() {
    // Check sessionStorage first
    const storedMode = sessionStorage.getItem("dashboard_expense_view_mode")
    if (storedMode && (storedMode === "compact" || storedMode === "expanded")) {
      this.viewModeValue = storedMode
    } else if (this.element.dataset.dashboardExpensesViewModeValue) {
      // Use server-provided value as fallback
      this.viewModeValue = this.element.dataset.dashboardExpensesViewModeValue
    }
  }
  
  // Initialize responsive design handling
  initializeResponsiveDesign() {
    // Check initial viewport size
    this.checkViewportSize()
    
    // Set up resize observer for responsive behavior
    this.resizeObserver = new ResizeObserver(() => {
      this.checkViewportSize()
    })
    this.resizeObserver.observe(document.body)
    
    // Also listen to orientation change for mobile devices
    window.addEventListener("orientationchange", () => {
      setTimeout(() => this.checkViewportSize(), 100)
    })
  }
  
  // Check viewport size and adjust accordingly
  checkViewportSize() {
    const width = window.innerWidth
    const wasMobile = this.isMobileValue
    this.isMobileValue = width < 768 // Tailwind's md: breakpoint
    
    // Auto-switch to compact on mobile if not already
    if (this.isMobileValue && !wasMobile) {
      this.setViewModeWithoutSave("compact")
      this.disableExpandedButton()
    } else if (!this.isMobileValue && wasMobile) {
      // Re-enable expanded button on desktop
      this.enableExpandedButton()
      // Restore user preference if returning to desktop
      const storedMode = sessionStorage.getItem("dashboard_expense_view_mode")
      if (storedMode) {
        this.setViewModeWithoutSave(storedMode)
      }
    }
  }
  
  // Disable expanded button on mobile
  disableExpandedButton() {
    if (this.hasExpandedButtonTarget) {
      this.expandedButtonTarget.disabled = true
      this.expandedButtonTarget.classList.add("opacity-50", "cursor-not-allowed")
      this.expandedButtonTarget.title = "Vista expandida no disponible en móvil"
    }
  }
  
  // Enable expanded button on desktop
  enableExpandedButton() {
    if (this.hasExpandedButtonTarget) {
      this.expandedButtonTarget.disabled = false
      this.expandedButtonTarget.classList.remove("opacity-50", "cursor-not-allowed")
      this.expandedButtonTarget.title = ""
    }
  }
  
  // View mode toggling with session persistence (Task 3.2)
  setViewMode(event) {
    const mode = event.currentTarget.dataset.mode
    
    // Don't allow expanded mode on mobile
    if (mode === "expanded" && this.isMobileValue) {
      this.announce("Vista expandida no disponible en dispositivos móviles")
      return
    }
    
    this.setViewModeWithoutSave(mode)
    this.savePreference("view_mode", mode)
    this.updateServerPreference(mode)
  }
  
  // Set view mode without saving (for responsive changes)
  setViewModeWithoutSave(mode) {
    this.viewModeValue = mode
    this.applyViewMode()
    this.announce(`Vista cambiada a ${mode === "expanded" ? "expandida" : "compacta"}`)
  }
  
  // Apply the current view mode to the UI
  applyViewMode() {
    const mode = this.viewModeValue

    // Update widget container classes
    this.element.classList.remove("dashboard-expenses-compact", "dashboard-expenses-expanded")
    this.element.classList.add(`dashboard-expenses-${mode}`)

    // Update button states with smooth transition
    this.element.querySelectorAll("[data-mode]").forEach(button => {
      if (button.dataset.mode === mode) {
        button.classList.add("bg-white", "text-slate-900", "shadow-sm")
        button.classList.remove("text-slate-600", "hover:text-slate-900")
        button.setAttribute("aria-pressed", "true")
      } else {
        button.classList.remove("bg-white", "text-slate-900", "shadow-sm")
        button.classList.add("text-slate-600", "hover:text-slate-900")
        button.setAttribute("aria-pressed", "false")
      }
    })

    // Toggle column visibility (table-based layout)
    if (this.expandedColumnsTargets && this.expandedColumnsTargets.length > 0) {
      this.expandedColumnsTargets.forEach(col => {
        if (mode === "expanded") {
          col.classList.remove("hidden")
        } else {
          col.classList.add("hidden")
        }
      })
    }

    // Toggle description visibility in merchant cells
    this.element.querySelectorAll(".expense-description").forEach(desc => {
      if (mode === "expanded") {
        desc.classList.remove("hidden")
      } else {
        desc.classList.add("hidden")
      }
    })

    // Show all rows (table shows all loaded expenses)
    this.expenseRowTargets.forEach(row => {
      row.classList.remove("hidden")
    })
  }
  
  // Filter by category (Quick filter foundation)
  filterByCategory(event) {
    const categoryId = event.currentTarget.dataset.categoryId
    const params = new URLSearchParams(window.location.search)
    
    // Toggle category filter
    const currentCategories = params.getAll("category_ids[]")
    if (currentCategories.includes(categoryId)) {
      params.delete("category_ids[]")
      currentCategories
        .filter(id => id !== categoryId)
        .forEach(id => params.append("category_ids[]", id))
    } else {
      params.append("category_ids[]", categoryId)
    }
    
    this.applyFilters(params)
  }
  
  // Filter by status
  filterByStatus(event) {
    const status = event.currentTarget.dataset.status
    const params = new URLSearchParams(window.location.search)
    
    if (params.get("status") === status) {
      params.delete("status")
    } else {
      params.set("status", status)
    }
    
    this.applyFilters(params)
  }
  
  // Clear all filters
  clearFilters() {
    const params = new URLSearchParams()
    // Preserve only non-filter params
    const preserveParams = ["view_mode", "page"]
    const currentParams = new URLSearchParams(window.location.search)
    
    preserveParams.forEach(param => {
      if (currentParams.has(param)) {
        params.set(param, currentParams.get(param))
      }
    })
    
    this.applyFilters(params)
  }
  
  // Apply filters and reload widget
  applyFilters(params) {
    // Add loading state
    this.containerTarget.classList.add("opacity-50")
    
    // Fetch filtered data via Turbo
    const url = `/expenses/dashboard?${params.toString()}`
    
    Turbo.visit(url, {
      action: "replace",
      frame: "dashboard-expenses-widget"
    })
  }
  
  // Load more expenses (pagination)
  loadMore(event) {
    event.preventDefault()
    const button = event.currentTarget
    
    // Show loading state
    button.disabled = true
    button.textContent = "Cargando..."
    
    // Increment page
    const params = new URLSearchParams(window.location.search)
    const currentPage = parseInt(params.get("page") || "1")
    params.set("page", currentPage + 1)
    
    // Fetch next page
    fetch(`/expenses/dashboard?${params.toString()}`, {
      headers: {
        "Accept": "text/vnd.turbo-stream.html"
      }
    })
    .then(response => response.text())
    .then(html => {
      // Append new expenses to the list
      const parser = new DOMParser()
      const doc = parser.parseFromString(html, "text/html")
      const newExpenses = doc.querySelectorAll("[data-dashboard-expenses-target='expenseRow']")
      
      newExpenses.forEach(expense => {
        this.listTarget.appendChild(expense)
      })
      
      // Update or hide load more button
      const hasMore = doc.querySelector("[data-action*='loadMore']")
      if (!hasMore) {
        button.remove()
      } else {
        button.disabled = false
        button.textContent = "Cargar más gastos"
      }
    })
    .catch(error => {
      console.error("Error loading more expenses:", error)
      button.disabled = false
      button.textContent = "Error - Intentar de nuevo"
    })
  }
  
  // Delete expense (Task 3.3 foundation)
  deleteExpense(event) {
    event.preventDefault()
    const expenseId = event.currentTarget.dataset.expenseId
    
    if (!confirm("¿Estás seguro de que quieres eliminar este gasto?")) {
      return
    }
    
    const row = this.expenseRowTargets.find(row => 
      row.dataset.expenseId === expenseId
    )
    
    if (row) {
      // Add deleting state
      row.classList.add("opacity-50", "pointer-events-none")
      
      // Send delete request
      fetch(`/expenses/${expenseId}`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": this.getCSRFToken(),
          "Accept": "application/json"
        }
      })
      .then(response => {
        if (response.ok) {
          // Animate removal
          row.style.transition = "all 0.3s ease-out"
          row.style.transform = "translateX(-100%)"
          row.style.opacity = "0"
          
          setTimeout(() => {
            row.remove()
            this.announce("Gasto eliminado exitosamente")
            
            // Check if list is empty
            if (this.expenseRowTargets.length === 0) {
              this.showEmptyState()
            }
          }, 300)
        } else {
          throw new Error("Failed to delete expense")
        }
      })
      .catch(error => {
        console.error("Error deleting expense:", error)
        row.classList.remove("opacity-50", "pointer-events-none")
        this.announce("Error al eliminar el gasto")
      })
    }
  }
  
  // Initialize batch selection system (Task 3.4)
  initializeBatchSelection() {
    // Add click handlers for row selection
    this.expenseRowTargets.forEach((row, index) => {
      // Store index as data attribute for easier access
      row.dataset.rowIndex = index
      
      row.addEventListener("click", (event) => {
        // Don't select if clicking on action buttons, links, or the checkbox itself
        if (event.target.closest("button, a, input[type='checkbox']")) return
        
        if (this.selectionModeValue) {
          event.preventDefault()
          const checkbox = row.querySelector('input[type="checkbox"]')
          if (checkbox) {
            // Handle Shift+click for range selection
            if (event.shiftKey && this.lastSelectedIndexValue >= 0) {
              this.selectRange(this.lastSelectedIndexValue, index)
            } else {
              // Toggle checkbox state for normal click
              checkbox.checked = !checkbox.checked
              this.handleSelectionChange(event, index)
            }
          }
        }
      })
      
      // Add double-click to enter selection mode if not already
      row.addEventListener("dblclick", (event) => {
        if (!this.selectionModeValue && !event.target.closest("button, a")) {
          event.preventDefault()
          event.stopPropagation()
          this.enableSelectionMode()
          // Wait for DOM updates before selecting
          setTimeout(() => {
            const checkbox = row.querySelector('input[type="checkbox"]')
            if (checkbox) {
              checkbox.checked = true
              const currentIndex = parseInt(row.dataset.rowIndex)
              this.handleSelectionChange(event, currentIndex >= 0 ? currentIndex : index)
            }
          }, 100)
        }
      })
    })
    
    // Initialize selection mode based on URL params
    const params = new URLSearchParams(window.location.search)
    if (params.get("selection_mode") === "true") {
      this.enableSelectionMode()
    }
  }
  
  // Toggle selection mode
  toggleSelectionMode(event) {
    event?.preventDefault()
    
    // Check current state from the value and DOM
    const isActive = this.element.classList.contains("selection-mode-active") || this.selectionModeValue
    
    if (isActive) {
      this.disableSelectionMode()
    } else {
      this.enableSelectionMode()
    }
  }
  
  // Enable selection mode
  enableSelectionMode() {
    this.selectionModeValue = true
    this.selectedIdsValue = []
    this.lastSelectedIndexValue = -1
    
    // Add selection mode class to the controller element (which IS the widget)
    this.element.classList.add("selection-mode-active")
    
    // Debug logging in development
    if (this.element.dataset.environment === "development") {
      console.log("Selection mode enabled", {
        element: this.element,
        elementId: this.element.id,
        classList: this.element.classList.toString(),
        selectionMode: this.selectionModeValue
      })
    }
    
    // Show selection checkboxes with animation
    this.selectionContainerTargets.forEach((container, index) => {
      container.classList.remove("hidden")
      setTimeout(() => {
        container.style.opacity = "0"
        container.style.transform = "translateX(-10px)"
        container.style.transition = "all 0.2s ease-out"
        setTimeout(() => {
          container.style.opacity = "1"
          container.style.transform = "translateX(0)"
        }, index * 20) // Stagger animation
      }, 10)
    })
    
    // Show and animate toolbar
    if (this.hasSelectionToolbarTarget) {
      this.selectionToolbarTarget.classList.remove("hidden")
      this.selectionToolbarTarget.style.display = "block"
      this.selectionToolbarTarget.style.opacity = "0"
      this.selectionToolbarTarget.style.transform = "translateY(-10px)"
      setTimeout(() => {
        this.selectionToolbarTarget.style.transition = "all 0.3s ease-out"
        this.selectionToolbarTarget.style.opacity = "1"
        this.selectionToolbarTarget.style.transform = "translateY(0)"
      }, 50)
    }
    
    // Update button state
    const selectionButton = this.element.querySelector('[data-action*="toggleSelectionMode"]')
    if (selectionButton) {
      selectionButton.classList.add("bg-teal-50", "text-teal-700")
      selectionButton.classList.remove("text-slate-600")
    }
    
    // Update UI
    this.updateSelectionUI()
    
    // Update accessibility
    this.announce("Modo de selección activado. Usa la barra espaciadora para seleccionar elementos.")
    
    // Focus first visible row for keyboard users
    const firstVisibleRow = this.expenseRowTargets.find(row => !row.classList.contains("hidden"))
    if (firstVisibleRow) {
      firstVisibleRow.focus()
    }
  }
  
  // Disable selection mode
  disableSelectionMode() {
    this.selectionModeValue = false
    
    // Clear selections first
    this.clearAllSelections()
    
    // Animate hiding checkboxes
    this.selectionContainerTargets.forEach((container, index) => {
      container.style.transition = "all 0.2s ease-out"
      container.style.opacity = "0"
      container.style.transform = "translateX(-10px)"
      setTimeout(() => {
        container.classList.add("hidden")
      }, 200)
    })
    
    // Animate hiding toolbar
    if (this.hasSelectionToolbarTarget) {
      this.selectionToolbarTarget.style.transition = "all 0.3s ease-out"
      this.selectionToolbarTarget.style.opacity = "0"
      this.selectionToolbarTarget.style.transform = "translateY(-10px)"
      setTimeout(() => {
        this.selectionToolbarTarget.classList.add("hidden")
        this.selectionToolbarTarget.style.display = "none"
      }, 300)
    }
    
    // Remove selection mode class from controller element
    setTimeout(() => {
      this.element.classList.remove("selection-mode-active")
    }, 300)
    
    // Update button state
    const selectionButton = this.element.querySelector('[data-action*="toggleSelectionMode"]')
    if (selectionButton) {
      selectionButton.classList.remove("bg-teal-50", "text-teal-700")
      selectionButton.classList.add("text-slate-600")
    }
    
    this.announce("Modo de selección desactivado")
  }
  
  // Handle individual checkbox selection
  toggleSelection(event) {
    const checkbox = event.currentTarget
    const expenseId = checkbox.dataset.expenseId
    const row = checkbox.closest("tr[data-expense-id]") || checkbox.closest(".dashboard-expense-row")
    const rowIndex = parseInt(row.dataset.rowIndex) || this.expenseRowTargets.indexOf(row)
    
    // Check for Shift+click on checkbox
    if (event.shiftKey && this.lastSelectedIndexValue >= 0 && this.lastSelectedIndexValue !== rowIndex) {
      event.preventDefault()
      this.selectRange(this.lastSelectedIndexValue, rowIndex)
    } else {
      this.handleSelectionChange(event, rowIndex)
    }
  }
  
  // Handle selection change with Shift+click support
  handleSelectionChange(event, currentIndex) {
    const row = this.expenseRowTargets[currentIndex]
    const checkbox = row.querySelector('input[type="checkbox"]')
    if (!checkbox) return
    
    const expenseId = checkbox.dataset.expenseId
    
    // Shift+click handling is now done in initializeBatchSelection
    // This function handles single selection only
    if (checkbox.checked) {
      if (!this.selectedIdsValue.includes(expenseId)) {
        this.selectedIdsValue = [...this.selectedIdsValue, expenseId]
      }
      row.classList.add("selected")
      this.lastSelectedIndexValue = currentIndex
    } else {
      this.selectedIdsValue = this.selectedIdsValue.filter(id => id !== expenseId)
      row.classList.remove("selected")
      // Only clear last selected if this was the last selected item
      if (this.lastSelectedIndexValue === currentIndex) {
        this.lastSelectedIndexValue = -1
      }
    }
    
    // Update UI
    this.updateSelectionUI()
  }
  
  // Select range of items (Shift+click)
  selectRange(startIndex, endIndex) {
    const start = Math.min(startIndex, endIndex)
    const end = Math.max(startIndex, endIndex)
    
    for (let i = start; i <= end; i++) {
      const row = this.expenseRowTargets[i]
      if (!row) continue
      
      const checkbox = row.querySelector('input[type="checkbox"]')
      if (checkbox && !checkbox.checked) {
        checkbox.checked = true
        const expenseId = checkbox.dataset.expenseId
        if (expenseId && !this.selectedIdsValue.includes(expenseId)) {
          this.selectedIdsValue = [...this.selectedIdsValue, expenseId]
        }
        row.classList.add("selected")
      }
    }
    
    this.lastSelectedIndexValue = endIndex
    this.updateSelectionUI()
  }
  
  // Select all visible expenses
  selectAll(event) {
    event?.preventDefault()
    
    const visibleRows = this.expenseRowTargets.filter(row => !row.classList.contains("hidden"))
    const allSelected = visibleRows.every(row => {
      const checkbox = row.querySelector('input[type="checkbox"]')
      return checkbox && checkbox.checked
    })
    
    if (allSelected) {
      // Deselect all
      this.clearAllSelections()
    } else {
      // Select all visible
      visibleRows.forEach(row => {
        const checkbox = row.querySelector('input[type="checkbox"]')
        if (checkbox && !checkbox.checked) {
          checkbox.checked = true
          const expenseId = checkbox.dataset.expenseId
          if (!this.selectedIdsValue.includes(expenseId)) {
            this.selectedIdsValue = [...this.selectedIdsValue, expenseId]
          }
          row.classList.add("selected")
        }
      })
    }
    
    this.updateSelectionUI()
    this.announce(`${this.selectedIdsValue.length} elementos seleccionados`)
  }
  
  // Clear all selections
  clearAllSelections() {
    this.selectedIdsValue = []
    this.lastSelectedIndexValue = -1
    
    // Uncheck all checkboxes
    this.selectionCheckboxTargets.forEach(checkbox => {
      checkbox.checked = false
    })
    
    // Remove selected class from rows
    this.expenseRowTargets.forEach(row => {
      row.classList.remove("selected")
    })
    
    // Update select all checkbox
    if (this.hasSelectAllCheckboxTarget) {
      this.selectAllCheckboxTarget.checked = false
      this.selectAllCheckboxTarget.indeterminate = false
    }
    
    this.updateSelectionUI()
  }
  
  // Initialize keyboard shortcuts
  initializeKeyboardShortcuts() {
    this.keyboardShortcutHandler = (event) => {
      // Don't fire shortcuts when typing in form fields (except Escape)
      if (shouldSuppressShortcut(event)) return

      // Only handle shortcuts when this controller's element is relevant
      // (contains the active element or is visible on the page)
      if (!this.element.contains(document.activeElement) && document.activeElement !== document.body) {
        // Allow Ctrl+Shift+V globally since it is a view toggle
        if (!((event.ctrlKey || event.metaKey) && event.shiftKey && event.key === "V")) {
          return
        }
      }

      // Ctrl+Shift+V or Cmd+Shift+V for view toggle
      if ((event.ctrlKey || event.metaKey) && event.shiftKey && event.key === "V") {
        event.preventDefault()
        event.stopPropagation()
        this.toggleViewMode()
        return
      }

      // Ctrl+A or Cmd+A for select all (when in selection mode)
      if ((event.ctrlKey || event.metaKey) && event.key === "a" && this.selectionModeValue) {
        event.preventDefault()
        event.stopPropagation()
        this.selectAll()
        return
      }

      // Escape to exit selection mode
      if (event.key === "Escape" && this.selectionModeValue) {
        event.preventDefault()
        event.stopPropagation()
        this.disableSelectionMode()
        return
      }

      // Ctrl+Shift+S or Cmd+Shift+S to toggle selection mode
      if ((event.ctrlKey || event.metaKey) && event.shiftKey && event.key === "S") {
        event.preventDefault()
        event.stopPropagation()
        this.toggleSelectionMode()
        return
      }

      // Space to toggle selection when focused on a row
      if (event.key === " " && this.selectionModeValue) {
        const activeElement = document.activeElement
        // Check if the focused element is a row or within a row
        const focusedRow = activeElement.closest("tr[data-expense-id]") ||
                          activeElement.closest(".dashboard-expense-row") ||
                          (activeElement.matches("[data-dashboard-expenses-target='expenseRow']") ? activeElement : null)

        if (focusedRow) {
          event.preventDefault()
          event.stopPropagation()
          const checkbox = focusedRow.querySelector('input[type="checkbox"]')
          if (checkbox) {
            checkbox.checked = !checkbox.checked
            const index = parseInt(focusedRow.dataset.rowIndex) || this.expenseRowTargets.indexOf(focusedRow)
            if (index >= 0) {
              this.handleSelectionChange(event, index)
            }
          }
        }
      }
    }

    document.addEventListener("keydown", this.keyboardShortcutHandler)
  }
  
  // Toggle between compact and expanded view modes
  toggleViewMode() {
    const newMode = this.viewModeValue === "compact" ? "expanded" : "compact"
    
    // Don't allow expanded mode on mobile
    if (newMode === "expanded" && this.isMobileValue) {
      this.announce("Vista expandida no disponible en dispositivos móviles")
      return
    }
    
    this.setViewModeWithoutSave(newMode)
    this.savePreference("view_mode", newMode)
    this.updateServerPreference(newMode)
  }
  
  // Update server with view preference via AJAX
  updateServerPreference(mode) {
    // Store in sessionStorage for immediate persistence
    sessionStorage.setItem("dashboard_expense_view_mode", mode)
    
    // Optional: Send to server if user preferences are stored there
    // This is a non-blocking request, we don't wait for the response
    fetch("/expenses/update_preference", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.getCSRFToken(),
        "Accept": "application/json"
      },
      body: JSON.stringify({
        preference: "dashboard_expense_view_mode",
        value: mode
      })
    })
    .catch(error => {
      // Silently fail - preference is already saved locally
      console.debug("Failed to update server preference:", error)
    })
  }
  
  // Keyboard navigation support
  initializeKeyboardNavigation() {
    this.expenseRowTargets.forEach((row, index) => {
      // Make rows focusable if not already
      if (!row.hasAttribute('tabindex')) {
        row.setAttribute('tabindex', '0')
      }
      
      row.addEventListener("keydown", (event) => {
        // Don't fire shortcuts when typing in form fields (except Escape)
        if (shouldSuppressShortcut(event)) return

        switch(event.key) {
          case "ArrowDown":
            event.preventDefault()
            this.focusRow(index + 1)
            break
          case "ArrowUp":
            event.preventDefault()
            this.focusRow(index - 1)
            break
          case "Enter":
            if (this.selectionModeValue && !event.ctrlKey && !event.metaKey) {
              // Toggle selection in selection mode
              event.preventDefault()
              const checkbox = row.querySelector('input[type="checkbox"]')
              if (checkbox) {
                checkbox.checked = !checkbox.checked
                this.handleSelectionChange(event, index)
              }
            } else if (event.ctrlKey || event.metaKey) {
              // Open in new tab
              const editLink = row.querySelector("a[href*='edit']")
              if (editLink) {
                window.open(editLink.href, "_blank")
              }
            }
            break
          case "Delete":
            if (!this.selectionModeValue) {
              const deleteButton = row.querySelector("[data-action*='deleteExpense']")
              if (deleteButton) {
                deleteButton.click()
              }
            }
            break
          case " ":
            // Space key for selection - prevent default scrolling
            if (this.selectionModeValue) {
              event.preventDefault()
              event.stopPropagation()
              // Toggle selection
              const checkbox = row.querySelector('input[type="checkbox"]')
              if (checkbox) {
                checkbox.checked = !checkbox.checked
                this.handleSelectionChange(event, index)
              }
            }
            break
        }
      })
    })
  }
  
  focusRow(index) {
    if (index >= 0 && index < this.expenseRowTargets.length) {
      this.expenseRowTargets[index].focus()
    }
  }
  
  // Update selection UI
  updateSelectionUI() {
    const count = this.selectedIdsValue.length
    const visibleRows = this.expenseRowTargets.filter(row => !row.classList.contains("hidden"))
    const visibleCount = visibleRows.length
    
    // Update selected count display
    if (this.hasSelectedCountTarget) {
      this.selectedCountTarget.textContent = count
      // Animate count change
      this.selectedCountTarget.style.animation = "none"
      setTimeout(() => {
        this.selectedCountTarget.style.animation = "countUpdate 0.3s ease-out"
      }, 10)
    }
    
    // Update select all checkbox state
    if (this.hasSelectAllCheckboxTarget) {
      const visibleSelected = visibleRows.filter(row => {
        const checkbox = row.querySelector('input[type="checkbox"]')
        return checkbox && checkbox.checked
      }).length
      
      if (visibleSelected === 0) {
        this.selectAllCheckboxTarget.checked = false
        this.selectAllCheckboxTarget.indeterminate = false
      } else if (visibleSelected === visibleCount) {
        this.selectAllCheckboxTarget.checked = true
        this.selectAllCheckboxTarget.indeterminate = false
      } else {
        this.selectAllCheckboxTarget.checked = false
        this.selectAllCheckboxTarget.indeterminate = true
      }
    }
    
    // Show/hide toolbar based on selection mode
    if (this.hasSelectionToolbarTarget) {
      if (this.selectionModeValue) {
        // Toolbar is always visible in selection mode
        this.selectionToolbarTarget.classList.remove("hidden")
        this.selectionToolbarTarget.style.display = "block"
        
        // CRITICAL FIX: Update visual state of bulk action buttons based on selection count
        // Find buttons specifically by their data-bulk-action attributes
        const bulkButtons = this.selectionToolbarTarget.querySelectorAll('[data-bulk-action]')
        
        bulkButtons.forEach(button => {
          if (count > 0) {
            button.classList.remove("opacity-50", "cursor-not-allowed")
            button.removeAttribute('aria-disabled')
          } else {
            button.classList.add("opacity-50", "cursor-not-allowed")
            button.setAttribute('aria-disabled', 'true')
          }
        })
      } else {
        // Hide toolbar when not in selection mode
        this.selectionToolbarTarget.classList.add("hidden")
        this.selectionToolbarTarget.style.display = "none"
      }
    }
    
    // Update ARIA live region with proper announcement
    if (count > 0) {
      this.announce(`${count} ${count === 1 ? 'elemento seleccionado' : 'elementos seleccionados'}`)
    } else if (this.selectionModeValue) {
      // Only announce empty selection in selection mode
      this.announce("Ningún elemento seleccionado")
    }
  }
  
  // Task 3.5: Bulk Operations Implementation
  
  // Bulk delete selected items with confirmation modal
  bulkDelete(event) {
    event?.preventDefault()
    
    if (this.selectedIdsValue.length === 0) {
      this.showToast("Por favor selecciona al menos un gasto", "warning")
      return
    }
    
    const count = this.selectedIdsValue.length
    this.showBulkDeleteModal(count)
  }
  
  // Show bulk delete confirmation modal
  showBulkDeleteModal(count) {
    // Create modal HTML
    const modalHtml = `
      <div class="bulk-modal-overlay" data-bulk-modal="delete">
        <div class="bulk-modal-container">
          <div class="bulk-modal-header bg-rose-50 border-rose-200">
            <h3 class="text-lg font-semibold text-rose-900">Confirmar Eliminación</h3>
            <button type="button" class="bulk-modal-close" data-action="click->dashboard-expenses#closeBulkModal">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>
            </button>
          </div>
          <div class="bulk-modal-body">
            <div class="flex items-start space-x-3">
              <div class="flex-shrink-0">
                <svg class="w-6 h-6 text-rose-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
                </svg>
              </div>
              <div class="flex-1">
                <p class="text-sm text-slate-900">
                  ¿Estás seguro de que quieres eliminar <strong>${count} ${count === 1 ? 'gasto' : 'gastos'}</strong>?
                </p>
                <p class="mt-2 text-sm text-slate-600">
                  Los gastos se eliminarán pero podrás deshacer esta acción durante los próximos 30 segundos.
                </p>
              </div>
            </div>
          </div>
          <div class="bulk-modal-footer">
            <button type="button" 
                    class="btn-secondary w-full sm:w-auto px-4 py-2"
                    data-action="click->dashboard-expenses#closeBulkModal">
              Cancelar
            </button>
            <button type="button" 
                    class="btn-danger w-full sm:w-auto px-4 py-2"
                    data-action="click->dashboard-expenses#confirmBulkDelete">
              <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
              </svg>
              Eliminar ${count === 1 ? 'Gasto' : `${count} Gastos`}
            </button>
          </div>
        </div>
      </div>
    `
    
    this.insertModal(modalHtml)
  }
  
  // Confirm bulk delete
  confirmBulkDelete(event) {
    event?.preventDefault()
    
    const button = event.currentTarget
    button.disabled = true
    button.innerHTML = '<span class="spinner"></span> Eliminando...'
    
    // Send bulk delete request
    fetch('/expenses/bulk_destroy', {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCSRFToken(),
        'Accept': 'application/json'
      },
      body: JSON.stringify({
        expense_ids: this.selectedIdsValue
      })
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
      return response.json()
    })
    .then(data => {
      console.log("Bulk delete response:", data)
      if (data.success) {
        this.closeBulkModal()
        
        // Show undo notification if undo_id is provided
        if (data.undo_id) {
          this.showUndoNotification(
            data.undo_id,
            data.message || `${data.affected_count || this.selectedIdsValue.length} gastos eliminados`,
            data.undo_time_remaining || 30
          )
        } else {
          const message = data.message || `${data.affected_count || this.selectedIdsValue.length} gastos eliminados exitosamente`
          console.log("Showing toast with message:", message)
          this.showToast(message, "success")
        }
        
        // Remove deleted rows from DOM
        this.selectedIdsValue.forEach(id => {
          const row = this.expenseRowTargets.find(r => r.dataset.expenseId === id)
          if (row) {
            row.style.transition = "all 0.3s ease-out"
            row.style.transform = "translateX(-100%)"
            row.style.opacity = "0"
            setTimeout(() => row.remove(), 300)
          }
        })
        
        // Clear selections and exit selection mode
        this.clearAllSelections()
        this.disableSelectionMode()
        
        // Check if list is empty
        if (this.expenseRowTargets.length === this.selectedIdsValue.length) {
          setTimeout(() => this.showEmptyState(), 400)
        }
      } else {
        this.closeBulkModal()
        this.showToast(data.message || "Error al eliminar gastos", "error")
      }
    })
    .catch(error => {
      console.error("Error in bulk delete:", error)
      this.closeBulkModal()
      this.showToast("Error al eliminar gastos", "error")
    })
  }
  
  // Bulk categorize selected items with modal
  bulkCategorize(event) {
    event?.preventDefault()
    
    if (this.selectedIdsValue.length === 0) {
      this.showToast("Por favor selecciona al menos un gasto", "warning")
      return
    }
    
    this.showBulkCategorizeModal()
  }
  
  // Show bulk categorize modal
  showBulkCategorizeModal() {
    const count = this.selectedIdsValue.length
    
    // Fetch categories for the dropdown
    fetch('/categories.json', {
      headers: {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
      .then(response => {
        if (!response.ok) throw new Error('Failed to fetch categories')
        return response.json()
      })
      .then(categories => {
        const categoryOptions = categories.map(cat => 
          `<option value="${cat.id}" data-color="${cat.color}">${cat.name}</option>`
        ).join('')
        
        const modalHtml = `
          <div class="bulk-modal-overlay" data-bulk-modal="categorize">
            <div class="bulk-modal-container">
              <div class="bulk-modal-header bg-teal-50 border-teal-200">
                <h3 class="text-lg font-semibold text-teal-900">Categorizar Gastos</h3>
                <button type="button" class="bulk-modal-close" data-action="click->dashboard-expenses#closeBulkModal">
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                  </svg>
                </button>
              </div>
              <form data-action="submit->dashboard-expenses#confirmBulkCategorize">
                <div class="bulk-modal-body">
                  <p class="text-sm text-slate-700 mb-4">
                    Selecciona una categoría para aplicar a <strong>${count} ${count === 1 ? 'gasto' : 'gastos'}</strong>:
                  </p>
                  <div class="form-group">
                    <label for="bulk-category-select" class="block text-sm font-medium text-slate-700 mb-2">
                      Categoría
                    </label>
                    <select id="bulk-category-select" 
                            name="category_id" 
                            class="w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-teal-500 focus:border-teal-500"
                            required>
                      <option value="">Seleccionar categoría...</option>
                      ${categoryOptions}
                    </select>
                  </div>
                  <div class="mt-3 p-3 bg-amber-50 border border-amber-200 rounded-lg">
                    <p class="text-xs text-amber-800">
                      <strong>Nota:</strong> Esta acción actualizará la categoría de todos los gastos seleccionados y 
                      registrará la corrección para mejorar las sugerencias futuras del sistema.
                    </p>
                  </div>
                </div>
                <div class="bulk-modal-footer">
                  <button type="button" 
                          class="btn-secondary w-full sm:w-auto px-4 py-2"
                          data-action="click->dashboard-expenses#closeBulkModal">
                    Cancelar
                  </button>
                  <button type="submit" 
                          class="btn-primary w-full sm:w-auto px-4 py-2">
                    <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"></path>
                    </svg>
                    Aplicar Categoría
                  </button>
                </div>
              </form>
            </div>
          </div>
        `
        
        this.insertModal(modalHtml)
        
        // Focus on select after modal opens
        setTimeout(() => {
          document.getElementById('bulk-category-select')?.focus()
        }, 100)
      })
      .catch(error => {
        console.error("Error fetching categories:", error)
        this.showToast("Error al cargar categorías", "error")
      })
  }
  
  // Confirm bulk categorize
  confirmBulkCategorize(event) {
    event?.preventDefault()
    
    const form = event.currentTarget
    const formData = new FormData(form)
    const categoryId = formData.get('category_id')
    
    if (!categoryId) {
      this.showToast("Por favor selecciona una categoría", "warning")
      return
    }
    
    const submitButton = form.querySelector('button[type="submit"]')
    submitButton.disabled = true
    submitButton.innerHTML = '<span class="spinner"></span> Aplicando...'
    
    // Send bulk categorize request
    fetch('/expenses/bulk_categorize', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCSRFToken(),
        'Accept': 'application/json'
      },
      body: JSON.stringify({
        expense_ids: this.selectedIdsValue,
        category_id: categoryId
      })
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
      return response.json()
    })
    .then(data => {
      console.log("Bulk categorize response:", data)
      if (data.success) {
        this.closeBulkModal()
        // Use the message from the backend service which includes the category name
        const message = data.message || `${data.affected_count || this.selectedIdsValue.length} gastos categorizados exitosamente`
        console.log("Showing toast with message:", message)
        this.showToast(message, "success")
        
        // Update UI - reload the widget to show new categories
        this.reloadWidget()
        
        // Clear selections and exit selection mode
        this.clearAllSelections()
        this.disableSelectionMode()
      } else {
        submitButton.disabled = false
        submitButton.innerHTML = `
          <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"></path>
          </svg>
          Aplicar Categoría
        `
        this.showToast(data.message || "Error al categorizar gastos", "error")
      }
    })
    .catch(error => {
      console.error("Error in bulk categorize:", error)
      submitButton.disabled = false
      submitButton.innerHTML = `
        <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"></path>
        </svg>
        Aplicar Categoría
      `
      this.showToast("Error al categorizar gastos", "error")
    })
  }
  
  // Bulk update status with modal
  bulkUpdateStatus(event) {
    event?.preventDefault()
    
    if (this.selectedIdsValue.length === 0) {
      this.showToast("Por favor selecciona al menos un gasto", "warning")
      return
    }
    
    this.showBulkStatusModal()
  }
  
  // Show bulk status update modal
  showBulkStatusModal() {
    const count = this.selectedIdsValue.length
    
    const modalHtml = `
      <div class="bulk-modal-overlay" data-bulk-modal="status">
        <div class="bulk-modal-container">
          <div class="bulk-modal-header bg-amber-50 border-amber-200">
            <h3 class="text-lg font-semibold text-amber-900">Actualizar Estado</h3>
            <button type="button" class="bulk-modal-close" data-action="click->dashboard-expenses#closeBulkModal">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>
            </button>
          </div>
          <form data-action="submit->dashboard-expenses#confirmBulkStatus">
            <div class="bulk-modal-body">
              <p class="text-sm text-slate-700 mb-4">
                Selecciona un estado para aplicar a <strong>${count} ${count === 1 ? 'gasto' : 'gastos'}</strong>:
              </p>
              <div class="form-group">
                <div class="space-y-2">
                  <label class="flex items-center p-3 border border-slate-200 rounded-lg hover:bg-slate-50 cursor-pointer transition-colors">
                    <input type="radio" name="status" value="pending" class="text-amber-600 focus:ring-amber-500" required>
                    <span class="ml-3 flex items-center">
                      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-amber-100 text-amber-800">
                        Pendiente
                      </span>
                      <span class="ml-2 text-sm text-slate-600">Requiere revisión</span>
                    </span>
                  </label>
                  <label class="flex items-center p-3 border border-slate-200 rounded-lg hover:bg-slate-50 cursor-pointer transition-colors">
                    <input type="radio" name="status" value="processed" class="text-emerald-600 focus:ring-emerald-500" required>
                    <span class="ml-3 flex items-center">
                      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-emerald-100 text-emerald-800">
                        Procesado
                      </span>
                      <span class="ml-2 text-sm text-slate-600">Completamente revisado</span>
                    </span>
                  </label>
                </div>
              </div>
            </div>
            <div class="bulk-modal-footer">
              <button type="button" 
                      class="btn-secondary w-full sm:w-auto px-4 py-2"
                      data-action="click->dashboard-expenses#closeBulkModal">
                Cancelar
              </button>
              <button type="submit" 
                      class="btn-primary bg-amber-600 hover:bg-amber-700 w-full sm:w-auto px-4 py-2">
                <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                Actualizar Estado
              </button>
            </div>
          </form>
        </div>
      </div>
    `
    
    this.insertModal(modalHtml)
  }
  
  // Confirm bulk status update
  confirmBulkStatus(event) {
    event?.preventDefault()
    
    const form = event.currentTarget
    const formData = new FormData(form)
    const status = formData.get('status')
    
    if (!status) {
      this.showToast("Por favor selecciona un estado", "warning")
      return
    }
    
    const submitButton = form.querySelector('button[type="submit"]')
    submitButton.disabled = true
    submitButton.innerHTML = '<span class="spinner"></span> Actualizando...'
    
    // Send bulk status update request
    fetch('/expenses/bulk_update_status', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCSRFToken(),
        'Accept': 'application/json'
      },
      body: JSON.stringify({
        expense_ids: this.selectedIdsValue,
        status: status
      })
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
      return response.json()
    })
    .then(data => {
      console.log("Bulk status update response:", data)
      if (data.success) {
        this.closeBulkModal()
        const message = data.message || `${data.affected_count || this.selectedIdsValue.length} gastos actualizados exitosamente`
        console.log("Showing toast with message:", message)
        this.showToast(message, "success")
        
        // Update UI - reload the widget to show new statuses
        this.reloadWidget()
        
        // Clear selections and exit selection mode
        this.clearAllSelections()
        this.disableSelectionMode()
      } else {
        submitButton.disabled = false
        submitButton.innerHTML = `
          <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
          </svg>
          Actualizar Estado
        `
        this.showToast(data.message || "Error al actualizar estado", "error")
      }
    })
    .catch(error => {
      console.error("Error in bulk status update:", error)
      submitButton.disabled = false
      submitButton.innerHTML = `
        <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
        Actualizar Estado
      `
      this.showToast("Error al actualizar estado", "error")
    })
  }
  
  // Helper: Insert modal into DOM
  insertModal(modalHtml) {
    // Remove any existing modals first
    const existingModal = document.querySelector('.bulk-modal-overlay')
    if (existingModal) {
      existingModal.remove()
    }
    
    // Create modal element
    const modalDiv = document.createElement('div')
    modalDiv.innerHTML = modalHtml
    const modalElement = modalDiv.firstElementChild
    document.body.appendChild(modalElement)
    
    // Add escape key handler
    this.modalEscapeHandler = (e) => {
      if (e.key === 'Escape') {
        e.stopPropagation()
        this.closeBulkModal()
      }
    }
    document.addEventListener('keydown', this.modalEscapeHandler)
    
    // Add click outside handler
    modalElement.addEventListener('click', (e) => {
      if (e.target === modalElement) {
        this.closeBulkModal()
      }
    })
    
    // Animate modal entrance
    requestAnimationFrame(() => {
      if (modalElement) {
        modalElement.style.opacity = '0'
        modalElement.style.transition = 'opacity 0.2s ease-out'
        requestAnimationFrame(() => {
          modalElement.style.opacity = '1'
        })
      }
    })
  }
  
  // Close bulk modal
  closeBulkModal(event) {
    event?.preventDefault()
    event?.stopPropagation()
    
    console.log("Closing bulk modal")
    const modal = document.querySelector('.bulk-modal-overlay')
    if (modal) {
      // Add closing state to prevent multiple close attempts
      if (modal.dataset.closing === 'true') return
      modal.dataset.closing = 'true'
      
      modal.style.transition = 'opacity 0.2s ease-out'
      modal.style.opacity = '0'
      
      // Use a slightly longer timeout to ensure animation completes
      setTimeout(() => {
        if (modal && modal.parentNode) {
          modal.remove()
        }
      }, 300) // Increased timeout for more reliable removal
    }
    
    // Remove escape key handler
    if (this.modalEscapeHandler) {
      document.removeEventListener('keydown', this.modalEscapeHandler)
      this.modalEscapeHandler = null
    }
  }
  
  // CRITICAL FIX: Clean up all modals and toasts
  cleanupModalsAndToasts() {
    // Remove any bulk modals
    document.querySelectorAll('.bulk-modal-overlay').forEach(modal => {
      modal.remove()
    })
    
    // Remove toast container
    const toastContainer = document.getElementById('toast-container')
    if (toastContainer) {
      toastContainer.remove()
    }
    
    // Clean up any event handlers
    if (this.modalEscapeHandler) {
      document.removeEventListener('keydown', this.modalEscapeHandler)
      this.modalEscapeHandler = null
    }
  }
  
  // Show toast notification
  showToast(message, type = "info") {
    const toastTypes = {
      success: {
        bg: "bg-emerald-50",
        border: "border-emerald-200",
        text: "text-emerald-800",
        icon: `<svg class="w-5 h-5 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>`
      },
      error: {
        bg: "bg-rose-50",
        border: "border-rose-200",
        text: "text-rose-800",
        icon: `<svg class="w-5 h-5 text-rose-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>`
      },
      warning: {
        bg: "bg-amber-50",
        border: "border-amber-200",
        text: "text-amber-800",
        icon: `<svg class="w-5 h-5 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
              </svg>`
      },
      info: {
        bg: "bg-slate-50",
        border: "border-slate-200",
        text: "text-slate-800",
        icon: `<svg class="w-5 h-5 text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>`
      }
    }
    
    const config = toastTypes[type] || toastTypes.info
    
    // Create toast container if it doesn't exist
    let toastContainer = document.getElementById('toast-container')
    if (!toastContainer) {
      toastContainer = document.createElement('div')
      toastContainer.id = 'toast-container'
      toastContainer.className = 'fixed top-4 right-4 z-[9999] space-y-2'
      document.body.appendChild(toastContainer)
    }
    
    // Create toast element
    const toast = document.createElement('div')
    toast.className = `flex items-center p-4 rounded-lg border ${config.bg} ${config.border} ${config.text} shadow-lg max-w-sm animate-slide-in`
    toast.innerHTML = `
      <div class="flex-shrink-0 mr-3">
        ${config.icon}
      </div>
      <div class="flex-1 text-sm font-medium">
        ${message}
      </div>
      <button type="button" class="ml-3 -mr-1 flex-shrink-0" onclick="this.parentElement.remove()">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
        </svg>
      </button>
    `
    
    toastContainer.appendChild(toast)
    
    // Auto-remove after 5 seconds
    setTimeout(() => {
      toast.classList.add('animate-slide-out')
      setTimeout(() => {
        toast.remove()
        // Remove container if empty
        if (toastContainer.children.length === 0) {
          toastContainer.remove()
        }
      }, 300)
    }, 5000)
    
    // Also announce to screen readers
    this.announce(message)
  }
  
  // Reload widget with current filters
  reloadWidget() {
    const params = new URLSearchParams(window.location.search)
    params.set('view_mode', this.viewModeValue)
    
    // Add loading state
    this.containerTarget.classList.add("opacity-50")
    
    // Fetch updated data via Turbo
    const url = `/expenses/dashboard?${params.toString()}`
    
    Turbo.visit(url, {
      action: "replace",
      frame: "dashboard-expenses-widget"
    })
  }
  
  // Show empty state
  showEmptyState() {
    this.containerTarget.innerHTML = `
      <div class="text-center py-8">
        <svg class="mx-auto h-12 w-12 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"></path>
        </svg>
        <h3 class="mt-2 text-sm font-medium text-slate-900">No hay gastos</h3>
        <p class="mt-1 text-sm text-slate-500">
          Todos los gastos han sido eliminados.
        </p>
      </div>
    `
  }
  
  // Load user preferences
  loadPreferences() {
    // Use sessionStorage for session persistence
    const savedViewMode = sessionStorage.getItem("dashboard_expense_view_mode")
    if (savedViewMode && (savedViewMode === "compact" || savedViewMode === "expanded")) {
      this.viewModeValue = savedViewMode
    }
  }
  
  // Save user preference
  savePreference(key, value) {
    // Use sessionStorage for session persistence
    sessionStorage.setItem(`dashboard_expense_${key}`, value)
  }
  
  // Get CSRF token
  getCSRFToken() {
    const tokenElement = document.querySelector('meta[name="csrf-token"]')
    return tokenElement ? tokenElement.content : ""
  }
  
  // Initialize ARIA live region for announcements
  initializeAriaLiveRegion() {
    // Check if one already exists and remove it
    const existingRegion = this.element.querySelector('[role="status"][aria-live="polite"]')
    if (existingRegion) {
      existingRegion.remove()
    }
    
    // Create persistent live region within the widget
    this.ariaLiveRegion = document.createElement("div")
    this.ariaLiveRegion.setAttribute("role", "status")
    this.ariaLiveRegion.setAttribute("aria-live", "polite")
    this.ariaLiveRegion.setAttribute("aria-atomic", "true")
    this.ariaLiveRegion.classList.add("sr-only")
    // Use visibility hidden instead of offscreen positioning for better compatibility
    this.ariaLiveRegion.style.position = "absolute"
    this.ariaLiveRegion.style.width = "1px"
    this.ariaLiveRegion.style.height = "1px"
    this.ariaLiveRegion.style.padding = "0"
    this.ariaLiveRegion.style.margin = "-1px"
    this.ariaLiveRegion.style.overflow = "hidden"
    this.ariaLiveRegion.style.clip = "rect(0, 0, 0, 0)"
    this.ariaLiveRegion.style.whiteSpace = "nowrap"
    this.ariaLiveRegion.style.border = "0"
    // Append to widget element instead of body
    this.element.appendChild(this.ariaLiveRegion)
  }
  
  // Show undo notification
  showUndoNotification(undoId, message, timeRemaining) {
    // Create undo notification element
    const notificationHtml = `
      <div class="fixed bottom-4 left-4 right-4 md:left-auto md:right-4 md:w-96 z-50 
                  bg-white rounded-lg shadow-xl border border-slate-200 p-4 
                  transform transition-all duration-300 slide-in-bottom"
           data-controller="undo-manager"
           data-undo-manager-undo-id-value="${undoId}"
           data-undo-manager-time-remaining-value="${timeRemaining}">
        <div class="flex items-start justify-between">
          <div class="flex items-start space-x-3 flex-1">
            <div class="flex-shrink-0">
              <svg class="w-5 h-5 text-amber-600 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
              </svg>
            </div>
            <div class="flex-1">
              <p class="text-sm font-medium text-slate-900" data-undo-manager-target="message">
                ${message}
              </p>
              <p class="text-xs text-slate-600 mt-1">
                Tiempo restante: <span class="font-medium" data-undo-manager-target="timer">${timeRemaining}s</span>
              </p>
            </div>
          </div>
          <div class="flex items-center space-x-2 ml-4">
            <button type="button"
                    class="px-3 py-1.5 text-sm font-medium text-white bg-teal-700 rounded-lg hover:bg-teal-800 transition-colors"
                    data-undo-manager-target="undoButton"
                    data-action="click->undo-manager#undo">
              Deshacer
            </button>
            <button type="button"
                    class="p-1 text-slate-400 hover:text-slate-600 transition-colors"
                    data-action="click->undo-manager#dismiss">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>
            </button>
          </div>
        </div>
      </div>
    `
    
    // Add notification to page
    const container = document.createElement('div')
    container.innerHTML = notificationHtml
    document.body.appendChild(container.firstElementChild)
  }
  
  // Announce to screen readers
  announce(message) {
    if (!this.ariaLiveRegion) {
      // Initialize if not present
      this.initializeAriaLiveRegion()
    }
    
    if (this.ariaLiveRegion) {
      // CRITICAL FIX: Force update by clearing and setting with delay
      // This ensures screen readers pick up the change
      this.ariaLiveRegion.textContent = ""
      // Use requestAnimationFrame for better timing
      requestAnimationFrame(() => {
        this.ariaLiveRegion.textContent = message
        // Also update aria-label for better compatibility
        this.ariaLiveRegion.setAttribute("aria-label", message)
        
        // Log for debugging in test environment
        if (this.element.dataset.environment === "test" || this.element.dataset.environment === "development") {
          console.log("ARIA announcement:", message)
        }
      })
    }
  }
}