import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("Conflict modal controller connected")
  }

  open(event) {
    const conflictId = event.currentTarget.dataset.conflictId
    
    // Fetch conflict details and show modal
    fetch(`/sync_conflicts/${conflictId}`, {
      headers: {
        'Accept': 'text/html',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    .then(response => response.text())
    .then(html => {
      // Create modal container if it doesn't exist
      let modal = document.getElementById('conflict_modal')
      if (!modal) {
        modal = document.createElement('div')
        modal.id = 'conflict_modal'
        modal.dataset.controller = 'conflict-modal'
        document.body.appendChild(modal)
      }
      
      // Insert content and show
      modal.innerHTML = html
      modal.classList.remove('hidden')
    })
    .catch(error => {
      console.error('Error loading conflict details:', error)
      this.showError('Error al cargar los detalles del conflicto')
    })
  }

  close() {
    const modal = document.getElementById('conflict_modal')
    if (modal) {
      modal.classList.add('hidden')
      modal.innerHTML = ''
    }
  }

  showError(message) {
    // Show error toast notification
    const notification = document.createElement('div')
    notification.className = 'fixed top-4 right-4 z-50 p-4 bg-rose-50 border border-rose-200 rounded-lg shadow-lg'
    notification.innerHTML = `
      <div class="flex items-center">
        <svg class="w-5 h-5 text-rose-600 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
        <span class="text-rose-700">${message}</span>
      </div>
    `
    
    document.body.appendChild(notification)
    
    // Remove after 5 seconds
    setTimeout(() => {
      notification.remove()
    }, 5000)
  }
}