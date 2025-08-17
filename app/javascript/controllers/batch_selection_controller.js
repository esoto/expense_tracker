import { Controller } from "@hotwired/stimulus"

/**
 * Batch Selection Controller
 * Manages batch selection of expenses with checkboxes, master selection, and keyboard navigation
 * Maintains selection state across filtering and pagination
 * Integrates with view toggle modes and prepares for bulk operations
 */
export default class extends Controller {
  static targets = [
    "masterCheckbox",
    "checkbox",
    "selectionCounter",
    "selectionToolbar",
    "bulkActionsButton",
    "clearSelectionButton",
    "selectedCount",
    "totalCount",
    "row"
  ]
  
  static values = {
    selectedIds: { type: Array, default: [] },
    totalVisible: { type: Number, default: 0 },
    selectionMode: { type: Boolean, default: false }
  }
  
  static classes = [
    "selectedRow",
    "unselectedRow",
    "toolbarVisible",
    "toolbarHidden"
  ]

  connect() {
    // Initialize with empty selections
    this.selectedIdsValue = []
    
    // Initialize timeout tracking for announcements
    this.announcementTimeout = null
    
    // Set up keyboard navigation
    this.setupKeyboardNavigation()
    
    // Count total visible expenses
    this.updateTotalCount()
    
    // Initialize UI state
    this.updateUI()
    
    // Listen for view toggle changes
    this.handleViewToggleChange = this.handleViewToggleChange.bind(this)
    document.addEventListener('view-toggle:toggled', this.handleViewToggleChange)
    
    // Listen for bulk operations completion
    this.handleBulkOperationsCompleted = this.handleBulkOperationsCompleted.bind(this)
    document.addEventListener('bulk-operations:completed', this.handleBulkOperationsCompleted)
  }

  disconnect() {
    // Clean up event listeners
    document.removeEventListener('view-toggle:toggled', this.handleViewToggleChange)
    document.removeEventListener('bulk-operations:completed', this.handleBulkOperationsCompleted)
    
    // Clean up keyboard navigation listeners
    this.disconnectKeyboardNavigation()
    
    // Clear any pending announcement timeouts
    if (this.announcementTimeout) {
      clearTimeout(this.announcementTimeout)
      this.announcementTimeout = null
    }
  }

  /**
   * Initialize keyboard navigation for accessibility
   */
  setupKeyboardNavigation() {
    // Add keyboard event listener for batch operations shortcuts
    this.keydownHandler = (event) => {
      // Ctrl/Cmd + A: Select all
      if ((event.metaKey || event.ctrlKey) && event.key === 'a' || 
          (event.metaKey || event.ctrlKey) && event.key === 'A') {
        const tableElement = this.element.querySelector('table')
        if (tableElement && (this.element.contains(document.activeElement) || this.selectionModeValue)) {
          event.preventDefault()
          this.selectAll()
        }
      }
      
      // Escape: Clear selection
      if (event.key === 'Escape' && this.selectedIdsValue.length > 0) {
        event.preventDefault()
        this.clearSelection()
      }
      
      // Ctrl/Cmd + Shift + A: Toggle selection mode
      if ((event.metaKey || event.ctrlKey) && event.shiftKey && event.key === 'A') {
        event.preventDefault()
        this.toggleSelectionMode()
      }
    }
    
    document.addEventListener('keydown', this.keydownHandler)
  }

  /**
   * Toggle selection mode on/off
   */
  toggleSelectionMode() {
    this.selectionModeValue = !this.selectionModeValue
    
    if (!this.selectionModeValue) {
      // Clear selections when exiting selection mode
      this.clearSelection()
    }
    
    this.updateCheckboxVisibility()
    this.dispatch('selectionModeChanged', {
      detail: { enabled: this.selectionModeValue }
    })
  }

  /**
   * Handle individual checkbox change
   */
  toggleSelection(event) {
    const checkbox = event.currentTarget
    const expenseId = parseInt(checkbox.dataset.expenseId)
    const row = checkbox.closest('tr')
    
    if (checkbox.checked) {
      this.addToSelection(expenseId, row)
    } else {
      this.removeFromSelection(expenseId, row)
    }
    
    this.updateUI()
  }

  /**
   * Add expense to selection
   */
  addToSelection(expenseId, row) {
    if (!this.selectedIdsValue.includes(expenseId)) {
      this.selectedIdsValue = [...this.selectedIdsValue, expenseId]
      
      if (row) {
        row.classList.add('bg-teal-50', 'border-teal-200')
        row.classList.remove('hover:bg-slate-50')
        row.setAttribute('aria-selected', 'true')
      }
    }
  }

  /**
   * Remove expense from selection
   */
  removeFromSelection(expenseId, row) {
    this.selectedIdsValue = this.selectedIdsValue.filter(id => id !== expenseId)
    
    if (row) {
      row.classList.remove('bg-teal-50', 'border-teal-200')
      row.classList.add('hover:bg-slate-50')
      row.setAttribute('aria-selected', 'false')
    }
  }

