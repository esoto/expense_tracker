import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "selectAll", "resolveButton"]
  static values = { url: String }
  
  connect() {
    console.log("Bulk actions controller connected")
    this.updateButtonState()
  }

  selectAll(event) {
    const isChecked = event.currentTarget.checked || !this.allChecked()
    
    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = isChecked
    })
    
    this.updateButtonState()
  }

  checkboxChanged() {
    this.updateSelectAllState()
    this.updateButtonState()
  }

  updateSelectAllState() {
    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = this.allChecked()
      this.selectAllTarget.indeterminate = this.someChecked() && !this.allChecked()
    }
  }

  updateButtonState() {
    const selectedCount = this.selectedConflictIds().length
    
    if (this.hasResolveButtonTarget) {
      if (selectedCount > 0) {
        this.resolveButtonTarget.classList.remove('hidden')
        this.resolveButtonTarget.disabled = false
        this.resolveButtonTarget.textContent = `Resolver ${selectedCount} seleccionado${selectedCount > 1 ? 's' : ''}`
      } else {
        this.resolveButtonTarget.classList.add('hidden')
        this.resolveButtonTarget.disabled = true
      }
    }
  }

  async bulkResolve(event) {
    const conflictIds = this.selectedConflictIds()
    
    if (conflictIds.length === 0) {
      this.showError('No hay conflictos seleccionados')
      return
    }
    
    // Show action selection modal
    const action = await this.showActionModal()
    if (!action) return
    
    // Disable button and show loading
    const button = event.currentTarget
    button.disabled = true
    const originalText = button.textContent
    button.textContent = 'Procesando...'
    
    try {
      const response = await fetch(this.urlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          conflict_ids: conflictIds,
          action_type: action
        })
      })
      
      const data = await response.json()
      
      if (data.success) {
        this.showSuccess(`${data.resolved_count} conflictos resueltos exitosamente`)
        
        if (data.failed_count > 0) {
          this.showWarning(`${data.failed_count} conflictos no pudieron ser resueltos`)
        }
        
        // Reload the page or update the UI
        setTimeout(() => {
          window.location.reload()
        }, 1500)
      } else {
        this.showError('Error al resolver conflictos')
      }
    } catch (error) {
      console.error('Error in bulk resolve:', error)
      this.showError('Error de conexión')
    } finally {
      button.disabled = false
      button.textContent = originalText
    }
  }

  showActionModal() {
    return new Promise((resolve) => {
      const modal = document.createElement('div')
      modal.className = 'fixed inset-0 z-50 overflow-y-auto'
      modal.innerHTML = `
        <div class="flex items-center justify-center min-h-screen px-4">
          <div class="fixed inset-0 bg-slate-900 opacity-75"></div>
          <div class="relative bg-white rounded-xl p-6 max-w-md w-full">
            <h3 class="text-lg font-semibold mb-4">Seleccionar Acción de Resolución</h3>
            <p class="text-sm text-slate-600 mb-4">
              ¿Cómo deseas resolver los ${this.selectedConflictIds().length} conflictos seleccionados?
            </p>
            <div class="space-y-2">
              <button data-action="keep_existing" 
                      class="w-full px-4 py-3 text-left bg-emerald-50 hover:bg-emerald-100 rounded-lg border border-emerald-200">
                <span class="font-medium text-emerald-900">Mantener Existente</span>
                <p class="text-sm text-emerald-700">Conservar los gastos existentes y marcar los nuevos como duplicados</p>
              </button>
              <button data-action="keep_new"
                      class="w-full px-4 py-3 text-left bg-amber-50 hover:bg-amber-100 rounded-lg border border-amber-200">
                <span class="font-medium text-amber-900">Mantener Nuevo</span>
                <p class="text-sm text-amber-700">Reemplazar los gastos existentes con los nuevos detectados</p>
              </button>
              <button data-action="keep_both"
                      class="w-full px-4 py-3 text-left bg-teal-50 hover:bg-teal-100 rounded-lg border border-teal-200">
                <span class="font-medium text-teal-900">Mantener Ambos</span>
                <p class="text-sm text-teal-700">Conservar tanto los gastos existentes como los nuevos</p>
              </button>
            </div>
            <div class="mt-4 flex justify-end">
              <button data-action="cancel"
                      class="px-4 py-2 border border-slate-300 rounded-lg text-slate-700 hover:bg-slate-50">
                Cancelar
              </button>
            </div>
          </div>
        </div>
      `
      
      document.body.appendChild(modal)
      
      // Add event listeners
      modal.querySelectorAll('button[data-action]').forEach(button => {
        button.addEventListener('click', () => {
          const action = button.dataset.action
          modal.remove()
          resolve(action === 'cancel' ? null : action)
        })
      })
    })
  }

  selectedConflictIds() {
    return this.checkboxTargets
      .filter(checkbox => checkbox.checked)
      .map(checkbox => checkbox.dataset.conflictId)
  }

  allChecked() {
    return this.checkboxTargets.length > 0 && 
           this.checkboxTargets.every(checkbox => checkbox.checked)
  }

  someChecked() {
    return this.checkboxTargets.some(checkbox => checkbox.checked)
  }

  showSuccess(message) {
    this.showNotification(message, 'success')
  }

  showError(message) {
    this.showNotification(message, 'error')
  }

  showWarning(message) {
    this.showNotification(message, 'warning')
  }

  showNotification(message, type = 'info') {
    const colors = {
      success: 'emerald',
      error: 'rose',
      warning: 'amber',
      info: 'teal'
    }
    
    const color = colors[type] || colors.info
    
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 z-50 p-4 bg-${color}-50 border border-${color}-200 rounded-lg shadow-lg`
    notification.innerHTML = `
      <div class="flex items-center">
        <span class="text-${color}-700">${message}</span>
      </div>
    `
    
    document.body.appendChild(notification)
    
    setTimeout(() => {
      notification.remove()
    }, 5000)
  }
}