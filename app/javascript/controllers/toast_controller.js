import { Controller } from "@hotwired/stimulus"

/**
 * Toast Controller
 * Manages individual toast notification lifecycle and interactions
 * Works in conjunction with ToastContainerController
 */
export default class extends Controller {
  static values = { removeDelay: Number }
  
  connect() {
    // Auto-remove after delay
    if (this.hasRemoveDelayValue && this.removeDelayValue > 0) {
      this.timeout = setTimeout(() => {
        this.remove()
      }, this.removeDelayValue)
    }
    
    // Add hover behavior to pause auto-remove
    this.element.addEventListener('mouseenter', () => this.pauseAutoRemove())
    this.element.addEventListener('mouseleave', () => this.resumeAutoRemove())
  }
  
  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }
  
  /**
   * Remove the toast with animation
   */
  remove() {
    // Clear any pending timeout
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
    
    // Add fade-out animation
    this.element.classList.remove('translate-x-0', 'opacity-100')
    this.element.classList.add('translate-x-full', 'opacity-0')
    
    // Remove element after animation
    setTimeout(() => {
      this.element.remove()
    }, 300)
  }
  
  /**
   * Pause auto-remove on hover
   */
  pauseAutoRemove() {
    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }
  }
  
  /**
   * Resume auto-remove after hover
   */
  resumeAutoRemove() {
    if (this.hasRemoveDelayValue && this.removeDelayValue > 0 && !this.timeout) {
      this.timeout = setTimeout(() => {
        this.remove()
      }, 2000) // Shorter delay after hovering
    }
  }
}