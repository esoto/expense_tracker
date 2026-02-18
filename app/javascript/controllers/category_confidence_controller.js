import { Controller } from "@hotwired/stimulus"
import { shouldSuppressShortcut } from "../utilities/keyboard_shortcut_helpers"

export default class extends Controller {
  static targets = ["badge", "tooltip", "correctionPanel", "correctionTrigger", "categorySelect"]
  static values = {
    expenseId: Number,
    level: String,
    percentage: Number,
    explanation: String,
    categories: Array
  }

  connect() {
    this.setupTooltip()
    this.setupKeyboardShortcuts()
    this.setupTouchInteractions()
  }

  disconnect() {
    this.removeKeyboardShortcuts()
    this.removeTouchInteractions()
  }

  // Setup tooltip for confidence explanation
  setupTooltip() {
    if (!this.hasTooltipTarget) return

    this.badgeTarget.addEventListener("mouseenter", this.showTooltip.bind(this))
    this.badgeTarget.addEventListener("mouseleave", this.hideTooltip.bind(this))
    this.badgeTarget.addEventListener("focus", this.showTooltip.bind(this))
    this.badgeTarget.addEventListener("blur", this.hideTooltip.bind(this))
  }

  showTooltip(event) {
    if (!this.hasTooltipTarget) {
      this.createTooltip()
    }
    
    const rect = this.badgeTarget.getBoundingClientRect()
    this.tooltipTarget.style.top = `${rect.bottom + 8}px`
    this.tooltipTarget.style.left = `${rect.left}px`
    this.tooltipTarget.classList.remove("hidden")
    this.tooltipTarget.classList.add("opacity-100")
  }

  hideTooltip() {
    if (this.hasTooltipTarget) {
      this.tooltipTarget.classList.add("hidden")
      this.tooltipTarget.classList.remove("opacity-100")
    }
  }

  createTooltip() {
    const tooltip = document.createElement("div")
    tooltip.classList.add(
      "absolute", "z-50", "p-2", "text-xs", "text-white", "bg-slate-800",
      "rounded-lg", "shadow-lg", "transition-opacity", "duration-200",
      "max-w-xs", "hidden", "opacity-0"
    )
    tooltip.setAttribute("data-category-confidence-target", "tooltip")
    
    // Add arrow
    const arrow = document.createElement("div")
    arrow.classList.add(
      "absolute", "-top-1", "left-4", "w-2", "h-2",
      "bg-slate-800", "transform", "rotate-45"
    )
    tooltip.appendChild(arrow)
    
    // Add content
    const content = document.createElement("div")
    content.classList.add("relative")
    content.innerHTML = this.getTooltipContent()
    tooltip.appendChild(content)
    
    document.body.appendChild(tooltip)
    this.tooltipTarget = tooltip
  }

  getTooltipContent() {
    let content = `<div class="font-semibold mb-1">Confianza: ${this.percentageValue}%</div>`
    
    if (this.explanationValue) {
      content += `<div class="text-slate-300">${this.explanationValue}</div>`
    }
    
    const levelDescriptions = {
      high: "Alta probabilidad de categorización correcta",
      medium: "Categorización probable pero puede requerir revisión",
      low: "Baja confianza - se recomienda revisar",
      very_low: "Muy baja confianza - requiere revisión manual"
    }
    
    if (levelDescriptions[this.levelValue]) {
      content += `<div class="mt-1 pt-1 border-t border-slate-600 text-slate-400">
                    ${levelDescriptions[this.levelValue]}
                  </div>`
    }
    
    // Add keyboard shortcut hint
    if (this.levelValue === "low" || this.levelValue === "very_low") {
      content += `<div class="mt-1 text-slate-500">
                    Presiona 'C' para corregir
                  </div>`
    }
    
    return content
  }

  // Show correction interface
  showCorrection(event) {
    event.preventDefault()
    
    if (!this.hasCorrectionPanelTarget) {
      this.createCorrectionPanel()
    }
    
    this.correctionPanelTarget.classList.remove("hidden")
    this.animateIn(this.correctionPanelTarget)
    
    // Focus on category select for accessibility
    if (this.hasCategorySelectTarget) {
      this.categorySelectTarget.focus()
    }
  }

