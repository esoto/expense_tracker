import { Controller } from "@hotwired/stimulus"

/**
 * Toast Container Controller
 * Manages a global toast notification system for user feedback
 * Handles toast creation, positioning, stacking, and lifecycle
 */
export default class extends Controller {
  connect() {
    // Listen for custom toast events
    this.boundShowToast = this.showToast.bind(this)
    document.addEventListener('toast:show', this.boundShowToast)
    
    // Track active toasts for positioning
    this.activeToasts = []
  }

  disconnect() {
    document.removeEventListener('toast:show', this.boundShowToast)
  }

  /**
   * Show a toast notification
   * @param {CustomEvent} event - Event with detail: { message, type, duration }
   */
  showToast(event) {
    const { message, type = 'info', duration = 5000 } = event.detail
    
    // Create toast element
    const toast = this.createToastElement(message, type, duration)
    
    // Add to container with animation
    this.element.appendChild(toast)
    this.activeToasts.push(toast)
    
    // Trigger entrance animation
    requestAnimationFrame(() => {
      toast.classList.remove('translate-x-full', 'opacity-0')
      toast.classList.add('translate-x-0', 'opacity-100')
    })
    
    // Auto-remove after duration
    if (duration > 0) {
      setTimeout(() => {
        this.removeToast(toast)
      }, duration)
    }
  }

  /**
   * Create a toast element
   */
  createToastElement(message, type, duration) {
    const toast = document.createElement('div')
    toast.className = this.getToastClasses(type)
    toast.setAttribute('data-controller', 'toast')
    toast.setAttribute('data-toast-remove-delay-value', duration)
    toast.style.transition = 'all 300ms ease-in-out'
    
    // Create toast content
    toast.innerHTML = `
      <div class="flex items-center gap-3">
        ${this.getToastIcon(type)}
        <p class="flex-1 text-sm font-medium">${this.escapeHtml(message)}</p>
        <button type="button" 
                class="ml-auto -mx-1.5 -my-1.5 rounded-lg p-1.5 inline-flex h-8 w-8 items-center justify-center hover:bg-white/20 transition-colors"
                data-action="click->toast#remove"
                aria-label="Cerrar notificación">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
          </svg>
        </button>
      </div>
    `
    
    return toast
  }

  /**
   * Get toast classes based on type
   */
  getToastClasses(type) {
    const baseClasses = 'pointer-events-auto mb-3 p-4 rounded-lg shadow-lg transform translate-x-full opacity-0 transition-all duration-300 min-w-[320px] max-w-md'
    
    const typeClasses = {
      success: 'bg-emerald-600 text-white',
      error: 'bg-rose-600 text-white',
      warning: 'bg-amber-600 text-white',
      info: 'bg-teal-700 text-white'
    }
    
    return `${baseClasses} ${typeClasses[type] || typeClasses.info}`
  }

  /**
   * Get toast icon based on type
   */
  getToastIcon(type) {
    const icons = {
      success: `
        <svg class="w-5 h-5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
      `,
      error: `
        <svg class="w-5 h-5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
      `,
      warning: `
        <svg class="w-5 h-5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
        </svg>
      `,
      info: `
        <svg class="w-5 h-5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
      `
    }
    
    return icons[type] || icons.info
  }

  /**
   * Remove a toast with animation
   */
  removeToast(toast) {
    // Trigger exit animation
    toast.classList.remove('translate-x-0', 'opacity-100')
    toast.classList.add('translate-x-full', 'opacity-0')
    
    // Remove from DOM after animation
    setTimeout(() => {
      const index = this.activeToasts.indexOf(toast)
      if (index > -1) {
        this.activeToasts.splice(index, 1)
      }
      if (toast.parentNode === this.element) {
        toast.remove()
      }
    }, 300)
  }

  /**
   * Escape HTML to prevent XSS
   */
  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}