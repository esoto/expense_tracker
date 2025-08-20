// Accessibility Manager for Dashboard Features
// Task 3.9: Dashboard Accessibility
// Provides utilities for WCAG 2.1 AA compliance

export default class AccessibilityManager {
  constructor() {
    this.statusRegion = document.getElementById('accessibility-status')
    this.alertRegion = document.getElementById('accessibility-alerts')
    this.activeModal = null
    this.lastFocusedElement = null
    this.keyboardNavigation = true
    this.reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    
    this.initializeA11y()
  }
  
  // Initialize accessibility features
  initializeA11y() {
    this.setupKeyboardDetection()
    this.setupFocusManagement()
    this.setupReducedMotionDetection()
    this.setupScreenReaderDetection()
    this.addGlobalKeyboardShortcuts()
    
    // Announce page load completion
    setTimeout(() => {
      this.announce('Página cargada. Use Tab para navegar o presione Alt+H para ayuda con atajos de teclado.')
    }, 1000)
  }
  
  // Keyboard vs mouse detection
  setupKeyboardDetection() {
    let isUsingKeyboard = false
    
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Tab') {
        isUsingKeyboard = true
        document.body.setAttribute('data-keyboard-navigation', 'true')
      }
    })
    
    document.addEventListener('mousedown', () => {
      isUsingKeyboard = false
      document.body.setAttribute('data-keyboard-navigation', 'false')
    })
    
    // Focus-visible polyfill behavior
    document.addEventListener('focusin', (e) => {
      if (isUsingKeyboard || e.target.matches('input, textarea, select')) {
        e.target.setAttribute('data-focus-visible', 'true')
      }
    })
    
    document.addEventListener('focusout', (e) => {
      e.target.removeAttribute('data-focus-visible')
    })
  }
  
  // Focus management for modals and dropdowns
  setupFocusManagement() {
    // Store last focused element when modal opens
    document.addEventListener('modal:opened', (e) => {
      this.lastFocusedElement = document.activeElement
      this.activeModal = e.detail.modal
      this.trapFocus(this.activeModal)
      this.announce('Modal abierto', 'assertive')
    })
    
    // Restore focus when modal closes
    document.addEventListener('modal:closed', (e) => {
      if (this.lastFocusedElement) {
        this.lastFocusedElement.focus()
        this.lastFocusedElement = null
      }
      this.activeModal = null
      this.announce('Modal cerrado', 'assertive')
    })
  }
  
  // Reduced motion detection
  setupReducedMotionDetection() {
    const mediaQuery = window.matchMedia('(prefers-reduced-motion: reduce)')
    
    const updateMotionPreference = () => {
      this.reducedMotion = mediaQuery.matches
      document.body.setAttribute('data-reduced-motion', this.reducedMotion)
    }
    
    updateMotionPreference()
    mediaQuery.addEventListener('change', updateMotionPreference)
  }
  
  // Screen reader detection (basic heuristic)
  setupScreenReaderDetection() {
    // Basic screen reader detection
    const isScreenReader = window.navigator.userAgent.includes('NVDA') ||
                          window.navigator.userAgent.includes('JAWS') ||
                          window.speechSynthesis ||
                          window.navigator.maxTouchPoints === 0
    
    if (isScreenReader) {
      document.body.setAttribute('data-screen-reader', 'true')
    }
  }
  
  // Global keyboard shortcuts
  addGlobalKeyboardShortcuts() {
    document.addEventListener('keydown', (e) => {
      // Skip if in input fields
      if (e.target.matches('input, textarea, select, [contenteditable]')) {
        return
      }
      
      // Alt+H: Show keyboard shortcuts help
      if (e.altKey && e.key === 'h') {
        e.preventDefault()
        this.showKeyboardShortcuts()
      }
      
      // Alt+1: Focus on filters
      if (e.altKey && e.key === '1') {
        e.preventDefault()
        this.focusFilters()
      }
      
      // Alt+2: Focus on expense list
      if (e.altKey && e.key === '2') {
        e.preventDefault()
        this.focusExpenseList()
      }
      
      // Alt+3: Focus on selection toolbar
      if (e.altKey && e.key === '3') {
        e.preventDefault()
        this.focusSelectionToolbar()
      }
      
      // Escape: Global escape handler
      if (e.key === 'Escape') {
        this.handleGlobalEscape()
      }
    })
  }
  
  // Announce messages to screen readers
  announce(message, priority = 'polite') {
    const region = priority === 'assertive' ? this.alertRegion : this.statusRegion
    
    if (region) {
      // Clear any existing message
      region.textContent = ''
      
      // Add new message with slight delay to ensure it's announced
      setTimeout(() => {
        region.textContent = message
      }, 100)
      
      // Clear message after 5 seconds to avoid confusion
      setTimeout(() => {
        if (region.textContent === message) {
          region.textContent = ''
        }
      }, 5000)
    }
  }
  
  // Trap focus within an element
  trapFocus(element) {
    if (!element) return
    
    const focusableElements = element.querySelectorAll(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    )
    
    if (focusableElements.length === 0) return
    
    const firstElement = focusableElements[0]
    const lastElement = focusableElements[focusableElements.length - 1]
    
    const trapHandler = (e) => {
      if (e.key === 'Tab') {
        if (e.shiftKey) {
          if (document.activeElement === firstElement) {
            e.preventDefault()
            lastElement.focus()
          }
        } else {
          if (document.activeElement === lastElement) {
            e.preventDefault()
            firstElement.focus()
          }
        }
      }
    }
    
    element.addEventListener('keydown', trapHandler)
    
    // Store handler for cleanup
    element._focusTrapHandler = trapHandler
    
    // Focus first element
    setTimeout(() => firstElement.focus(), 100)
  }
  
  // Remove focus trap
  removeFocusTrap(element) {
    if (element && element._focusTrapHandler) {
      element.removeEventListener('keydown', element._focusTrapHandler)
      delete element._focusTrapHandler
    }
  }
  
  // Show keyboard shortcuts help
  showKeyboardShortcuts() {
    const shortcuts = [
      'Tab/Shift+Tab: Navegar entre elementos',
      'Enter/Espacio: Activar botón o enlace',
      'Escape: Cerrar modales o limpiar filtros',
      'Flechas: Navegar en listas y filtros',
      'Alt+1: Ir a filtros rápidos',
      'Alt+2: Ir a lista de gastos',
      'Alt+3: Ir a acciones de selección',
      'Ctrl+Shift+S: Activar selección múltiple',
      'Ctrl+Shift+V: Cambiar vista',
      'C: Categorizar (en lista de gastos)',
      'S: Cambiar estado (en lista de gastos)',
      'D: Duplicar (en lista de gastos)',
      'Del: Eliminar (en lista de gastos)'
    ]
    
    const helpText = shortcuts.join('\n')
    
    // Create modal with keyboard shortcuts
    const modal = document.createElement('div')
    modal.className = 'fixed inset-0 bg-slate-900/50 backdrop-blur-sm z-[9999] flex items-center justify-center p-4'
    modal.setAttribute('role', 'dialog')
    modal.setAttribute('aria-modal', 'true')
    modal.setAttribute('aria-labelledby', 'shortcuts-title')
    
    modal.innerHTML = `
      <div class="bg-white rounded-xl shadow-2xl max-w-md w-full p-6">
        <div class="flex items-center justify-between mb-4">
          <h2 id="shortcuts-title" class="text-lg font-semibold text-slate-900">
            Atajos de Teclado
          </h2>
          <button type="button" 
                  class="p-1 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-100"
                  aria-label="Cerrar ayuda">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
            </svg>
          </button>
        </div>
        <div class="space-y-2 max-h-64 overflow-y-auto">
          ${shortcuts.map(shortcut => `
            <div class="text-sm">
              <code class="bg-slate-100 px-2 py-1 rounded text-xs font-mono">${shortcut.split(':')[0]}</code>
              <span class="ml-2 text-slate-700">${shortcut.split(':')[1]}</span>
            </div>
          `).join('')}
        </div>
        <div class="mt-4 pt-4 border-t border-slate-200">
          <button type="button" 
                  class="w-full px-4 py-2 bg-teal-700 text-white rounded-lg hover:bg-teal-800 transition-colors"
                  aria-label="Cerrar ayuda de atajos">
            Cerrar
          </button>
        </div>
      </div>
    `
    
    // Close handlers
    const closeModal = () => {
      document.body.removeChild(modal)
      this.announce('Ayuda de atajos cerrada')
    }
    
    modal.querySelector('button[aria-label="Cerrar ayuda"]').addEventListener('click', closeModal)
    modal.querySelector('button[aria-label="Cerrar ayuda de atajos"]').addEventListener('click', closeModal)
    
    modal.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        closeModal()
      }
    })
    
    modal.addEventListener('click', (e) => {
      if (e.target === modal) {
        closeModal()
      }
    })
    
    document.body.appendChild(modal)
    this.trapFocus(modal)
    this.announce('Ayuda de atajos de teclado abierta', 'assertive')
  }
  
  // Focus on filters section
  focusFilters() {
    const filtersSection = document.getElementById('filter-chips-title') || 
                          document.querySelector('[data-controller="dashboard-filter-chips"]')
    
    if (filtersSection) {
      filtersSection.focus()
      this.announce('Enfocado en filtros rápidos')
    }
  }
  
  // Focus on expense list
  focusExpenseList() {
    const expenseList = document.getElementById('recent-expenses-title') ||
                       document.querySelector('[data-dashboard-expenses-target="list"]')
    
    if (expenseList) {
      expenseList.focus()
      this.announce('Enfocado en lista de gastos')
    }
  }
  
  // Focus on selection toolbar
  focusSelectionToolbar() {
    const toolbar = document.querySelector('[data-dashboard-expenses-target="selectionToolbar"]')
    
    if (toolbar && !toolbar.classList.contains('hidden')) {
      const firstButton = toolbar.querySelector('button')
      if (firstButton) {
        firstButton.focus()
        this.announce('Enfocado en acciones de selección')
      }
    } else {
      this.announce('Modo de selección no activo')
    }
  }
  
  // Global escape handler
  handleGlobalEscape() {
    // Close any open modals
    if (this.activeModal) {
      const closeButton = this.activeModal.querySelector('[data-dismiss], [aria-label*="cerrar" i]')
      if (closeButton) {
        closeButton.click()
        return
      }
    }
    
    // Clear filters if any are active
    const clearFiltersButton = document.querySelector('[data-dashboard-filter-chips-target="clearButton"]')
    if (clearFiltersButton && !clearFiltersButton.classList.contains('hidden')) {
      clearFiltersButton.click()
      return
    }
    
    // Exit selection mode
    const selectionModeButton = document.querySelector('[data-action*="disableSelectionMode"]')
    if (selectionModeButton) {
      selectionModeButton.click()
      return
    }
  }
  
  // Update loading states with proper announcements
  updateLoadingState(element, isLoading, message = null) {
    if (isLoading) {
      element.setAttribute('aria-busy', 'true')
      if (message) {
        this.announce(message)
      }
    } else {
      element.removeAttribute('aria-busy')
      if (message) {
        this.announce(message)
      }
    }
  }
  
  // Update selection count announcements
  announceSelectionChange(count, total) {
    if (count === 0) {
      this.announce('Selección limpiada')
    } else if (count === total) {
      this.announce(`Todos los ${total} gastos seleccionados`)
    } else {
      this.announce(`${count} de ${total} gastos seleccionados`)
    }
  }
  
  // Announce filter changes
  announceFilterChange(filterType, value, isActive) {
    const action = isActive ? 'aplicado' : 'removido'
    const message = `Filtro ${action}: ${filterType} ${value}`
    this.announce(message)
  }
  
  // Announce bulk operation results
  announceBulkOperation(operation, count, success = true) {
    const operations = {
      categorize: 'categorizados',
      status: 'actualizados',
      delete: 'eliminados'
    }
    
    const operationText = operations[operation] || operation
    const status = success ? 'exitosamente' : 'con errores'
    
    this.announce(`${count} gastos ${operationText} ${status}`, 'assertive')
  }
  
  // Announce navigation changes
  announceNavigation(fromPage, toPage) {
    this.announce(`Navegado de ${fromPage} a ${toPage}`)
  }
  
  // Color contrast validation
  validateColorContrast(foreground, background) {
    // Simple contrast ratio calculation
    const getLuminance = (color) => {
      const rgb = color.match(/\d+/g)
      if (!rgb || rgb.length < 3) return 0
      
      const [r, g, b] = rgb.map(c => {
        c = parseInt(c) / 255
        return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
      })
      
      return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    
    const fgLuminance = getLuminance(foreground)
    const bgLuminance = getLuminance(background)
    
    const light = Math.max(fgLuminance, bgLuminance)
    const dark = Math.min(fgLuminance, bgLuminance)
    
    const ratio = (light + 0.05) / (dark + 0.05)
    
    return {
      ratio: ratio,
      passesAA: ratio >= 4.5,
      passesAALarge: ratio >= 3.0
    }
  }
  
  // Add high contrast mode support
  enableHighContrastMode() {
    document.body.classList.add('high-contrast-mode')
    this.announce('Modo de alto contraste activado')
  }
  
  disableHighContrastMode() {
    document.body.classList.remove('high-contrast-mode')
    this.announce('Modo de alto contraste desactivado')
  }
}

// Initialize accessibility manager when DOM is ready
let accessibilityManager = null

document.addEventListener('DOMContentLoaded', () => {
  accessibilityManager = new AccessibilityManager()
  
  // Make it globally available
  window.accessibilityManager = accessibilityManager
})

export { accessibilityManager }