import { Controller } from "@hotwired/stimulus"

// Tooltip Controller for Task 2.3.3
// Handles interactive tooltips with proper positioning, delays, and mobile support
// Integrates with sparkline controller for chart rendering
export default class extends Controller {
  static targets = ["trigger", "content", "sparkline"]
  static values = {
    delay: { type: Number, default: 200 }, // Hover delay in ms
    position: { type: String, default: "top" }, // top, bottom, left, right
    showOnMobile: { type: Boolean, default: true },
    trendData: Object,
    metricType: String,
    metricLabel: String
  }
  
  connect() {
    this.isVisible = false
    this.hoverTimer = null
    this.touchTimer = null
    
    // Bind event listeners
    this.bindEvents()
    
    // Create tooltip element if it doesn't exist
    this.createTooltipElement()
    
    // Check if we're on mobile
    this.isMobile = this.checkMobile()
  }
  
  disconnect() {
    // Clean up timers
    this.clearTimers()
    
    // Remove tooltip element
    if (this.tooltipElement) {
      this.tooltipElement.remove()
      this.tooltipElement = null
    }
    
    // Remove global click listener
    if (this.documentClickHandler) {
      document.removeEventListener('click', this.documentClickHandler)
      this.documentClickHandler = null
    }
    
    // Clear any references to prevent memory leaks
    this.isVisible = false
  }
  
  bindEvents() {
    // Desktop hover events
    this.element.addEventListener('mouseenter', this.handleMouseEnter.bind(this))
    this.element.addEventListener('mouseleave', this.handleMouseLeave.bind(this))
    
    // Mobile touch events
    if (this.showOnMobileValue) {
      this.element.addEventListener('touchstart', this.handleTouchStart.bind(this), { passive: true })
    }
    
    // Keyboard accessibility
    this.element.addEventListener('focus', this.handleFocus.bind(this))
    this.element.addEventListener('blur', this.handleBlur.bind(this))
    
    // Make element keyboard accessible if not already
    if (!this.element.hasAttribute('tabindex')) {
      this.element.setAttribute('tabindex', '0')
    }
    
    // Add ARIA attributes for accessibility
    this.element.setAttribute('aria-describedby', this.tooltipId)
    this.element.setAttribute('role', 'button')
  }
  
  createTooltipElement() {
    // Generate unique ID for tooltip
    this.tooltipId = `tooltip-${Math.random().toString(36).substr(2, 9)}`
    
    // Create tooltip container
    this.tooltipElement = document.createElement('div')
    this.tooltipElement.id = this.tooltipId
    this.tooltipElement.className = 'tooltip-container absolute z-50 pointer-events-none opacity-0 transition-opacity duration-200'
    this.tooltipElement.setAttribute('role', 'tooltip')
    
    // Create tooltip content wrapper
    const wrapper = document.createElement('div')
    wrapper.className = 'bg-white rounded-lg shadow-xl border border-slate-200 p-4 max-w-sm'
    
    // Build tooltip content
    wrapper.innerHTML = this.buildTooltipContent()
    
    this.tooltipElement.appendChild(wrapper)
    document.body.appendChild(this.tooltipElement)
  }
  
  buildTooltipContent() {
    const trendData = this.hasTrendDataValue ? this.trendDataValue : null
    const metricLabel = this.hasMetricLabelValue ? this.metricLabelValue : 'Tendencia'
    
    let content = `
      <div class="tooltip-content">
        <div class="mb-3">
          <h4 class="text-sm font-semibold text-slate-900">${metricLabel}</h4>
          <p class="text-xs text-slate-600">Tendencia últimos 7 días</p>
        </div>
    `
    
    // Add sparkline container
    if (trendData) {
      content += `
        <div class="sparkline-container mb-3" 
             data-controller="sparkline"
             data-sparkline-data-value='${JSON.stringify(trendData.daily_amounts || [])}'
             data-sparkline-min-value="${trendData.min || 0}"
             data-sparkline-max-value="${trendData.max || 0}"
             data-sparkline-average-value="${trendData.average || 0}"
             data-sparkline-width-value="240"
             data-sparkline-height-value="80"
             data-sparkline-show-labels-value="true">
          <canvas data-sparkline-target="canvas"></canvas>
        </div>
      `
      
      // Add statistics
      content += `
        <div class="grid grid-cols-3 gap-2 text-xs">
          <div class="text-center">
            <div class="text-slate-600">Mínimo</div>
            <div class="font-semibold text-emerald-600">₡${this.formatNumber(trendData.min || 0)}</div>
          </div>
          <div class="text-center">
            <div class="text-slate-600">Promedio</div>
            <div class="font-semibold text-amber-600">₡${this.formatNumber(trendData.average || 0)}</div>
          </div>
          <div class="text-center">
            <div class="text-slate-600">Máximo</div>
            <div class="font-semibold text-rose-600">₡${this.formatNumber(trendData.max || 0)}</div>
          </div>
        </div>
      `
    } else {
      // No data available message
      content += `
        <div class="text-center py-4">
          <svg class="w-8 h-8 text-slate-400 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"></path>
          </svg>
          <p class="text-sm text-slate-600">No hay datos de tendencia disponibles</p>
        </div>
      `
    }
    
    content += '</div>'
    return content
  }
  
  handleMouseEnter(event) {
    if (this.isMobile) return
    
    // Clear any existing timer
    this.clearTimers()
    
    // Start hover timer
    this.hoverTimer = setTimeout(() => {
      this.showTooltip()
    }, this.delayValue)
  }
  
