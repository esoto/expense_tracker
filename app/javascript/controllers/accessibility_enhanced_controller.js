import { Controller } from "@hotwired/stimulus"

/**
 * Accessibility Enhanced Controller
 * Improves accessibility for inline actions with screen reader support,
 * keyboard navigation, ARIA live regions, and high contrast mode support
 */
export default class extends Controller {
  static targets = [
    "actionButton",
    "actionMenu",
    "liveRegion",
    "skipLink",
    "focusTrap",
    "announcement"
  ]
  
  static values = {
    highContrast: { type: Boolean, default: false },
    reducedMotion: { type: Boolean, default: false },
    screenReaderMode: { type: Boolean, default: false },
    keyboardNavEnabled: { type: Boolean, default: true }
  }
  
  connect() {
    // Detect user preferences
    this.detectUserPreferences()
    
    // Set up ARIA live regions
    this.setupLiveRegions()
    
    // Set up keyboard navigation
    this.setupKeyboardNavigation()
    
    // Set up focus management
    this.setupFocusManagement()
    
    // Set up skip links
    this.setupSkipLinks()
    
    // Apply accessibility enhancements
    this.applyAccessibilityEnhancements()
    
    // Listen for preference changes
    this.setupPreferenceListeners()
  }
  
  disconnect() {
    // Clean up listeners
    if (this.mediaQueryListeners) {
      this.mediaQueryListeners.forEach(({ query, handler }) => {
        query.removeEventListener('change', handler)
      })
    }
    
    // Clean up keyboard listeners
    if (this.keyboardHandler) {
      document.removeEventListener('keydown', this.keyboardHandler)
    }
  }
  
  /**
   * Detect user accessibility preferences
   */
  detectUserPreferences() {
    // Check for high contrast mode
    if (window.matchMedia) {
      const highContrastQuery = window.matchMedia('(prefers-contrast: high)')
      this.highContrastValue = highContrastQuery.matches
      
      // Check for reduced motion
      const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)')
      this.reducedMotionValue = reducedMotionQuery.matches
    }
    