  hideCorrection() {
    if (this.hasCorrectionPanelTarget) {
      this.animateOut(this.correctionPanelTarget).then(() => {
        this.correctionPanelTarget.classList.add("hidden")
      })
    }
  }

  createCorrectionPanel() {
    const panel = document.createElement("div")
    panel.classList.add(
      "absolute", "z-40", "mt-2", "p-3", "bg-white", "rounded-lg",
      "shadow-xl", "border", "border-slate-200", "hidden"
    )
    panel.setAttribute("data-category-confidence-target", "correctionPanel")
    
    panel.innerHTML = `
      <div class="text-sm font-medium text-slate-700 mb-2">Corregir categoría</div>
      <div class="space-y-2">
        <select data-category-confidence-target="categorySelect"
                class="w-full rounded-md border-slate-300 text-sm focus:border-teal-500 focus:ring-teal-500">
          <option value="">Seleccionar categoría...</option>
        </select>
        <div class="flex gap-2">
          <button data-action="click->category-confidence#applyCorrection"
                  class="flex-1 px-3 py-1.5 bg-teal-700 text-white text-sm rounded-lg hover:bg-teal-800">
            Aplicar
          </button>
          <button data-action="click->category-confidence#hideCorrection"
                  class="flex-1 px-3 py-1.5 bg-slate-200 text-slate-700 text-sm rounded-lg hover:bg-slate-300">
            Cancelar
          </button>
        </div>
      </div>
    `
    
    // Position relative to the trigger
    if (this.hasCorrectionTriggerTarget) {
      this.correctionTriggerTarget.parentNode.appendChild(panel)
    } else {
      this.element.appendChild(panel)
    }
    
    this.correctionPanelTarget = panel
    this.loadCategories()
  }

  async loadCategories() {
    try {
      const response = await fetch("/api/v1/categories")
      const categories = await response.json()
      
      if (this.hasCategorySelectTarget) {
        const select = this.categorySelectTarget
        select.innerHTML = '<option value="">Seleccionar categoría...</option>'
        
        categories.forEach(category => {
          const option = document.createElement("option")
          option.value = category.id
          option.textContent = category.name
          option.style.color = category.color
          select.appendChild(option)
        })
      }
    } catch (error) {
      console.error("Error loading categories:", error)
    }
  }

  async applyCorrection() {
    if (!this.hasCategorySelectTarget) return
    
    const categoryId = this.categorySelectTarget.value
    if (!categoryId) {
      this.showError("Por favor selecciona una categoría")
      return
    }
    
    try {
      const response = await fetch(`/expenses/${this.expenseIdValue}/correct_category`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        },
        body: JSON.stringify({ category_id: categoryId })
      })
      
