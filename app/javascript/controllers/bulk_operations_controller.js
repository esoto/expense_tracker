import { Controller } from "@hotwired/stimulus"

/**
 * Bulk Operations Controller
 * Manages bulk operations modal for selected expenses with progress tracking
 * Provides categorization, status updates, and deletion operations
 * Integrates with batch selection system for seamless workflow
 */
export default class extends Controller {
  static targets = [
    "modal",
    "overlay",
    "form",
    "categorySelect",
    "statusSelect",
    "confirmCheckbox",
    "submitButton",
    "cancelButton",
    "closeButton",
    "selectedCount",
    "operationType",
    "progressBar",
    "progressContainer",
    "progressText",
    "progressPercentage",
    "errorContainer",
    "errorList",
    "successMessage",
    "operationSection"
  ]
  
  static values = {
    selectedIds: { type: Array, default: [] },
    selectedCount: { type: Number, default: 0 },
    currentOperation: { type: String, default: "" },
    isProcessing: { type: Boolean, default: false }
  }

  connect() {
    // Listen for bulk operations request from batch selection controller
    this.handleOpenRequest = this.handleOpenRequest.bind(this)
    // Listen for the correct event name that batch_selection_controller dispatches
    document.addEventListener('batch-selection:openBulkOperations', this.handleOpenRequest)
    
    // Also ensure the modal element is properly targeted
    this.modalTarget = document.getElementById('bulk_operations_modal')
    
    // Set up keyboard navigation
    this.setupKeyboardNavigation()
    
    // Initialize form state
    this.resetForm()
  }

  disconnect() {
    // Clean up event listeners
    document.removeEventListener('batch-selection:openBulkOperations', this.handleOpenRequest)
    
    // Clean up keyboard navigation
    if (this.keydownHandler) {
      document.removeEventListener('keydown', this.keydownHandler)
    }
  }

  /**
   * Handle open request from batch selection controller
   */
  handleOpenRequest(event) {
    const { selectedIds, selectedCount } = event.detail
    this.selectedIdsValue = selectedIds
    this.selectedCountValue = selectedCount
    
    // Update modal content
    this.updateSelectedCount()
    
    // Open modal
    this.open()
  }

  /**
   * Open the modal
   */
  open() {
    // Ensure modal element exists
    if (!this.modalTarget) {
      this.modalTarget = document.getElementById('bulk_operations_modal')
    }
    
    if (!this.modalTarget) {
      console.error('Bulk operations modal not found')
      return
    }
    
    // Show modal with animation
    this.modalTarget.classList.remove('hidden')
    this.modalTarget.setAttribute('aria-hidden', 'false')
    
    // Animate in
    requestAnimationFrame(() => {
      if (this.hasOverlayTarget) {
        this.overlayTarget.classList.add('opacity-100')
      }
      const formElement = this.modalTarget.querySelector('[data-bulk-operations-target="form"]')
      if (formElement) {
        formElement.classList.add('translate-y-0', 'opacity-100')
        formElement.classList.remove('translate-y-4', 'opacity-0')
      }
    })
    
    // Focus management
    this.previousActiveElement = document.activeElement
    this.focusFirstElement()
    
    // Trap focus
    this.trapFocus()
  }

  /**
   * Close the modal
   */
  close() {
    // Don't close if processing
    if (this.isProcessingValue) {
      return
    }
    
    // Animate out
    this.overlayTarget.classList.remove('opacity-100')
    const formElement = this.modalTarget.querySelector('[data-bulk-operations-target="form"]')
    formElement.classList.remove('translate-y-0', 'opacity-100')
    formElement.classList.add('translate-y-4', 'opacity-0')
    
    // Hide after animation
    setTimeout(() => {
      this.modalTarget.classList.add('hidden')
      this.modalTarget.setAttribute('aria-hidden', 'true')
      
      // Reset form
      this.resetForm()
      
      // Restore focus
      if (this.previousActiveElement) {
        this.previousActiveElement.focus()
      }
    }, 200)
    
    // Remove focus trap
    this.removeFocusTrap()
  }