    // Check for screen reader (basic detection)
    this.detectScreenReader()
  }
  
  /**
   * Basic screen reader detection
   */
  detectScreenReader() {
    // This is a heuristic approach - not 100% reliable
    const indicators = [
      // Check for ARIA attributes being actively used
      document.querySelector('[aria-live]'),
      // Check for focus visible
      document.activeElement !== document.body,
      // Check for specific user agent strings (limited reliability)
      /NVDA|JAWS|VoiceOver|TalkBack/.test(navigator.userAgent)
    ]
    
    this.screenReaderModeValue = indicators.some(Boolean)
  }
  
  /**
   * Set up ARIA live regions for dynamic updates
   */
  setupLiveRegions() {
    // Create main live region if it doesn't exist
    if (!this.hasLiveRegionTarget) {
      const liveRegion = document.createElement('div')
      liveRegion.setAttribute('role', 'status')
      liveRegion.setAttribute('aria-live', 'polite')
      liveRegion.setAttribute('aria-atomic', 'true')
      liveRegion.className = 'sr-only'
      liveRegion.setAttribute('data-accessibility-enhanced-target', 'liveRegion')
      document.body.appendChild(liveRegion)
      this.liveRegionTarget = liveRegion
    }
    
    // Create assertive region for urgent announcements
    const assertiveRegion = document.createElement('div')
    assertiveRegion.setAttribute('role', 'alert')
    assertiveRegion.setAttribute('aria-live', 'assertive')
    assertiveRegion.className = 'sr-only'
    document.body.appendChild(assertiveRegion)
    this.assertiveRegion = assertiveRegion
  }
  
  /**
   * Set up enhanced keyboard navigation
   */
  setupKeyboardNavigation() {
    this.keyboardHandler = (event) => {
      if (!this.keyboardNavEnabledValue) return
      
      // Handle action button keyboard shortcuts
      if (event.altKey && event.key === 'a') {
        event.preventDefault()
        this.focusFirstAction()
      }
      
      // Navigate between actions with arrow keys
      if (this.isInActionContext(event.target)) {
        switch(event.key) {
          case 'ArrowDown':
            event.preventDefault()
            this.focusNextAction(event.target)
            break
          case 'ArrowUp':
            event.preventDefault()
            this.focusPreviousAction(event.target)
            break
          case 'Home':
            event.preventDefault()
            this.focusFirstAction()
            break
          case 'End':
            event.preventDefault()
            this.focusLastAction()
            break
          case 'Escape':
            event.preventDefault()
            this.closeAllMenus()
            break
        }
      }
      
      // Quick action shortcuts
      if (event.ctrlKey || event.metaKey) {
        switch(event.key) {
          case 'e': // Edit
            event.preventDefault()
            this.triggerQuickAction('edit')
            break
          case 'd': // Delete
            if (event.shiftKey) {
              event.preventDefault()
              this.triggerQuickAction('delete')
            }
            break
          case 's': // Status
            if (event.altKey) {
              event.preventDefault()
              this.triggerQuickAction('status')
            }
            break
        }
      }
    }
    
    document.addEventListener('keydown', this.keyboardHandler)
  }
  
  /**
   * Set up focus management for better navigation
   */
  setupFocusManagement() {
    // Track focus for restoration
    this.previousFocus = null
    
    // Set up focus trap for modals/menus
    this.element.addEventListener('focusin', (event) => {
      if (this.hasFocusTrapTarget && this.focusTrapTarget.contains(event.target)) {
        this.trapFocus(this.focusTrapTarget)
      }
    })
    
    // Restore focus when closing menus
    this.element.addEventListener('menu:closed', () => {
      if (this.previousFocus) {
        this.previousFocus.focus()
        this.previousFocus = null
      }
    })
  }
  
  /**
   * Set up skip links for keyboard navigation
   */
  setupSkipLinks() {
    // Create skip to actions link
    const skipLink = document.createElement('a')
    skipLink.href = '#expense-actions'
    skipLink.className = 'sr-only focus:not-sr-only focus:absolute focus:top-4 focus:left-4 bg-teal-700 text-white px-4 py-2 rounded-lg z-50'
    skipLink.textContent = 'Saltar a acciones de gastos'
    skipLink.setAttribute('data-accessibility-enhanced-target', 'skipLink')
    
    // Insert at beginning of body
    document.body.insertBefore(skipLink, document.body.firstChild)
    
    // Handle skip link activation
    skipLink.addEventListener('click', (e) => {
      e.preventDefault()
      this.focusFirstAction()
      this.announce('Navegado a acciones de gastos')
    })
  }
  
  /**
   * Apply accessibility enhancements based on preferences
   */
  applyAccessibilityEnhancements() {
    // High contrast mode enhancements
    if (this.highContrastValue) {
      this.applyHighContrastStyles()
    }
    
    // Reduced motion enhancements
    if (this.reducedMotionValue) {
      this.applyReducedMotion()
    }
    
    // Screen reader enhancements
    if (this.screenReaderModeValue) {
      this.applyScreenReaderEnhancements()
    }
    
    // Enhance all action buttons
    this.enhanceActionButtons()
    
    // Add ARIA labels and descriptions
    this.addAriaEnhancements()
  }
  
  /**
   * Apply high contrast styles
   */
  applyHighContrastStyles() {
    // Add high contrast class to body
    document.body.classList.add('high-contrast-mode')
    
    // Enhance focus indicators
    const style = document.createElement('style')
    style.textContent = `
      .high-contrast-mode *:focus {
        outline: 3px solid currentColor !important;
        outline-offset: 2px !important;
      }
      
      .high-contrast-mode button {
        border: 2px solid currentColor !important;
      }
      
      .high-contrast-mode .text-slate-600 {
        color: #1e293b !important;
      }
      
      .high-contrast-mode .bg-teal-50 {
        background-color: #0f766e !important;
        color: white !important;
      }
      
      .high-contrast-mode .border-slate-200 {
        border-color: #1e293b !important;
      }
    `
    document.head.appendChild(style)
    this.highContrastStyle = style
  }
  
  /**
   * Apply reduced motion preferences
   */
  applyReducedMotion() {
    // Add reduced motion class
    document.body.classList.add('reduce-motion')
    
    // Override animations
    const style = document.createElement('style')
    style.textContent = `
      .reduce-motion * {
        animation-duration: 0.01ms !important;
        animation-iteration-count: 1 !important;
        transition-duration: 0.01ms !important;
      }
    `
    document.head.appendChild(style)
    this.reducedMotionStyle = style
  }
  
  /**
   * Apply screen reader specific enhancements
   */
  applyScreenReaderEnhancements() {
    // Add screen reader class for specific adjustments
    document.body.classList.add('screen-reader-active')
    
    // Ensure all interactive elements have labels
    this.element.querySelectorAll('button:not([aria-label])').forEach(button => {
      const text = button.textContent.trim()
      if (!text) {
        button.setAttribute('aria-label', 'Acción sin etiqueta')
      }
    })
    
    // Add descriptions to complex elements
    this.element.querySelectorAll('[data-expense-id]').forEach(row => {
      const expenseId = row.dataset.expenseId
      row.setAttribute('aria-label', `Gasto ${expenseId}`)
    })
  }
  
  /**
   * Enhance action buttons with ARIA attributes
   */
  enhanceActionButtons() {
    if (!this.hasActionButtonTarget) return
    
    this.actionButtonTargets.forEach((button, index) => {
      // Add ARIA attributes
      button.setAttribute('aria-label', this.getActionLabel(button))
      button.setAttribute('aria-describedby', `action-desc-${index}`)
      button.setAttribute('role', 'button')
      
      // Add keyboard hints
      const hint = document.createElement('span')
      hint.id = `action-desc-${index}`
      hint.className = 'sr-only'
      hint.textContent = this.getActionDescription(button)
      button.appendChild(hint)
      
      // Enhance focus behavior
      button.addEventListener('focus', () => {
        this.announce(`${this.getActionLabel(button)} enfocado`)
      })
    })
  }
  
  /**
   * Add ARIA enhancements to the entire component
   */
  addAriaEnhancements() {
    // Mark main expense list as a feed for screen readers
    const expenseList = this.element.querySelector('[data-controller*="batch-selection"]')
    if (expenseList) {
      expenseList.setAttribute('role', 'feed')
      expenseList.setAttribute('aria-label', 'Lista de gastos')
      expenseList.setAttribute('aria-busy', 'false')
    }
    
    // Mark each expense row as an article
    this.element.querySelectorAll('tbody tr').forEach((row, index) => {
      row.setAttribute('role', 'article')
      row.setAttribute('aria-posinset', index + 1)
      row.setAttribute('tabindex', '0')
      
      // Add descriptive label
      const date = row.querySelector('td:first-child')?.textContent.trim()
      const merchant = row.querySelector('td:nth-child(2)')?.textContent.trim()
      const amount = row.querySelector('td:nth-child(4)')?.textContent.trim()
      
      if (date && merchant && amount) {
        row.setAttribute('aria-label', `Gasto: ${merchant} el ${date} por ${amount}`)
      }
    })
  }
  
  /**
   * Focus management utilities
   */
  focusFirstAction() {
    const firstAction = this.element.querySelector('button[data-accessibility-enhanced-target="actionButton"]:first-of-type')
    if (firstAction) {
      firstAction.focus()
      this.announce('Primera acción enfocada')
    }
  }
  
  focusLastAction() {
    const actions = this.element.querySelectorAll('button[data-accessibility-enhanced-target="actionButton"]')
    const lastAction = actions[actions.length - 1]
    if (lastAction) {
      lastAction.focus()
      this.announce('Última acción enfocada')
    }
  }
  
  focusNextAction(current) {
    const actions = Array.from(this.element.querySelectorAll('button[data-accessibility-enhanced-target="actionButton"]'))
    const currentIndex = actions.indexOf(current)
    const nextAction = actions[currentIndex + 1] || actions[0]
    if (nextAction) {
      nextAction.focus()
    }
  }
  
  focusPreviousAction(current) {
    const actions = Array.from(this.element.querySelectorAll('button[data-accessibility-enhanced-target="actionButton"]'))
    const currentIndex = actions.indexOf(current)
    const prevAction = actions[currentIndex - 1] || actions[actions.length - 1]
    if (prevAction) {
      prevAction.focus()
    }
  }
  
  /**
   * Trap focus within an element
   */
  trapFocus(element) {
    const focusableElements = element.querySelectorAll(
      'a[href], button, textarea, input[type="text"], input[type="radio"], input[type="checkbox"], select'
    )
    const firstFocusable = focusableElements[0]
    const lastFocusable = focusableElements[focusableElements.length - 1]
    
    element.addEventListener('keydown', (e) => {
      if (e.key === 'Tab') {
        if (e.shiftKey) {
          if (document.activeElement === firstFocusable) {
            lastFocusable.focus()
            e.preventDefault()
          }
        } else {
          if (document.activeElement === lastFocusable) {
            firstFocusable.focus()
            e.preventDefault()
          }
        }
      }
    })
  }
  
  /**
   * Announce message to screen readers
   */
  announce(message, priority = 'polite') {
    const region = priority === 'assertive' ? this.assertiveRegion : this.liveRegionTarget
    
    if (region) {
      region.textContent = message
      
      // Clear after announcement
      setTimeout(() => {
        region.textContent = ''
      }, 1000)
    }
  }
  
  /**
   * Helper methods
   */
  isInActionContext(element) {
    return element.closest('[data-accessibility-enhanced-target="actionButton"]') !== null
  }
  
  getActionLabel(button) {
    const text = button.textContent.trim()
    const action = button.dataset.action || ''
    
    if (action.includes('edit')) return 'Editar gasto'
    if (action.includes('delete')) return 'Eliminar gasto'
    if (action.includes('duplicate')) return 'Duplicar gasto'
    if (action.includes('status')) return 'Cambiar estado'
    if (action.includes('category')) return 'Cambiar categoría'
    
    return text || 'Acción'
  }
  
  getActionDescription(button) {
    const action = button.dataset.action || ''
    
    if (action.includes('edit')) return 'Presiona Enter para editar este gasto'
    if (action.includes('delete')) return 'Presiona Enter para eliminar este gasto de forma permanente. Esta acción no se puede deshacer.'
    if (action.includes('duplicate')) return 'Presiona Enter para crear una copia de este gasto'
    if (action.includes('status')) return 'Presiona Enter para cambiar el estado del gasto'
    if (action.includes('category')) return 'Presiona Enter para cambiar la categoría del gasto'
    
    return 'Presiona Enter para ejecutar esta acción'
  }
  
  triggerQuickAction(type) {
    const focusedRow = document.activeElement.closest('tr')
    if (!focusedRow) return
    
    const actionButton = focusedRow.querySelector(`button[data-action*="${type}"]`)
    if (actionButton) {
      actionButton.click()
      this.announce(`Acción ${type} ejecutada`)
    }
  }
  
  closeAllMenus() {
    this.element.querySelectorAll('[data-action-menu]').forEach(menu => {
      menu.style.display = 'none'
    })
    this.announce('Menús cerrados')
  }
  
  /**
   * Set up preference change listeners
   */
  setupPreferenceListeners() {
    this.mediaQueryListeners = []
    
    if (window.matchMedia) {
      // High contrast listener
      const highContrastQuery = window.matchMedia('(prefers-contrast: high)')
      const highContrastHandler = (e) => {
        this.highContrastValue = e.matches
        if (e.matches) {
          this.applyHighContrastStyles()
        } else {
          this.removeHighContrastStyles()
        }
      }
      highContrastQuery.addEventListener('change', highContrastHandler)
      this.mediaQueryListeners.push({ query: highContrastQuery, handler: highContrastHandler })
      
      // Reduced motion listener
      const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)')
      const reducedMotionHandler = (e) => {
        this.reducedMotionValue = e.matches
        if (e.matches) {
          this.applyReducedMotion()
        } else {
          this.removeReducedMotion()
        }
      }
      reducedMotionQuery.addEventListener('change', reducedMotionHandler)
      this.mediaQueryListeners.push({ query: reducedMotionQuery, handler: reducedMotionHandler })
    }
  }
  
  removeHighContrastStyles() {
    document.body.classList.remove('high-contrast-mode')
    if (this.highContrastStyle) {
      this.highContrastStyle.remove()
    }
  }
  
  removeReducedMotion() {
    document.body.classList.remove('reduce-motion')
    if (this.reducedMotionStyle) {
      this.reducedMotionStyle.remove()
    }
  }
}