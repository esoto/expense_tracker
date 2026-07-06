import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("Conflict modal controller connected")

    // Bind once so add/removeEventListener reference the same function.
    this.handleKeydown = this.handleKeydown.bind(this)
    this.handleSubmitEnd = this.handleSubmitEnd.bind(this)

    // Scoped to this controller's element (the whole conflicts page), so it
    // only ever needs to be registered/torn down once — not per open/close.
    this.element.addEventListener("turbo:submit-end", this.handleSubmitEnd)
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-end", this.handleSubmitEnd)
    document.removeEventListener("keydown", this.handleKeydown)
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

      // Registered on open, removed on close — avoids leaking listeners
      // across repeated opens (duplicate addEventListener calls with the
      // same bound function reference are no-ops per the DOM spec).
      document.addEventListener('keydown', this.handleKeydown)
    })
    .catch(error => {
      console.error('Error loading conflict details:', error)
      this.showError('Error al cargar los detalles del conflicto')
    })
  }

  // Bound to backdrop clicks. Uses e.target === e.currentTarget (not
  // stopPropagation on the panel) so a click that bubbles up from inside the
  // modal panel never closes the modal, while a genuine backdrop click does.
  closeOnBackdropClick(event) {
    if (event.target !== event.currentTarget) return
    this.close()
  }

  handleKeydown(event) {
    if (event.key === 'Escape') {
      this.close()
    }
  }

  // Closes the modal once a form submitted from within it (resolve, merge)
  // completes successfully. Scoped to forms inside #conflict_modal so
  // unrelated submissions elsewhere on the page (e.g. bulk actions, undo)
  // never trigger a close.
  handleSubmitEnd(event) {
    const modal = document.getElementById('conflict_modal')
    if (!modal || modal.classList.contains('hidden')) return
    if (!modal.contains(event.target)) return
    if (event.detail && event.detail.success) {
      this.close()
    }
  }

  close() {
    const modal = document.getElementById('conflict_modal')
    if (modal) {
      modal.classList.add('hidden')
      modal.innerHTML = ''
    }
    document.removeEventListener('keydown', this.handleKeydown)
  }

  showError(message) {
    // Show error toast notification
    const notification = document.createElement('div')
    notification.className = 'fixed top-4 right-4 z-50 p-4 bg-rose-50 border border-rose-200 rounded-lg shadow-lg'
    notification.innerHTML = `
      <div class="flex items-center">
        <svg aria-hidden="true" class="w-5 h-5 text-rose-600 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
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