  /**
   * Toggle master checkbox - select/deselect all visible
   */
  toggleMasterSelection(event) {
    const isChecked = event.currentTarget.checked
    
    if (isChecked) {
      this.selectAll()
    } else {
      // Ensure immediate clearing when unchecking master
      this.clearSelection()
    }
  }

  /**
   * Select all visible expenses
   */
  selectAll() {
    // Enable selection mode if not already enabled
    if (!this.selectionModeValue) {
      this.selectionModeValue = true
      this.updateCheckboxVisibility()
    }
    
    const newSelectedIds = []
    const updates = []
    
    // Batch collect all updates
    this.checkboxTargets.forEach(checkbox => {
      const expenseId = parseInt(checkbox.dataset.expenseId)
      const row = checkbox.closest('tr')
      
      newSelectedIds.push(expenseId)
      updates.push({ checkbox, row })
    })
    
    // Apply all updates in a single frame for better performance
    requestAnimationFrame(() => {
      updates.forEach(({ checkbox, row }) => {
        checkbox.checked = true
        
        if (row) {
          row.classList.add('bg-teal-50', 'border-teal-200')
          row.classList.remove('hover:bg-slate-50')
          row.setAttribute('aria-selected', 'true')
        }
      })
      
      this.selectedIdsValue = newSelectedIds
      this.updateUI()
      
      // Announce to screen readers
      this.announceSelection(`${newSelectedIds.length} gastos seleccionados`)
    })
  }

