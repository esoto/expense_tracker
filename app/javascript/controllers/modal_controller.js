import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Add event listener for ESC key
    this.handleEscape = this.handleEscape.bind(this)
    document.addEventListener('keydown', this.handleEscape)
    
    // Prevent body scroll when modal is open
    document.body.style.overflow = 'hidden'
  }

  disconnect() {
    document.removeEventListener('keydown', this.handleEscape)
    document.body.style.overflow = ''
  }

  close(event) {
    // Prevent event from bubbling if clicking on the modal content
    if (event && event.target !== event.currentTarget && !event.currentTarget.hasAttribute('data-action')) {
      return
    }
    
    // Remove the modal element
    this.element.remove()
  }

  handleEscape(event) {
    if (event.key === 'Escape') {
      this.close()
    }
  }
}