  handleMouseLeave(event) {
    if (this.isMobile) return
    
    // Clear timer and hide tooltip
    this.clearTimers()
    this.hideTooltip()
  }
  
  handleTouchStart(event) {
    if (!this.showOnMobileValue) return
    
    // Toggle tooltip on tap
    if (this.isVisible) {
      this.hideTooltip()
    } else {
      this.showTooltip()
      
      // Set up document click handler to close tooltip
      this.setupDocumentClickHandler()
    }
  }
  
  handleFocus(event) {
    // Show tooltip on keyboard focus
    this.showTooltip()
  }
  
  handleBlur(event) {
    // Hide tooltip on blur
    this.hideTooltip()
  }
  
  showTooltip() {
    if (this.isVisible) return
    
    // Update content if trend data has changed
    if (this.hasTrendDataValue) {
      const wrapper = this.tooltipElement.querySelector('.bg-white')
      if (wrapper) {
        wrapper.innerHTML = this.buildTooltipContent()
      }
    }
    
    // Position tooltip
    this.positionTooltip()
    
    // Show with animation
    this.tooltipElement.style.pointerEvents = 'auto'
    requestAnimationFrame(() => {
      this.tooltipElement.classList.remove('opacity-0')
      this.tooltipElement.classList.add('opacity-100')
    })
    
    this.isVisible = true
    
    // Dispatch custom event
    this.dispatch('shown')
  }
  
  hideTooltip() {
    if (!this.isVisible) return
    
    // Hide with animation
    this.tooltipElement.classList.remove('opacity-100')
    this.tooltipElement.classList.add('opacity-0')
    this.tooltipElement.style.pointerEvents = 'none'
    
    this.isVisible = false
    
    // Remove document click and touch handlers
    if (this.documentClickHandler) {
      document.removeEventListener('click', this.documentClickHandler)
      document.removeEventListener('touchstart', this.documentClickHandler)
      this.documentClickHandler = null
    }
    
    // Dispatch custom event
    this.dispatch('hidden')
  }
  
  positionTooltip() {
    const triggerRect = this.element.getBoundingClientRect()
    const tooltipRect = this.tooltipElement.getBoundingClientRect()
    const viewportWidth = window.innerWidth
    const viewportHeight = window.innerHeight
    const offset = 12 // Distance from trigger element
    
    let top, left
    let position = this.positionValue
    
    // Auto-adjust position if it would go off-screen
    if (position === 'top' && triggerRect.top - tooltipRect.height - offset < 0) {
      position = 'bottom'
    } else if (position === 'bottom' && triggerRect.bottom + tooltipRect.height + offset > viewportHeight) {
      position = 'top'
    } else if (position === 'left' && triggerRect.left - tooltipRect.width - offset < 0) {
      position = 'right'
    } else if (position === 'right' && triggerRect.right + tooltipRect.width + offset > viewportWidth) {
      position = 'left'
    }
    
    // Calculate position based on final position
    switch (position) {
      case 'top':
        top = triggerRect.top - tooltipRect.height - offset
        left = triggerRect.left + (triggerRect.width - tooltipRect.width) / 2
        break
      case 'bottom':
        top = triggerRect.bottom + offset
        left = triggerRect.left + (triggerRect.width - tooltipRect.width) / 2
        break
      case 'left':
        top = triggerRect.top + (triggerRect.height - tooltipRect.height) / 2
        left = triggerRect.left - tooltipRect.width - offset
        break
      case 'right':
        top = triggerRect.top + (triggerRect.height - tooltipRect.height) / 2
        left = triggerRect.right + offset
        break
    }
    
    // Ensure tooltip stays within viewport horizontally
    if (left < offset) {
      left = offset
    } else if (left + tooltipRect.width > viewportWidth - offset) {
      left = viewportWidth - tooltipRect.width - offset
    }
    
    // Ensure tooltip stays within viewport vertically
    if (top < offset) {
      top = offset
    } else if (top + tooltipRect.height > viewportHeight - offset) {
      top = viewportHeight - tooltipRect.height - offset
    }
    
    // Apply position
    this.tooltipElement.style.top = `${top}px`
    this.tooltipElement.style.left = `${left}px`
  }
  
  setupDocumentClickHandler() {
    // Create handler that closes tooltip when clicking outside
    this.documentClickHandler = (event) => {
      // Don't close if clicking on the element or tooltip itself
      if (!this.element.contains(event.target) && !this.tooltipElement.contains(event.target)) {
        this.hideTooltip()
      }
    }
    
    // Add listener with slight delay to avoid immediate triggering
    setTimeout(() => {
      document.addEventListener('click', this.documentClickHandler)
      // Also listen for touch events on mobile
      document.addEventListener('touchstart', this.documentClickHandler, { passive: true })
    }, 100)
  }
  
  clearTimers() {
    if (this.hoverTimer) {
      clearTimeout(this.hoverTimer)
      this.hoverTimer = null
    }
    if (this.touchTimer) {
      clearTimeout(this.touchTimer)
      this.touchTimer = null
    }
  }
  
  checkMobile() {
    return 'ontouchstart' in window || navigator.maxTouchPoints > 0
  }
  
  formatNumber(value) {
    return new Intl.NumberFormat('es-CR').format(Math.round(value))
  }
  
  // Public method to update trend data
  updateTrendData(newData) {
    this.trendDataValue = newData
    if (this.isVisible) {
      // Update content while visible
      const wrapper = this.tooltipElement.querySelector('.bg-white')
      if (wrapper) {
        wrapper.innerHTML = this.buildTooltipContent()
      }
    }
  }
}