  /**
   * Handle operation type change
   */
  changeOperation(event) {
    const operationType = event.currentTarget.value
    this.currentOperationValue = operationType
    
    // Hide all operation sections
    this.operationSectionTargets.forEach(section => {
      section.classList.add('hidden')
    })
    
    // Show selected operation section
    const selectedSection = this.element.querySelector(`[data-operation-type="${operationType}"]`)
    if (selectedSection) {
      selectedSection.classList.remove('hidden')
    }
    
    // Update submit button text
    this.updateSubmitButton(operationType)
    
    // Reset confirmation for delete operation
    if (operationType === 'delete' && this.hasConfirmCheckboxTarget) {
      this.confirmCheckboxTarget.checked = false
    }
  }

  /**
   * Update submit button based on operation
   */
  updateSubmitButton(operationType) {
    const buttonTexts = {
      categorize: 'Categorizar Gastos',
      status: 'Actualizar Estado',
      delete: 'Eliminar Gastos'
    }
    
    const buttonClasses = {
      categorize: ['bg-teal-700', 'hover:bg-teal-800'],
      status: ['bg-amber-600', 'hover:bg-amber-700'],
      delete: ['bg-rose-600', 'hover:bg-rose-700']
    }
    
    if (this.hasSubmitButtonTarget) {
      // Update text
      this.submitButtonTarget.textContent = buttonTexts[operationType] || 'Ejecutar'
      
      // Enable button for non-delete operations
      if (operationType !== 'delete') {
        this.submitButtonTarget.disabled = false
        this.submitButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
      }
      
      // Remove all color classes
      this.submitButtonTarget.classList.remove(
        'bg-teal-700', 'hover:bg-teal-800',
        'bg-amber-600', 'hover:bg-amber-700',
        'bg-rose-600', 'hover:bg-rose-700'
      )
      
      // Add operation-specific color classes
      const classes = buttonClasses[operationType] || buttonClasses.categorize
      this.submitButtonTarget.classList.add(...classes)
    }
  }

