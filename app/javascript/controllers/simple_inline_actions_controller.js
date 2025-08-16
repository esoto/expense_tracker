import { Controller } from "@hotwired/stimulus"

// Simple version for testing
export default class extends Controller {
  static targets = ["actionsContainer"]
  
  connect() {
    // Simple direct approach
    this.element.addEventListener('mouseenter', this.handleMouseEnter.bind(this))
    this.element.addEventListener('mouseleave', this.handleMouseLeave.bind(this))
  }
  
  handleMouseEnter() {
    if (this.hasActionsContainerTarget) {
      this.actionsContainerTarget.classList.remove("opacity-0", "pointer-events-none")
      this.actionsContainerTarget.classList.add("opacity-100", "pointer-events-auto")
    }
  }
  
  handleMouseLeave(event) {
    // Don't hide if moving to child element
    if (event.relatedTarget && this.element.contains(event.relatedTarget)) {
      return
    }
    
    if (this.hasActionsContainerTarget) {
      this.actionsContainerTarget.classList.remove("opacity-100", "pointer-events-auto")
      this.actionsContainerTarget.classList.add("opacity-0", "pointer-events-none")
    }
  }
  
  // Action methods for buttons
  toggleCategoryDropdown(event) {
    event.preventDefault()
    const dropdown = this.element.querySelector('[data-inline-actions-target="categoryDropdown"]')
    if (dropdown) {
      dropdown.classList.toggle("hidden")
    }
  }
  
  selectCategory(event) {
    event.preventDefault()
    const dropdown = this.element.querySelector('[data-inline-actions-target="categoryDropdown"]')
    if (dropdown) {
      dropdown.classList.add("hidden")
    }
    // Show toast
    this.showToast("Categoría actualizada")
  }
  
  toggleStatus(event) {
    event.preventDefault()
    this.showToast("Estado actualizado")
  }
  
  duplicateExpense(event) {
    event.preventDefault()
    this.showToast("Gasto duplicado exitosamente")
  }
  
  showDeleteConfirmation(event) {
    event.preventDefault()
    const confirmation = this.element.querySelector('[data-inline-actions-target="deleteConfirmation"]')
    if (confirmation) {
      confirmation.classList.remove("hidden")
    }
  }
  
  cancelDelete(event) {
    event.preventDefault()
    const confirmation = this.element.querySelector('[data-inline-actions-target="deleteConfirmation"]')
    if (confirmation) {
      confirmation.classList.add("hidden")
    }
  }
  
  confirmDelete(event) {
    event.preventDefault()
    const confirmation = this.element.querySelector('[data-inline-actions-target="deleteConfirmation"]')
    if (confirmation) {
      confirmation.classList.add("hidden")
    }
    this.showToast("Gasto eliminado")
    
    // Remove row after a delay
    setTimeout(() => {
      this.element.style.opacity = '0'
      setTimeout(() => {
        this.element.remove()
      }, 200)
    }, 500)
  }
  
  showToast(message) {
    // Simple toast implementation
    const toast = document.createElement('div')
    toast.className = 'fixed bottom-4 right-4 bg-teal-700 text-white px-4 py-2 rounded-lg shadow-lg z-50'
    toast.textContent = message
    document.body.appendChild(toast)
    
    setTimeout(() => {
      toast.remove()
    }, 3000)
  }
}