  /**
   * Clear all selections
   */
  clearSelection() {
    // Immediately clear selection array to ensure UI updates correctly
    this.selectedIdsValue = []
    
    // Clear all checkboxes and row styles
    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = false
      const row = checkbox.closest('tr')
      
      if (row) {
        row.classList.remove('bg-teal-50', 'border-teal-200')
        row.classList.add('hover:bg-slate-50')
        row.setAttribute('aria-selected', 'false')
      }
    })
    
    // Reset master checkbox
    if (this.hasMasterCheckboxTarget) {
      this.masterCheckboxTarget.checked = false
      this.masterCheckboxTarget.indeterminate = false
    }
    
    // Immediately hide toolbar before updating UI
    if (this.hasSelectionToolbarTarget) {
      this.selectionToolbarTarget.classList.remove('flex', 'animate-slide-up')
      this.selectionToolbarTarget.classList.add('hidden')
      this.selectionToolbarTarget.style.display = 'none'
    }
    
    // Force update UI to ensure all elements are hidden
    this.updateUI()
    
    // Announce to screen readers
    this.announceSelection('Selección limpiada')
  }

  /**
   * Update UI elements based on selection state
   */
  updateUI() {
    const selectedCount = this.selectedIdsValue.length
    const totalCount = this.checkboxTargets.length
    
    // Update master checkbox state
    if (this.hasMasterCheckboxTarget) {
      if (selectedCount === 0) {
        this.masterCheckboxTarget.checked = false
        this.masterCheckboxTarget.indeterminate = false
      } else if (selectedCount === totalCount) {
        this.masterCheckboxTarget.checked = true
        this.masterCheckboxTarget.indeterminate = false
      } else {
        this.masterCheckboxTarget.checked = false
        this.masterCheckboxTarget.indeterminate = true
      }
    }
    
    // Update selection counter
    if (this.hasSelectionCounterTarget) {
      if (selectedCount > 0) {
        this.selectionCounterTarget.textContent = `${selectedCount} de ${totalCount} gastos seleccionados`
        this.selectionCounterTarget.classList.remove('hidden')
      } else {
        this.selectionCounterTarget.classList.add('hidden')
      }
    }
    
    // Update selection toolbar visibility
    if (this.hasSelectionToolbarTarget) {
      if (selectedCount > 0) {
        // Remove any forced display style
        this.selectionToolbarTarget.style.display = ''
        this.selectionToolbarTarget.classList.remove('hidden')
        this.selectionToolbarTarget.classList.add('flex')
        
        // Animate toolbar appearance
        requestAnimationFrame(() => {
          this.selectionToolbarTarget.classList.add('animate-slide-up')
        })
      } else {
        // Ensure toolbar is completely hidden
        this.selectionToolbarTarget.classList.remove('flex', 'animate-slide-up')
        this.selectionToolbarTarget.classList.add('hidden')
        // Force display none to ensure it's really hidden
        this.selectionToolbarTarget.style.display = 'none'
      }
    }
    
    // Update count displays
    if (this.hasSelectedCountTarget) {
      this.selectedCountTarget.textContent = selectedCount
    }
    
    if (this.hasTotalCountTarget) {
      this.totalCountTarget.textContent = totalCount
    }
    
    // Enable/disable bulk actions button
    if (this.hasBulkActionsButtonTarget) {
      this.bulkActionsButtonTarget.disabled = selectedCount === 0
      
      if (selectedCount > 0) {
        this.bulkActionsButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
        this.bulkActionsButtonTarget.classList.add('hover:bg-teal-800')
      } else {
        this.bulkActionsButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
        this.bulkActionsButtonTarget.classList.remove('hover:bg-teal-800')
      }
    }
    
    // Dispatch event for other components
    this.dispatch('selectionChanged', {
      detail: {
        selectedIds: this.selectedIdsValue,
        selectedCount: selectedCount,
        totalCount: totalCount
      }
    })
  }

  /**
   * Update total count of visible expenses
   */
  updateTotalCount() {
    this.totalVisibleValue = this.checkboxTargets.length
  }

  /**
   * Handle row click for selection (when in selection mode)
   */
  handleRowClick(event) {
    // Don't trigger if clicking on actual checkbox or action buttons
    if (event.target.closest('input[type="checkbox"]') || 
        event.target.closest('button') ||
        event.target.closest('a')) {
      return
    }
    
    // Don't trigger if clicking on inline actions container or its children
    if (event.target.closest('[data-inline-actions-target]')) {
      return
    }
    
    // Only handle clicks in selection mode
    if (!this.selectionModeValue) {
      return
    }
    
    const row = event.currentTarget
    const checkbox = row.querySelector('input[type="checkbox"][data-batch-selection-target="checkbox"]')
    
    if (checkbox) {
      checkbox.checked = !checkbox.checked
      checkbox.dispatchEvent(new Event('change', { bubbles: true }))
    }
  }

  /**
   * Update checkbox column visibility
   */
  updateCheckboxVisibility() {
    const checkboxColumn = this.element.querySelector('.checkbox-column')
    const checkboxHeaders = this.element.querySelectorAll('.checkbox-header')
    const checkboxCells = this.element.querySelectorAll('.checkbox-cell')
    
    if (this.selectionModeValue) {
      // Show checkbox column
      checkboxHeaders.forEach(header => header.classList.remove('hidden'))
      checkboxCells.forEach(cell => cell.classList.remove('hidden'))
    } else {
      // Hide checkbox column
      checkboxHeaders.forEach(header => header.classList.add('hidden'))
      checkboxCells.forEach(cell => cell.classList.add('hidden'))
    }
  }

  /**
   * Open bulk operations modal
   */
  openBulkOperations() {
    if (this.selectedIdsValue.length === 0) {
      return
    }
    
    // Dispatch event for bulk operations modal (Task 3.5)
    this.dispatch('openBulkOperations', {
      detail: {
        selectedIds: this.selectedIdsValue,
        selectedCount: this.selectedIdsValue.length
      }
    })
  }

  /**
   * Handle view toggle changes
   */
  handleViewToggleChange(event) {
    // Re-apply selection highlighting after view change
    this.checkboxTargets.forEach(checkbox => {
      const expenseId = parseInt(checkbox.dataset.expenseId)
      const row = checkbox.closest('tr')
      
      if (this.selectedIdsValue.includes(expenseId)) {
        checkbox.checked = true
        if (row) {
          row.classList.add('bg-teal-50', 'border-teal-200')
          row.classList.remove('hover:bg-slate-50')
          row.setAttribute('aria-selected', 'true')
        }
      }
    })
    
    // Update UI to reflect current state
    this.updateUI()
  }

  /**
   * Announce selection changes to screen readers
   */
  announceSelection(message) {
    const announcement = document.createElement('div')
    announcement.setAttribute('role', 'status')
    announcement.setAttribute('aria-live', 'polite')
    announcement.classList.add('sr-only')
    announcement.textContent = message
    
    document.body.appendChild(announcement)
    
    // Clear any existing timeout
    if (this.announcementTimeout) {
      clearTimeout(this.announcementTimeout)
    }
    
    // Store timeout reference for cleanup
    this.announcementTimeout = setTimeout(() => {
      // Check if element still exists before removing
      if (announcement.parentNode) {
        document.body.removeChild(announcement)
      }
      this.announcementTimeout = null
    }, 1000)
  }

  /**
   * Get selected expense IDs
   */
  getSelectedIds() {
    return this.selectedIdsValue
  }

  /**
   * Handle bulk operations completion
   */
  handleBulkOperationsCompleted(event) {
    const { success } = event.detail
    
    if (success) {
      // Clear selection after successful bulk operation
      this.clearSelection()
      
      // Exit selection mode
      this.selectionModeValue = false
      this.updateCheckboxVisibility()
    }
  }

  /**
   * Clean up on disconnect
   */
  disconnectKeyboardNavigation() {
    if (this.keydownHandler) {
      document.removeEventListener('keydown', this.keydownHandler)
    }
  }
}