  /**
   * Handle delete confirmation checkbox
   */
  toggleDeleteConfirmation(event) {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = !event.currentTarget.checked
      
      if (event.currentTarget.checked) {
        this.submitButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
      } else {
        this.submitButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
      }
    }
  }

  /**
   * Submit bulk operation
   */
  async submit(event) {
    event.preventDefault()
    
    // Prevent double submission
    if (this.isProcessingValue) {
      return
    }
    
    // Validate operation
    if (!this.validateOperation()) {
      return
    }
    
    // Start processing
    this.startProcessing()
    
    try {
      // Determine endpoint and data based on operation
      const { endpoint, data } = this.prepareRequest()
      
      // Send request
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify(data)
      })
      
      const result = await response.json()
      
      if (response.ok && result.success) {
        this.handleSuccess(result)
      } else {
        this.handleError(result)
      }
    } catch (error) {
      this.handleError({ message: 'Error de conexión. Por favor, intenta nuevamente.' })
    }
  }

  /**
   * Validate operation before submission
   */
  validateOperation() {
    const operation = this.currentOperationValue
    
    if (!operation) {
      this.showError('Por favor selecciona un tipo de operación')
      return false
    }
    
    switch (operation) {
      case 'categorize':
        if (!this.hasCategorySelectTarget || !this.categorySelectTarget.value) {
          this.showError('Por favor selecciona una categoría')
          return false
        }
        break
      case 'status':
        if (!this.hasStatusSelectTarget || !this.statusSelectTarget.value) {
          this.showError('Por favor selecciona un estado')
          return false
        }
        break
      case 'delete':
        if (!this.hasConfirmCheckboxTarget || !this.confirmCheckboxTarget.checked) {
          this.showError('Por favor confirma la eliminación')
          return false
        }
        break
    }
    
    return true
  }

  /**
   * Prepare request data
   */
  prepareRequest() {
    const operation = this.currentOperationValue
    const baseData = {
      expense_ids: this.selectedIdsValue
    }
    
    switch (operation) {
      case 'categorize':
        return {
          endpoint: '/expenses/bulk_categorize',
          data: {
            ...baseData,
            category_id: this.categorySelectTarget.value
          }
        }
      case 'status':
        return {
          endpoint: '/expenses/bulk_update_status',
          data: {
            ...baseData,
            status: this.statusSelectTarget.value
          }
        }
      case 'delete':
        return {
          endpoint: '/expenses/bulk_destroy',
          data: baseData
        }
      default:
        throw new Error('Operación no válida')
    }
  }

  /**
   * Start processing state
   */
  startProcessing() {
    this.isProcessingValue = true
    
    // Disable form elements
    this.disableFormElements()
    
    // Show progress container
    if (this.hasProgressContainerTarget) {
      this.progressContainerTarget.classList.remove('hidden')
    }
    
    // Hide error container
    if (this.hasErrorContainerTarget) {
      this.errorContainerTarget.classList.add('hidden')
    }
    
    // Initialize progress
    this.updateProgress(0, `Procesando ${this.selectedCountValue} gastos...`)
  }

  /**
   * Update progress display
   */
  updateProgress(percentage, message) {
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${percentage}%`
    }
    
    if (this.hasProgressPercentageTarget) {
      this.progressPercentageTarget.textContent = `${Math.round(percentage)}%`
    }
    
    if (this.hasProgressTextTarget && message) {
      this.progressTextTarget.textContent = message
    }
  }

  /**
   * Handle successful operation
   */
  handleSuccess(result) {
    // Update progress to 100%
    this.updateProgress(100, result.message || 'Operación completada exitosamente')
    
    // Show success message
    if (this.hasSuccessMessageTarget) {
      const messageElement = this.successMessageTarget.querySelector('p')
      if (messageElement) {
        messageElement.textContent = result.message || 'Operación completada exitosamente'
      } else {
        this.successMessageTarget.textContent = result.message || 'Operación completada exitosamente'
      }
      this.successMessageTarget.classList.remove('hidden')
    }
    
    // Handle partial failures if any
    if (result.failures && result.failures.length > 0) {
      this.showPartialErrors(result.failures)
    }
    
    // Dispatch success event
    this.dispatch('operationCompleted', {
      detail: {
        operation: this.currentOperationValue,
        affectedCount: result.affected_count || this.selectedCountValue,
        failures: result.failures || []
      }
    })
    
    // Clear selection in batch selection controller
    document.dispatchEvent(new CustomEvent('bulk-operations:completed', {
      detail: {
        operation: this.currentOperationValue,
        success: true
      }
    }))
    
    // Close modal after delay
    setTimeout(() => {
      this.close()
      
      // Reload the page or update via Turbo
      if (result.reload) {
        window.location.reload()
      } else if (result.turbo_stream) {
        // Let Turbo handle the stream response
        Turbo.renderStreamMessage(result.turbo_stream)
      }
    }, 2000)
  }

  /**
   * Handle operation error
   */
  handleError(error) {
    this.isProcessingValue = false
    
    // Hide progress
    if (this.hasProgressContainerTarget) {
      this.progressContainerTarget.classList.add('hidden')
    }
    
    // Show error
    this.showError(error.message || 'Ocurrió un error al procesar la operación')
    
    // Show detailed errors if available
    if (error.errors && Array.isArray(error.errors)) {
      this.showDetailedErrors(error.errors)
    }
    
    // Re-enable form
    this.enableFormElements()
  }

  /**
   * Show error message
   */
  showError(message) {
    if (this.hasErrorContainerTarget) {
      this.errorContainerTarget.classList.remove('hidden')
      
      if (this.hasErrorListTarget) {
        this.errorListTarget.innerHTML = `<li>${message}</li>`
      }
    }
  }

  /**
   * Show detailed errors
   */
  showDetailedErrors(errors) {
    if (this.hasErrorListTarget) {
      this.errorListTarget.innerHTML = errors
        .map(error => `<li>${error}</li>`)
        .join('')
    }
  }

  /**
   * Show partial errors for failed items
   */
  showPartialErrors(failures) {
    if (failures.length > 0 && this.hasErrorContainerTarget) {
      const message = `${failures.length} gastos no pudieron ser procesados`
      this.errorContainerTarget.classList.remove('hidden')
      
      if (this.hasErrorListTarget) {
        this.errorListTarget.innerHTML = `
          <li class="font-semibold">${message}</li>
          ${failures.slice(0, 5).map(f => `<li class="ml-4">• Gasto #${f.id}: ${f.error}</li>`).join('')}
          ${failures.length > 5 ? `<li class="ml-4 text-slate-500">... y ${failures.length - 5} más</li>` : ''}
        `
      }
    }
  }

  /**
   * Update selected count display
   */
  updateSelectedCount() {
    if (this.hasSelectedCountTarget) {
      this.selectedCountTargets.forEach(target => {
        target.textContent = this.selectedCountValue
      })
    }
  }

  /**
   * Reset form to initial state
   */
  resetForm() {
    this.currentOperationValue = ""
    this.isProcessingValue = false
    
    // Reset operation selection
    const operationRadios = this.element.querySelectorAll('input[name="operation_type"]')
    operationRadios.forEach(radio => {
      radio.checked = false
    })
    
    // Hide all operation sections
    this.operationSectionTargets.forEach(section => {
      section.classList.add('hidden')
    })
    
    // Reset form fields
    if (this.hasCategorySelectTarget) {
      this.categorySelectTarget.value = ""
    }
    
    if (this.hasStatusSelectTarget) {
      this.statusSelectTarget.value = ""
    }
    
    if (this.hasConfirmCheckboxTarget) {
      this.confirmCheckboxTarget.checked = false
    }
    
    // Hide progress and errors
    if (this.hasProgressContainerTarget) {
      this.progressContainerTarget.classList.add('hidden')
    }
    
    if (this.hasErrorContainerTarget) {
      this.errorContainerTarget.classList.add('hidden')
    }
    
    if (this.hasSuccessMessageTarget) {
      this.successMessageTarget.classList.add('hidden')
    }
    
    // Reset submit button
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
      this.submitButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
    }
    
    // Enable form elements
    this.enableFormElements()
  }

  /**
   * Disable form elements during processing
   */
  disableFormElements() {
    const elements = this.formTarget.querySelectorAll('input, select, button')
    elements.forEach(el => {
      el.disabled = true
      el.classList.add('opacity-50', 'cursor-not-allowed')
    })
  }

  /**
   * Enable form elements
   */
  enableFormElements() {
    const elements = this.formTarget.querySelectorAll('input, select')
    elements.forEach(el => {
      el.disabled = false
      el.classList.remove('opacity-50', 'cursor-not-allowed')
    })
    
    // Enable buttons conditionally
    if (this.hasSubmitButtonTarget) {
      const shouldDisable = this.currentOperationValue === 'delete' && 
                           (!this.hasConfirmCheckboxTarget || !this.confirmCheckboxTarget.checked)
      this.submitButtonTarget.disabled = shouldDisable || !this.currentOperationValue
    }
    
    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.disabled = false
      this.cancelButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
    }
  }

  /**
   * Set up keyboard navigation
   */
  setupKeyboardNavigation() {
    this.keydownHandler = (event) => {
      // Only handle if modal is open
      if (this.modalTarget.classList.contains('hidden')) {
        return
      }
      
      // Escape to close (unless processing)
      if (event.key === 'Escape' && !this.isProcessingValue) {
        event.preventDefault()
        this.close()
      }
    }
    
    document.addEventListener('keydown', this.keydownHandler)
  }

  /**
   * Trap focus within modal
   */
  trapFocus() {
    const focusableElements = this.modalTarget.querySelectorAll(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    )
    
    this.firstFocusable = focusableElements[0]
    this.lastFocusable = focusableElements[focusableElements.length - 1]
    
    this.focusTrapHandler = (event) => {
      if (event.key !== 'Tab') return
      
      if (event.shiftKey) {
        if (document.activeElement === this.firstFocusable) {
          event.preventDefault()
          this.lastFocusable.focus()
        }
      } else {
        if (document.activeElement === this.lastFocusable) {
          event.preventDefault()
          this.firstFocusable.focus()
        }
      }
    }
    
    this.modalTarget.addEventListener('keydown', this.focusTrapHandler)
  }

  /**
   * Remove focus trap
   */
  removeFocusTrap() {
    if (this.focusTrapHandler) {
      this.modalTarget.removeEventListener('keydown', this.focusTrapHandler)
    }
  }

  /**
   * Focus first element in modal
   */
  focusFirstElement() {
    const firstInput = this.modalTarget.querySelector('input[type="radio"]')
    if (firstInput) {
      firstInput.focus()
    } else if (this.hasCloseButtonTarget) {
      this.closeButtonTarget.focus()
    }
  }

  /**
   * Get CSRF token
   */
  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ''
  }
}