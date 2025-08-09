import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]
  
  connect() {
    this.open = false
  }
  
  toggle() {
    this.open = !this.open
    
    if (this.hasMenuTarget) {
      if (this.open) {
        this.menuTarget.classList.remove('hidden')
      } else {
        this.menuTarget.classList.add('hidden')
      }
    }
  }
  
  close(event) {
    if (!this.element.contains(event.target)) {
      this.open = false
      if (this.hasMenuTarget) {
        this.menuTarget.classList.add('hidden')
      }
    }
  }
  
  // Close when clicking outside
  disconnect() {
    document.removeEventListener('click', this.close)
  }
}