import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { removeDelay: Number }
  
  connect() {
    // Auto-remove after delay
    if (this.hasRemoveDelayValue) {
      this.timeout = setTimeout(() => {
        this.remove()
      }, this.removeDelayValue)
    }
  }
  
  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }
  
  remove() {
    // Add fade-out animation
    this.element.classList.add('opacity-0', 'translate-x-full')
    
    // Remove element after animation
    setTimeout(() => {
      this.element.remove()
    }, 300)
  }
}