import { Controller } from "@hotwired/stimulus"

// A reusable toast notification system for displaying user feedback
export default class extends Controller {
  static targets = ["container"]
  static values = {
    position: { type: String, default: "top-right" },
    maxToasts: { type: Number, default: 5 },
    defaultDuration: { type: Number, default: 5000 }
  }

  connect() {
    // Create container if it doesn't exist
    if (!this.hasContainerTarget) {
      this.createContainer()
    }
    
    // Listen for custom toast events
    this.boundShowToast = this.handleToastEvent.bind(this)
    document.addEventListener("toast:show", this.boundShowToast)
    
    // Store active toasts for management
    this.activeToasts = new Set()
  }

  disconnect() {
    // Clean up event listeners
    document.removeEventListener("toast:show", this.boundShowToast)
    
    // Remove all active toasts
    this.activeToasts.forEach(toast => {
      if (toast.parentNode) {
        toast.remove()
      }
    })
    this.activeToasts.clear()
    
    // Remove container if it was created dynamically
    if (this.containerCreated && this.hasContainerTarget) {
      this.containerTarget.remove()
    }
  }

  createContainer() {
    const container = document.createElement("div")
    container.dataset.toastTarget = "container"
    container.className = this.getContainerClasses()
    container.setAttribute("aria-live", "polite")
    container.setAttribute("aria-atomic", "true")
    container.style.zIndex = "9999"
    
    document.body.appendChild(container)
    this.containerCreated = true
  }

  getContainerClasses() {
    const positions = {
      "top-right": "fixed top-4 right-4",
      "top-left": "fixed top-4 left-4",
      "bottom-right": "fixed bottom-4 right-4",
      "bottom-left": "fixed bottom-4 left-4",
      "top-center": "fixed top-4 left-1/2 transform -translate-x-1/2",
      "bottom-center": "fixed bottom-4 left-1/2 transform -translate-x-1/2"
    }
    
    return `${positions[this.positionValue]} space-y-2 pointer-events-none`
  }

  handleToastEvent(event) {
    const { message, type, duration, action, actionText, persistent } = event.detail
    this.show(message, type, duration, action, actionText, persistent)
  }

  // Public method to show a toast
  show(message, type = "info", duration = null, action = null, actionText = null, persistent = false) {
    // Limit number of toasts
    if (this.activeToasts.size >= this.maxToastsValue) {
      const oldestToast = this.activeToasts.values().next().value
      this.removeToast(oldestToast)
    }
    
    const toast = this.createToast(message, type, action, actionText)
    this.containerTarget.appendChild(toast)
    this.activeToasts.add(toast)
    
    // Animate in
    requestAnimationFrame(() => {
      toast.style.transform = "translateX(0)"
      toast.style.opacity = "1"
    })
    
    // Auto-dismiss if not persistent
    if (!persistent) {
      const dismissDuration = duration || this.defaultDurationValue
      const timer = setTimeout(() => {
        this.removeToast(toast)
      }, dismissDuration)
      
      // Store timer for cleanup
      toast.dataset.timerId = timer
    }
    
    return toast
  }

  createToast(message, type, action, actionText) {
    const toast = document.createElement("div")
    toast.className = this.getToastClasses(type)
    toast.style.transform = "translateX(100%)"
    toast.style.opacity = "0"
    toast.style.transition = "all 0.3s ease-in-out"
    toast.setAttribute("role", "alert")
    
    // Build toast content
    const content = document.createElement("div")
    content.className = "flex items-start"
    
    // Add icon
    const icon = this.createIcon(type)
    if (icon) {
      content.appendChild(icon)
    }
    
    // Add message container
    const messageContainer = document.createElement("div")
    messageContainer.className = "flex-1"
    
    // Add message text
    const messageText = document.createElement("p")
    messageText.className = "text-sm font-medium"
    messageText.textContent = message
    messageContainer.appendChild(messageText)
    
    // Add action button if provided
    if (action && actionText) {
      const actionButton = document.createElement("button")
      actionButton.className = "mt-1 text-sm font-medium underline hover:no-underline focus:outline-none focus:underline"
      actionButton.textContent = actionText
      actionButton.onclick = (e) => {
        e.stopPropagation()
        action()
        this.removeToast(toast)
      }
      messageContainer.appendChild(actionButton)
    }
    
    content.appendChild(messageContainer)
    
    // Add close button
    const closeButton = this.createCloseButton(toast)
    content.appendChild(closeButton)
    
    toast.appendChild(content)
    
    // Make toast clickable to dismiss (except on buttons)
    toast.onclick = (e) => {
      if (e.target.tagName !== "BUTTON") {
        this.removeToast(toast)
      }
    }
    
    return toast
  }

  getToastClasses(type) {
    const baseClasses = "pointer-events-auto max-w-sm w-full shadow-lg rounded-lg p-4 mb-2 cursor-pointer"
    
    const typeClasses = {
      success: "bg-emerald-50 text-emerald-900 border border-emerald-200",
      error: "bg-rose-50 text-rose-900 border border-rose-200",
      warning: "bg-amber-50 text-amber-900 border border-amber-200",
      info: "bg-slate-50 text-slate-900 border border-slate-200"
    }
    
    return `${baseClasses} ${typeClasses[type] || typeClasses.info}`
  }

  createIcon(type) {
    const iconContainer = document.createElement("div")
    iconContainer.className = "flex-shrink-0 mr-3"
    
    const icons = {
      success: `
        <svg class="h-5 w-5 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
      `,
      error: `
        <svg class="h-5 w-5 text-rose-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
      `,
      warning: `
        <svg class="h-5 w-5 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
        </svg>
      `,
      info: `
        <svg class="h-5 w-5 text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
      `
    }
    
    iconContainer.innerHTML = icons[type] || icons.info
    return iconContainer
  }

  createCloseButton(toast) {
    const button = document.createElement("button")
    button.className = "flex-shrink-0 ml-3 inline-flex text-current opacity-70 hover:opacity-100 focus:outline-none focus:opacity-100"
    button.setAttribute("aria-label", "Cerrar notificación")
    button.innerHTML = `
      <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
      </svg>
    `
    
    button.onclick = (e) => {
      e.stopPropagation()
      this.removeToast(toast)
    }
    
    return button
  }

  removeToast(toast) {
    if (!toast || !toast.parentNode) return
    
    // Clear timer if exists
    if (toast.dataset.timerId) {
      clearTimeout(parseInt(toast.dataset.timerId))
    }
    
    // Animate out
    toast.style.transform = "translateX(100%)"
    toast.style.opacity = "0"
    
    // Remove after animation
    setTimeout(() => {
      if (toast.parentNode) {
        toast.remove()
      }
      this.activeToasts.delete(toast)
    }, 300)
  }

  // Helper methods for quick access
  success(message, duration = null) {
    return this.show(message, "success", duration)
  }

  error(message, duration = null) {
    return this.show(message, "error", duration)
  }

  warning(message, duration = null) {
    return this.show(message, "warning", duration)
  }

  info(message, duration = null) {
    return this.show(message, "info", duration)
  }
}