      if (response.ok) {
        // Show success feedback
        this.showSuccess("Categoría actualizada correctamente")
        
        // Trigger Turbo to refresh the expense row
        const turboFrame = document.querySelector(`#expense_${this.expenseIdValue}_category`)
        if (turboFrame) {
          turboFrame.reload()
        }
        
        this.hideCorrection()
      } else {
        this.showError("Error al actualizar la categoría")
      }
    } catch (error) {
      console.error("Error applying correction:", error)
      this.showError("Error de conexión")
    }
  }

  // Keyboard shortcuts
  setupKeyboardShortcuts() {
    this.keyboardHandler = this.handleKeyboard.bind(this)
    document.addEventListener("keydown", this.keyboardHandler)
  }

  removeKeyboardShortcuts() {
    if (this.keyboardHandler) {
      document.removeEventListener("keydown", this.keyboardHandler)
    }
  }

  handleKeyboard(event) {
    // Only handle if this element is focused or hover
    if (!this.element.matches(":hover") && !this.element.contains(document.activeElement)) {
      return
    }

    // Don't fire shortcuts when typing in form fields (except Escape)
    if (shouldSuppressShortcut(event)) return

    switch(event.key.toLowerCase()) {
      case "escape":
        if (this.hasCorrectionPanelTarget && !this.correctionPanelTarget.classList.contains("hidden")) {
          event.stopPropagation()
          this.hideCorrection()
        }
        break
      case "c":
        if (!event.metaKey && !event.ctrlKey) {
          event.preventDefault()
          event.stopPropagation()
          this.showCorrection(event)
        }
        break
      case "enter":
        if (this.hasCorrectionPanelTarget && !this.correctionPanelTarget.classList.contains("hidden")) {
          event.preventDefault()
          event.stopPropagation()
          this.applyCorrection()
        }
        break
    }
  }

  // Touch interactions for mobile
  setupTouchInteractions() {
    if (!this.isMobile()) return
    
    this.touchStartHandler = this.handleTouchStart.bind(this)
    this.touchEndHandler = this.handleTouchEnd.bind(this)
    
    this.element.addEventListener("touchstart", this.touchStartHandler)
    this.element.addEventListener("touchend", this.touchEndHandler)
  }

  removeTouchInteractions() {
    if (this.touchStartHandler) {
      this.element.removeEventListener("touchstart", this.touchStartHandler)
    }
    if (this.touchEndHandler) {
      this.element.removeEventListener("touchend", this.touchEndHandler)
    }
  }

  handleTouchStart(event) {
    this.touchStartTime = Date.now()
    this.touchStartX = event.touches[0].clientX
    this.touchStartY = event.touches[0].clientY
  }

  handleTouchEnd(event) {
    const touchDuration = Date.now() - this.touchStartTime
    const touchEndX = event.changedTouches[0].clientX
    const touchEndY = event.changedTouches[0].clientY
    const distance = Math.sqrt(
      Math.pow(touchEndX - this.touchStartX, 2) +
      Math.pow(touchEndY - this.touchStartY, 2)
    )
    
    // Long press to show correction (500ms+)
    if (touchDuration > 500 && distance < 10) {
      event.preventDefault()
      this.showCorrection(event)
    }
  }

  // Animation helpers
  animateIn(element) {
    element.style.opacity = "0"
    element.style.transform = "translateY(-10px)"
    
    requestAnimationFrame(() => {
      element.style.transition = "opacity 200ms, transform 200ms"
      element.style.opacity = "1"
      element.style.transform = "translateY(0)"
    })
  }

  animateOut(element) {
    return new Promise(resolve => {
      element.style.transition = "opacity 200ms, transform 200ms"
      element.style.opacity = "0"
      element.style.transform = "translateY(-10px)"
      
      setTimeout(resolve, 200)
    })
  }

  // Utility methods
  getCSRFToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }

  isMobile() {
    return window.innerWidth <= 768 || "ontouchstart" in window
  }

  showSuccess(message) {
    this.showNotification(message, "success")
  }

  showError(message) {
    this.showNotification(message, "error")
  }

  showNotification(message, type) {
    const notification = document.createElement("div")
    notification.classList.add(
      "fixed", "bottom-4", "right-4", "p-3", "rounded-lg",
      "shadow-lg", "z-50", "transition-all", "duration-300"
    )
    
    if (type === "success") {
      notification.classList.add("bg-emerald-50", "text-emerald-800", "border", "border-emerald-200")
      notification.innerHTML = `
        <div class="flex items-center gap-2">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
          </svg>
          <span>${message}</span>
        </div>
      `
    } else {
      notification.classList.add("bg-rose-50", "text-rose-800", "border", "border-rose-200")
      notification.innerHTML = `
        <div class="flex items-center gap-2">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
          </svg>
          <span>${message}</span>
        </div>
      `
    }
    
    document.body.appendChild(notification)
    
    // Animate in
    requestAnimationFrame(() => {
      notification.style.transform = "translateX(0)"
      notification.style.opacity = "1"
    })
    
    // Remove after 3 seconds
    setTimeout(() => {
      notification.style.transform = "translateX(100%)"
      notification.style.opacity = "0"
      setTimeout(() => notification.remove(), 300)
    }, 3000)
  }
}