import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["importModal", "searchField"]
  
  connect() {
    // Set up keyboard shortcuts
    this.setupKeyboardShortcuts()
    
    // Initialize search debounce timer
    this.searchTimer = null
  }
  
  disconnect() {
    // Clean up event listeners
    document.removeEventListener('keydown', this.handleKeydown)
  }
  
  setupKeyboardShortcuts() {
    this.handleKeydown = (event) => {
      // Cmd/Ctrl + K for search focus
      if ((event.metaKey || event.ctrlKey) && event.key === 'k') {
        event.preventDefault()
        this.focusSearch()
      }
      
      // Cmd/Ctrl + N for new pattern
      if ((event.metaKey || event.ctrlKey) && event.key === 'n') {
        event.preventDefault()
        this.createNewPattern()
      }
      
      // Cmd/Ctrl + I for import
      if ((event.metaKey || event.ctrlKey) && event.key === 'i') {
        event.preventDefault()
        this.showImportModal()
      }
      
      // Escape to close modals
      if (event.key === 'Escape') {
        this.hideImportModal()
      }
    }
    
    document.addEventListener('keydown', this.handleKeydown)
  }
  
  focusSearch() {
    if (this.hasSearchFieldTarget) {
      this.searchFieldTarget.focus()
      this.searchFieldTarget.select()
    }
  }
  
  createNewPattern() {
    window.location.href = '/admin/patterns/new'
  }
  
  showImportModal() {
    if (this.hasImportModalTarget) {
      this.importModalTarget.classList.remove('hidden')
      // Focus the file input
      const fileInput = this.importModalTarget.querySelector('input[type="file"]')
      if (fileInput) {
        fileInput.focus()
      }
    }
  }
  
  hideImportModal() {
    if (this.hasImportModalTarget) {
      this.importModalTarget.classList.add('hidden')
    }
  }
  
  debounceSearch(event) {
    // Clear existing timer
    if (this.searchTimer) {
      clearTimeout(this.searchTimer)
    }
    
    // Set new timer
    this.searchTimer = setTimeout(() => {
      event.target.form.requestSubmit()
    }, 300)
  }
  
  filterChanged(event) {
    // Submit form immediately when filter changes
    event.target.form.requestSubmit()
  }
  
  // Bulk operations
  selectAll(event) {
    const checkboxes = this.element.querySelectorAll('input[type="checkbox"][name="pattern_ids[]"]')
    checkboxes.forEach(checkbox => {
      checkbox.checked = event.target.checked
    })
    this.updateBulkActions()
  }
  
  updateBulkActions() {
    const checkedCount = this.element.querySelectorAll('input[type="checkbox"][name="pattern_ids[]"]:checked').length
    const bulkActions = this.element.querySelector('[data-bulk-actions]')
    
    if (bulkActions) {
      if (checkedCount > 0) {
        bulkActions.classList.remove('hidden')
        bulkActions.querySelector('[data-selected-count]').textContent = checkedCount
      } else {
        bulkActions.classList.add('hidden')
      }
    }
  }
  
  bulkActivate() {
    this.performBulkAction('activate')
  }
  
  bulkDeactivate() {
    this.performBulkAction('deactivate')
  }
  
  bulkDelete() {
    if (confirm('Are you sure you want to delete the selected patterns?')) {
      this.performBulkAction('delete')
    }
  }
  
  performBulkAction(action) {
    const form = document.createElement('form')
    form.method = 'POST'
    form.action = `/admin/patterns/bulk_${action}`
    
    // Add CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]').content
    const csrfInput = document.createElement('input')
    csrfInput.type = 'hidden'
    csrfInput.name = 'authenticity_token'
    csrfInput.value = csrfToken
    form.appendChild(csrfInput)
    
    // Add selected pattern IDs
    const checkboxes = this.element.querySelectorAll('input[type="checkbox"][name="pattern_ids[]"]:checked')
    checkboxes.forEach(checkbox => {
      const input = document.createElement('input')
      input.type = 'hidden'
      input.name = 'pattern_ids[]'
      input.value = checkbox.value
      form.appendChild(input)
    })
    
    document.body.appendChild(form)
    form.submit()
  }
}