import { Controller } from "@hotwired/stimulus"
import { shouldSuppressShortcut } from "../utilities/keyboard_shortcut_helpers"

/**
 * View Toggle Controller
 * Manages the toggle between compact and expanded view modes for the expense list
 * Persists user preference in sessionStorage for consistency across page loads
 */
export default class extends Controller {
  static targets = [
    "toggleButton",
    "compactIcon",
    "expandedIcon",
    "buttonText",
    "table",
    "compactColumns",
    "expandedColumns"
  ]
  
  static values = {
    compact: { type: Boolean, default: false }
  }
  
  static classes = [
    "compactRow",
    "expandedRow",
    "hiddenColumn",
    "visibleColumn"
  ]

  connect() {
    // Load saved preference from sessionStorage
    const savedMode = sessionStorage.getItem('expenseViewMode')
    if (savedMode === 'compact') {
      this.compactValue = true
    }
    
    // Apply initial view mode
    this.updateView()
  }

  /**
   * Toggle between compact and expanded view modes
   */
  toggle() {
    this.compactValue = !this.compactValue
    
    // Save preference to sessionStorage
    sessionStorage.setItem('expenseViewMode', this.compactValue ? 'compact' : 'expanded')
    
    // Update the view
    this.updateView()
    
    // Dispatch custom event for analytics or other listeners
    this.dispatch('toggled', {
      detail: { compact: this.compactValue }
    })
  }

  /**
   * Update the view based on current mode
   */
  updateView() {
    if (this.compactValue) {
      this.applyCompactView()
    } else {
      this.applyExpandedView()
    }
    
    this.updateToggleButton()
  }

  /**
   * Apply compact view mode
   * Shows only essential columns: Date, Merchant, Category, Amount
   */
  applyCompactView() {
    // Hide expanded columns
    this.expandedColumnsTargets.forEach(column => {
      column.classList.add('hidden')
      column.classList.add('md:hidden')
    })
    
    // Update row styling for compact mode
    const rows = this.tableTarget.querySelectorAll('tbody tr')
    rows.forEach(row => {
      row.classList.add('h-12') // Reduced height
      row.classList.remove('h-16')
      
      // Hide description lines in merchant column
      const descriptions = row.querySelectorAll('.expense-description')
      descriptions.forEach(desc => desc.classList.add('hidden'))
      
      // Compact the category display
      const categoryFrames = row.querySelectorAll('[data-controller="category-confidence"]')
      categoryFrames.forEach(frame => {
        const badges = frame.querySelectorAll('.confidence-badge')
        badges.forEach(badge => badge.classList.add('hidden'))
      })
      
      // Inline actions are hidden via CSS in compact mode
      // No JavaScript manipulation needed
    })
    
    // Add compact mode class to table
    this.tableTarget.classList.add('compact-mode')
    this.tableTarget.classList.remove('expanded-mode')
  }

  /**
   * Apply expanded view mode
   * Shows all columns and full information
   */
  applyExpandedView() {
    // Show expanded columns
    this.expandedColumnsTargets.forEach(column => {
      column.classList.remove('hidden', 'md:hidden')
    })
    
    // Update row styling for expanded mode
    const rows = this.tableTarget.querySelectorAll('tbody tr')
    rows.forEach(row => {
      row.classList.remove('h-12')
      row.classList.add('h-16') // Standard height
      
      // Show description lines in merchant column
      const descriptions = row.querySelectorAll('.expense-description')
      descriptions.forEach(desc => desc.classList.remove('hidden'))
      
      // Expand the category display
      const categoryFrames = row.querySelectorAll('[data-controller="category-confidence"]')
      categoryFrames.forEach(frame => {
        const badges = frame.querySelectorAll('.confidence-badge')
        badges.forEach(badge => badge.classList.remove('hidden'))
      })
      
      // Inline actions are shown via CSS in expanded mode
      // No JavaScript manipulation needed
    })
    
    // Add expanded mode class to table
    this.tableTarget.classList.remove('compact-mode')
    this.tableTarget.classList.add('expanded-mode')
  }

  /**
   * Update toggle button appearance
   */
  updateToggleButton() {
    if (!this.hasToggleButtonTarget) return
    
    // Update button text
    if (this.hasButtonTextTarget) {
      this.buttonTextTarget.textContent = this.compactValue ? 'Vista Expandida' : 'Vista Compacta'
    }
    
    // Update button icons
    if (this.hasCompactIconTarget && this.hasExpandedIconTarget) {
      if (this.compactValue) {
        this.compactIconTarget.classList.add('hidden')
        this.expandedIconTarget.classList.remove('hidden')
      } else {
        this.compactIconTarget.classList.remove('hidden')
        this.expandedIconTarget.classList.add('hidden')
      }
    }
    
    // Update button styling
    this.toggleButtonTarget.classList.toggle('bg-teal-100', this.compactValue)
    this.toggleButtonTarget.classList.toggle('text-teal-800', this.compactValue)
    this.toggleButtonTarget.classList.toggle('bg-slate-100', !this.compactValue)
    this.toggleButtonTarget.classList.toggle('text-slate-700', !this.compactValue)
  }

  /**
   * Keyboard shortcut handler
   * Allow toggling with keyboard shortcut (Ctrl/Cmd + Shift + V)
   */
  handleKeydown(event) {
    // Don't fire shortcuts when typing in form fields
    if (shouldSuppressShortcut(event)) return

    if ((event.metaKey || event.ctrlKey) && event.shiftKey && event.key === 'V') {
      event.preventDefault()
      this.toggle()
    }
  }

  /**
   * Handle responsive behavior
   * Automatically switch to compact mode on small screens
   */
  handleResize() {
    const isMobile = window.innerWidth < 768
    
    if (isMobile && !this.compactValue) {
      // Auto-switch to compact on mobile
      this.compactValue = true
      this.updateView()
    }
  }

  /**
   * Value changed callback for compactValue
   */
  compactValueChanged() {
    // This is called whenever compactValue changes
    // Can be used for additional side effects if needed
  }
}