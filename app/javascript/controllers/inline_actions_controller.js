import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["actionsContainer", "categoryDropdown", "deleteConfirmation", "statusButton", "duplicateButton"]
  
  connect() {
    // Remove debug logging for production
    this.setupEventListeners()
    this.actionsVisible = false
  }
  
  disconnect() {
    this.removeEventListeners()
  }
  
  setupEventListeners() {
    // Click outside to close dropdowns
    this.clickOutsideHandler = (event) => this.handleClickOutside(event)
    document.addEventListener('click', this.clickOutsideHandler)
    
    // Keyboard shortcuts
    this.keyboardHandler = (event) => this.handleKeyboard(event)
    this.element.addEventListener('keydown', this.keyboardHandler)
  }
  
  removeEventListeners() {
    if (this.clickOutsideHandler) {
      document.removeEventListener('click', this.clickOutsideHandler)
    }
    if (this.keyboardHandler) {
      this.element.removeEventListener('keydown', this.keyboardHandler)
    }
  }
  
  handleClickOutside(event) {
    // Close dropdowns if clicking outside
    if (this.hasCategoryDropdownTarget && !this.categoryDropdownTarget.contains(event.target)) {
      const button = this.element.querySelector('[data-action*="toggleCategoryDropdown"]')
      if (!button || !button.contains(event.target)) {
        this.closeCategoryDropdown()
      }
    }
    
    if (this.hasDeleteConfirmationTarget && !this.deleteConfirmationTarget.contains(event.target)) {
      const button = this.element.querySelector('[data-action*="showDeleteConfirmation"]')
      if (!button || !button.contains(event.target)) {
        this.closeDeleteConfirmation()
      }
    }
  }
  
  handleKeyboard(event) {
    // Handle keyboard shortcuts
    if (event.key === 'Escape') {
      this.closeCategoryDropdown()
      this.closeDeleteConfirmation()
      return
    }
    
    // Only handle shortcuts when row is focused/hovered
    if (!this.element.matches(':hover, :focus-within')) return
    
    switch(event.key.toLowerCase()) {
      case 'c':
        event.preventDefault()
        this.toggleCategoryDropdown(event)
        break
      case 'r':
        event.preventDefault()
        this.toggleStatus(event)
        break
      case 'd':
        event.preventDefault()
        this.duplicateExpense(event)
        break
      case 'delete':
      case 'backspace':
        if (event.metaKey || event.ctrlKey) {
          event.preventDefault()
          this.showDeleteConfirmation(event)
        }
        break
    }
  }

  // Note: Hover actions are handled by CSS, not JavaScript
  // This ensures smooth hover interactions without JavaScript delays

  toggleCategoryDropdown(event) {
    event.preventDefault()
    event.stopPropagation()
    
    if (this.hasCategoryDropdownTarget) {
      const isHidden = this.categoryDropdownTarget.classList.contains("hidden")
      
      // Close delete confirmation if open
      this.closeDeleteConfirmation()
      
      if (isHidden) {
        this.openCategoryDropdown()
      } else {
        this.closeCategoryDropdown()
      }
    }
  }
  
  openCategoryDropdown() {
    if (this.hasCategoryDropdownTarget) {
      this.categoryDropdownTarget.classList.remove("hidden")
      this.categoryDropdownTarget.classList.add("animate-fade-in")
      
      // Position dropdown to avoid viewport clipping
      this.positionDropdown(this.categoryDropdownTarget)
    }
  }

  closeCategoryDropdown() {
    if (this.hasCategoryDropdownTarget) {
      this.categoryDropdownTarget.classList.add("hidden")
      this.categoryDropdownTarget.classList.remove("animate-fade-in")
    }
  }
  
  positionDropdown(dropdown) {
    // Reset position
    dropdown.style.top = ''
    dropdown.style.bottom = ''
    dropdown.style.left = ''
    dropdown.style.right = ''
    
    // Get dropdown dimensions
    const rect = dropdown.getBoundingClientRect()
    const viewportHeight = window.innerHeight
    const viewportWidth = window.innerWidth
    
    // Check if dropdown would extend beyond viewport bottom
    if (rect.bottom > viewportHeight - 20) {
      // Position above the button
      dropdown.style.bottom = '100%'
      dropdown.style.top = 'auto'
      dropdown.style.marginBottom = '0.25rem'
      dropdown.style.marginTop = '0'
    } else {
      // Position below the button (default)
      dropdown.style.top = '100%'
      dropdown.style.bottom = 'auto'
      dropdown.style.marginTop = '0.25rem'
      dropdown.style.marginBottom = '0'
    }
    
    // Check horizontal positioning
    if (rect.right > viewportWidth - 20) {
      dropdown.style.right = '0'
      dropdown.style.left = 'auto'
    } else {
      dropdown.style.right = '0'
      dropdown.style.left = 'auto'
    }
  }

  selectCategory(event) {
    event.preventDefault()
    event.stopPropagation()
    
    const categoryId = event.currentTarget.dataset.categoryId
    const categoryName = event.currentTarget.dataset.categoryName
    
    // Close dropdown immediately for better UX
    this.closeCategoryDropdown()
    
    // Get expense ID from the row
    const expenseId = this.element.id.replace('expense_row_', '')
    
    // Disable the button during request
    const button = this.element.querySelector('[data-action*="toggleCategoryDropdown"]')
    if (button) {
      button.disabled = true
      button.classList.add('opacity-50', 'cursor-not-allowed')
    }
    
    fetch(`/expenses/${expenseId}/correct_category`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.csrfToken,
        'Accept': 'text/vnd.turbo-stream.html'
      },
      body: JSON.stringify({ category_id: categoryId })
    })
    .then(response => {
      if (response.ok) {
        this.showToast('Categoría actualizada', 'success')
        return response.text()
      } else {
        throw new Error('Failed to update category')
      }
    })
    .then(turboStream => {
      if (turboStream) {
        Turbo.renderStreamMessage(turboStream)
      }
    })
    .catch(error => {
      console.error('Error updating category:', error)
      this.showToast('Error al actualizar categoría', 'error')
    })
    .finally(() => {
      // Re-enable the button
      if (button) {
        button.disabled = false
        button.classList.remove('opacity-50', 'cursor-not-allowed')
      }
    })
  }

  toggleStatus(event) {
    event.preventDefault()
    event.stopPropagation()
    
    const expenseId = this.element.id.replace('expense_row_', '')
    const currentStatus = this.element.dataset.inlineActionsCurrentStatusValue || 'pending'
    const newStatus = currentStatus === 'pending' ? 'processed' : 'pending'
    
    fetch(`/expenses/${expenseId}/update_status`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.csrfToken,
        'Accept': 'text/vnd.turbo-stream.html'
      },
      body: JSON.stringify({ status: newStatus })
    })
    .then(response => {
      if (response.ok) {
        this.element.dataset.inlineActionsCurrentStatusValue = newStatus
        this.showToast(
          newStatus === 'processed' ? 'Marcado como revisado' : 'Marcado como pendiente',
          'success'
        )
        return response.text()
      } else {
        throw new Error('Failed to update status')
      }
    })
    .then(turboStream => {
      if (turboStream) {
        Turbo.renderStreamMessage(turboStream)
      }
    })
    .catch(error => {
      console.error('Error:', error)
      this.showToast('Error al actualizar estado', 'error')
    })
  }

  duplicateExpense(event) {
    event.preventDefault()
    event.stopPropagation()
    
    const expenseId = this.element.id.replace('expense_row_', '')
    
    fetch(`/expenses/${expenseId}/duplicate`, {
      method: 'POST',
      headers: {
        'X-CSRF-Token': this.csrfToken,
        'Accept': 'text/vnd.turbo-stream.html'
      }
    })
    .then(response => {
      if (response.ok) {
        this.showToast('Gasto duplicado exitosamente', 'success')
        return response.text()
      } else {
        throw new Error('Failed to duplicate')
      }
    })
    .then(turboStream => {
      if (turboStream) {
        Turbo.renderStreamMessage(turboStream)
      }
    })
    .catch(error => {
      console.error('Error:', error)
      this.showToast('Error al duplicar gasto', 'error')
    })
  }

  showDeleteConfirmation(event) {
    event.preventDefault()
    event.stopPropagation()
    
    // Close category dropdown if open
    this.closeCategoryDropdown()
    
    if (this.hasDeleteConfirmationTarget) {
      this.deleteConfirmationTarget.classList.remove("hidden")
      this.deleteConfirmationTarget.classList.add("animate-fade-in")
      
      // Position modal to avoid viewport clipping
      this.positionDropdown(this.deleteConfirmationTarget)
    }
  }

  closeDeleteConfirmation() {
    if (this.hasDeleteConfirmationTarget) {
      this.deleteConfirmationTarget.classList.add("hidden")
      this.deleteConfirmationTarget.classList.remove("animate-fade-in")
    }
  }

  cancelDelete(event) {
    event.preventDefault()
    this.closeDeleteConfirmation()
  }

  confirmDelete(event) {
    event.preventDefault()
    event.stopPropagation()
    
    // Close the confirmation modal
    this.closeDeleteConfirmation()
    
    const expenseId = this.element.id.replace('expense_row_', '')
    
    // Disable the row during deletion
    this.element.classList.add('opacity-50', 'pointer-events-none')
    
    fetch(`/expenses/${expenseId}`, {
      method: 'DELETE',
      headers: {
        'X-CSRF-Token': this.csrfToken,
        'Accept': 'text/vnd.turbo-stream.html'
      }
    })
    .then(response => {
      if (response.ok) {
        // Animate row removal
        this.element.style.transition = 'all 300ms ease-out'
        this.element.style.transform = 'translateX(100%)'
        this.element.style.opacity = '0'
        
        setTimeout(() => {
          this.element.remove()
        }, 300)
        
        this.showToast('Gasto eliminado', 'success')
        return response.text()
      } else {
        throw new Error('Failed to delete')
      }
    })
    .then(turboStream => {
      // Handle any turbo stream responses
      if (turboStream && turboStream.includes('turbo-stream')) {
        Turbo.renderStreamMessage(turboStream)
      }
    })
    .catch(error => {
      console.error('Error deleting expense:', error)
      this.element.classList.remove('opacity-50', 'pointer-events-none')
      this.showToast('Error al eliminar gasto', 'error')
    })
  }

  showToast(message, type = 'info') {
    // Create and dispatch custom event for toast
    const event = new CustomEvent('toast:show', {
      bubbles: true,
      detail: { message, type }
    })
    document.dispatchEvent(event)
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ''
  }
}