import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mergeOptions"]
  
  connect() {
    console.log("Conflict resolution controller connected")
  }

  close() {
    // Close the modal
    const modal = this.element.closest('#conflict_modal')
    if (modal) {
      modal.classList.add('hidden')
      modal.innerHTML = ''
    }
  }

  showMergeOptions() {
    // Toggle merge options visibility
    if (this.hasMergeOptionsTarget) {
      this.mergeOptionsTarget.classList.toggle('hidden')
    }
  }

  async resolve(event) {
    const button = event.currentTarget
    const action = button.dataset.action
    const conflictId = button.dataset.conflictId
    
    // Disable button and show loading
    button.disabled = true
    const originalText = button.textContent
    button.textContent = 'Procesando...'
    
    try {
      const response = await fetch(`/sync_conflicts/${conflictId}/resolve`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          action_type: action
        })
      })
      
      const data = await response.json()
      
      if (data.success) {
        this.showSuccess('Conflicto resuelto exitosamente')
        
        // Update the conflict row if it exists
        const row = document.getElementById(`conflict_${conflictId}`)
        if (row) {
          // Request updated row HTML
          const rowResponse = await fetch(`/sync_conflicts/${conflictId}/row`, {
            headers: {
              'Accept': 'text/html',
              'X-Requested-With': 'XMLHttpRequest'
            }
          })
          
          if (rowResponse.ok) {
            const newRow = await rowResponse.text()
            row.outerHTML = newRow
          }
        }
        
        // Close modal after short delay
        setTimeout(() => this.close(), 1500)
      } else {
        this.showError(data.errors?.join(', ') || 'Error al resolver el conflicto')
        button.disabled = false
        button.textContent = originalText
      }
    } catch (error) {
      console.error('Error resolving conflict:', error)
      this.showError('Error de conexión')
      button.disabled = false
      button.textContent = originalText
    }
  }

  async previewMerge(event) {
    event.preventDefault()
    
    const form = event.target.closest('form')
    const formData = new FormData(form)
    const mergeFields = {}
    
    // Extract merge field selections
    for (let [key, value] of formData.entries()) {
      if (key.startsWith('merge_fields[')) {
        const field = key.match(/merge_fields\[(\w+)\]/)[1]
        mergeFields[field] = value
      }
    }
    
    const conflictId = form.action.match(/sync_conflicts\/(\d+)/)[1]
    
    try {
      const response = await fetch(`/sync_conflicts/${conflictId}/preview_merge`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Accept': 'application/json'
        },
        body: JSON.stringify({ merge_fields: mergeFields })
      })
      
      const data = await response.json()
      
      if (data.success) {
        // Show preview in a modal or update UI
        console.log('Merge preview:', data.preview)
        this.showMergePreview(data.preview, data.changes)
      }
    } catch (error) {
      console.error('Error previewing merge:', error)
      this.showError('Error al previsualizar la fusión')
    }
  }

  showMergePreview(preview, changes) {
    // Create and show preview modal
    const modal = document.createElement('div')
    modal.className = 'fixed inset-0 z-60 overflow-y-auto'
    modal.innerHTML = `
      <div class="flex items-center justify-center min-h-screen px-4">
        <div class="fixed inset-0 bg-slate-900 opacity-75"></div>
        <div class="relative bg-white rounded-xl p-6 max-w-2xl w-full">
          <h3 class="text-lg font-semibold mb-4">Vista Previa de Fusión</h3>
          <div class="space-y-2 max-h-96 overflow-y-auto">
            ${Object.entries(changes).map(([field, change]) => `
              <div class="flex justify-between p-2 bg-slate-50 rounded">
                <span class="font-medium">${field}:</span>
                <span class="text-sm">
                  <span class="text-rose-600 line-through">${change.from}</span>
                  →
                  <span class="text-emerald-600">${change.to}</span>
                </span>
              </div>
            `).join('')}
          </div>
          <div class="mt-4 flex justify-end space-x-2">
            <button onclick="this.closest('.fixed').remove()" 
                    class="px-4 py-2 border border-slate-300 rounded-lg">
              Cerrar
            </button>
          </div>
        </div>
      </div>
    `
    
    document.body.appendChild(modal)
  }

  showSuccess(message) {
    this.showNotification(message, 'success')
  }

  showError(message) {
    this.showNotification(message, 'error')
  }

  showNotification(message, type = 'info') {
    const colors = {
      success: 'emerald',
      error: 'rose',
      info: 'teal'
    }
    
    const color = colors[type] || colors.info
    
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 z-50 p-4 bg-${color}-50 border border-${color}-200 rounded-lg shadow-lg transform transition-all duration-300 translate-x-0`
    notification.innerHTML = `
      <div class="flex items-center">
        <svg class="w-5 h-5 text-${color}-600 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          ${type === 'success' ? 
            '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>' :
            type === 'error' ?
            '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>' :
            '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>'
          }
        </svg>
        <span class="text-${color}-700">${message}</span>
      </div>
    `
    
    document.body.appendChild(notification)
    
    // Animate in
    setTimeout(() => {
      notification.classList.add('translate-x-0')
    }, 10)
    
    // Remove after 5 seconds
    setTimeout(() => {
      notification.classList.add('translate-x-full', 'opacity-0')
      setTimeout(() => notification.remove(), 300)
    }, 5000)
  }
}