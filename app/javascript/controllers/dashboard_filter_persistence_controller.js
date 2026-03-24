import { Controller } from "@hotwired/stimulus"
import FilterStateManager from "utilities/filter_state_manager"

// Dashboard Filter Persistence Controller for Task 3.8
// Manages persistent filter state across browser sessions and page navigation
// Integrates with filter chips (Task 3.6) and virtual scrolling (Task 3.7)
export default class extends Controller {
  static targets = [
    "persistenceIndicator",
    "restoreNotification",
    "shareButton",
    "resetButton"
  ]
  
  static values = {
    autoRestore: { type: Boolean, default: true },
    showNotifications: { type: Boolean, default: true },
    syncAcrossTabs: { type: Boolean, default: true }
  }
  
  connect() {
    // Initialize state manager
    this.stateManager = new FilterStateManager()
    
    // Load persisted state
    this.restoreState()
    
    // Set up event listeners
    this.setupEventListeners()
    
    // Set up cross-tab synchronization
    if (this.syncAcrossTabsValue) {
      this.setupCrossTabSync()
    }
    
    // Monitor for filter changes
    this.monitorFilterChanges()
    
    // Set up periodic state validation
    this.setupStateValidation()
    
    // Log initialization in development
    if (this.element.dataset.environment === "development") {
      console.log("Filter Persistence initialized:", {
        state: this.stateManager.state,
        hasFilters: this.stateManager.hasActiveFilters(),
        filterCount: this.stateManager.getFilterCount()
      })
    }
  }
  
  disconnect() {
    // Clean up event listeners
    if (this.storageListener) {
      window.removeEventListener('storage', this.storageListener)
    }
    
    if (this.popstateListener) {
      window.removeEventListener('popstate', this.popstateListener)
    }
    
    if (this.beforeUnloadListener) {
      window.removeEventListener('beforeunload', this.beforeUnloadListener)
    }
    
    if (this.validationInterval) {
      clearInterval(this.validationInterval)
    }
    
    // Save final state
    this.saveCurrentState()
  }
  
  // Restore persisted filter state
  restoreState() {
    if (!this.autoRestoreValue) return
    
    // Load state from all sources
    const restoredState = this.stateManager.loadState()
    
    // Check if we have any persisted filters
    if (!this.stateManager.hasActiveFilters() && !restoredState.view_mode) {
      // No filters to restore, check for smart defaults
      const smartDefaults = this.stateManager.getSmartDefaults()
      if (smartDefaults.suggestedCategories || smartDefaults.suggestedPeriod) {
        this.showSmartSuggestions(smartDefaults)
      }
      return
    }
    
    // Apply restored state to UI
    this.applyRestoredState(restoredState)
    
    // Show restoration notification
    if (this.showNotificationsValue && this.stateManager.hasActiveFilters()) {
      this.showRestoreNotification(restoredState)
    }
    
    // Update persistence indicator
    this.updatePersistenceIndicator()
  }
  
  // Apply restored state to UI components
  applyRestoredState(state) {
    // Find and update filter chips controller
    const filterChipsController = this.findController('dashboard-filter-chips')
    if (filterChipsController) {
      // Update filter chips state
      filterChipsController.activeFiltersValue = {
        categories: state.categories || [],
        statuses: state.statuses || [],
        period: state.period || null
      }
      
      // Update UI without triggering new fetch
      filterChipsController.updateChipStates()
      filterChipsController.updateClearButtonVisibility()
      filterChipsController.updateFilterCount()
    }
    
    // Find and update virtual scroll controller
    const virtualScrollController = this.findController('dashboard-virtual-scroll')
    if (virtualScrollController && state.scroll_position) {
      // Restore scroll position after data loads
      setTimeout(() => {
        if (virtualScrollController.hasViewportTarget) {
          virtualScrollController.viewportTarget.scrollTop = state.scroll_position
        }
      }, 100)
      
      // Update virtual scrolling preference
      if (state.virtual_enabled !== undefined) {
        virtualScrollController.enabled = state.virtual_enabled
      }
    }
    
    // Find and update dashboard expenses controller
    const dashboardController = this.findController('dashboard-expenses')
    if (dashboardController && state.view_mode) {
      // Restore view mode
      dashboardController.viewModeValue = state.view_mode
      dashboardController.applyViewMode()
    }
    
    // Dispatch restoration event
    this.dispatch('restored', {
      detail: {
        state: state,
        filterCount: this.stateManager.getFilterCount(),
        source: this.getRestorationSource(state)
      }
    })
  }
  
  // Determine where the state was restored from
  getRestorationSource(state) {
    const urlParams = new URLSearchParams(window.location.search)
    
    if (urlParams.has('filter_state') || urlParams.has('category_ids[]')) {
      return 'url'
    } else if (state.last_updated && Date.now() - state.last_updated < 60000) {
      return 'session'
    } else {
      return 'local'
    }
  }
  
  // Show notification about restored filters
  showRestoreNotification(state) {
    if (!this.hasRestoreNotificationTarget) {
      this.createRestoreNotification()
    }
    
    const filterSummary = this.stateManager.getFilterSummary()
    const filterCount = this.stateManager.getFilterCount()
    
    const message = filterCount === 1 
      ? `1 filtro restaurado: ${filterSummary}`
      : `${filterCount} filtros restaurados: ${filterSummary}`
    
    this.restoreNotificationTarget.innerHTML = `
      <div class="flex items-center justify-between p-3 bg-teal-50 border border-teal-200 rounded-lg">
        <div class="flex items-center space-x-2">
          <svg class="w-5 h-5 text-teal-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
          </svg>
          <span class="text-sm text-teal-800">${message}</span>
        </div>
        <button type="button" 
                class="text-teal-600 hover:text-teal-700 text-sm font-medium"
                data-action="click->dashboard-filter-persistence#clearAndReload">
          Limpiar filtros
        </button>
      </div>
    `
    
    // Show notification with animation
    this.restoreNotificationTarget.style.display = 'block'
    this.restoreNotificationTarget.style.opacity = '0'
    this.restoreNotificationTarget.style.transform = 'translateY(-10px)'
    
    requestAnimationFrame(() => {
      this.restoreNotificationTarget.style.transition = 'all 0.3s ease-out'
      this.restoreNotificationTarget.style.opacity = '1'
      this.restoreNotificationTarget.style.transform = 'translateY(0)'
    })
    
    // Auto-hide after 5 seconds
    setTimeout(() => {
      this.hideRestoreNotification()
    }, 5000)
  }
  
  // Create restore notification element if it doesn't exist
  createRestoreNotification() {
    const notification = document.createElement('div')
    notification.dataset.dashboardFilterPersistenceTarget = 'restoreNotification'
    notification.className = 'mb-4'
    notification.style.display = 'none'
    
    // Insert at the top of the dashboard
    const container = this.element.querySelector('.dashboard-content') || this.element
    container.insertBefore(notification, container.firstChild)
  }
  
  // Hide restore notification
  hideRestoreNotification() {
    if (!this.hasRestoreNotificationTarget) return
    
    this.restoreNotificationTarget.style.transition = 'all 0.3s ease-out'
    this.restoreNotificationTarget.style.opacity = '0'
    this.restoreNotificationTarget.style.transform = 'translateY(-10px)'
    
    setTimeout(() => {
      this.restoreNotificationTarget.style.display = 'none'
    }, 300)
  }
  
  // Show smart filter suggestions based on usage
  showSmartSuggestions(suggestions) {
    if (!this.showNotificationsValue) return
    
    const notification = document.createElement('div')
    notification.className = 'mb-4 p-3 bg-amber-50 border border-amber-200 rounded-lg'
    
    let suggestionText = []
    if (suggestions.suggestedCategories) {
      suggestionText.push('categorías frecuentes')
    }
    if (suggestions.suggestedPeriod) {
      suggestionText.push(`período "${suggestions.suggestedPeriod}"`)
    }
    
    notification.innerHTML = `
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-2">
          <svg class="w-5 h-5 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"></path>
          </svg>
          <span class="text-sm text-amber-800">
            Sugerencia: Aplicar ${suggestionText.join(' y ')} basado en tu uso frecuente
          </span>
        </div>
        <button type="button" 
                class="text-amber-600 hover:text-amber-700 text-sm font-medium"
                data-action="click->dashboard-filter-persistence#applySuggestions">
          Aplicar
        </button>
      </div>
    `
    
    notification.dataset.suggestions = JSON.stringify(suggestions)
    
    const container = this.element.querySelector('.dashboard-content') || this.element
    container.insertBefore(notification, container.firstChild)
    
    // Auto-hide after 8 seconds
    setTimeout(() => {
      notification.style.transition = 'all 0.3s ease-out'
      notification.style.opacity = '0'
      setTimeout(() => notification.remove(), 300)
    }, 8000)
  }
  
  // Apply smart suggestions
  applySuggestions(event) {
    const notification = event.currentTarget.closest('[data-suggestions]')
    const suggestions = JSON.parse(notification.dataset.suggestions)
    
    const filterChipsController = this.findController('dashboard-filter-chips')
    if (filterChipsController) {
      const newFilters = {
        categories: suggestions.suggestedCategories || [],
        statuses: [],
        period: suggestions.suggestedPeriod || null
      }
      
      filterChipsController.activeFiltersValue = newFilters
      filterChipsController.applyFilters()
    }
    
    // Remove notification
    notification.remove()
  }
  
  // Set up event listeners
  setupEventListeners() {
    // Listen for filter changes from filter chips
    this.element.addEventListener('dashboard-filter-chips:filtersApplied', (event) => {
      this.handleFilterChange(event.detail.filters)
    })
    
    // Listen for virtual scroll events
    this.element.addEventListener('virtual-scroll:scrolled', (event) => {
      this.handleScrollChange(event.detail.position)
    })
    
    // Listen for view mode changes
    this.element.addEventListener('dashboard-expenses:viewModeChanged', (event) => {
      this.handleViewModeChange(event.detail.mode)
    })
    
    // Listen for browser back/forward
    this.popstateListener = () => {
      this.handlePopState()
    }
    window.addEventListener('popstate', this.popstateListener)
    
    // Save state before unload
    this.beforeUnloadListener = () => {
      this.saveCurrentState()
    }
    window.addEventListener('beforeunload', this.beforeUnloadListener)
  }
  
  // Monitor for filter changes
  monitorFilterChanges() {
    // Create a MutationObserver to watch for DOM changes
    this.filterObserver = new MutationObserver((mutations) => {
      // Check if filter chips have changed
      const hasFilterChange = mutations.some(mutation => {
        return mutation.target.closest('[data-controller*="dashboard-filter-chips"]') ||
               mutation.target.querySelector('[data-dashboard-filter-chips-target]')
      })
      
      if (hasFilterChange) {
        this.debouncedSaveState()
      }
    })
    
    // Observe the dashboard element for changes
    this.filterObserver.observe(this.element, {
      attributes: true,
      childList: true,
      subtree: true,
      attributeFilter: ['class', 'aria-pressed', 'checked']
    })
  }
  
  // Handle filter change event
  handleFilterChange(filters) {
    // Update state manager
    this.stateManager.saveState({
      categories: filters.categories || [],
      statuses: filters.statuses || [],
      period: filters.period || null
    })
    
    // Update persistence indicator
    this.updatePersistenceIndicator()
  }
  
  // Handle scroll position change
  handleScrollChange(position) {
    // Only save significant scroll changes
    if (Math.abs(position - this.stateManager.state.scroll_position) > 100) {
      this.stateManager.saveState({
        scroll_position: position
      }, { updateURL: false }) // Don't update URL for scroll
    }
  }
  
  // Handle view mode change
  handleViewModeChange(mode) {
    this.stateManager.saveState({
      view_mode: mode
    })
  }
  
  // Handle browser back/forward navigation
  handlePopState() {
    // Reload state from URL
    const restoredState = this.stateManager.loadState()
    this.applyRestoredState(restoredState)
  }
  
  // Set up cross-tab synchronization
  setupCrossTabSync() {
    this.storageListener = (event) => {
      if (event.key === FilterStateManager.STORAGE_KEY) {
        // Another tab updated the filters
        if (event.newValue) {
          try {
            const newState = JSON.parse(event.newValue)
            
            // Check if the change is significant
            if (this.isSignificantChange(this.stateManager.state, newState)) {
              // Show notification about cross-tab update
              this.showCrossTabNotification()
              
              // Apply the new state
              this.stateManager.state = newState
              this.applyRestoredState(newState)
            }
          } catch (e) {
            console.warn('Failed to parse cross-tab state:', e)
          }
        }
      }
    }
    
    window.addEventListener('storage', this.storageListener)
  }
  
  // Check if state change is significant
  isSignificantChange(oldState, newState) {
    // Check if filters have changed
    const oldFilters = JSON.stringify({
      categories: oldState.categories || [],
      statuses: oldState.statuses || [],
      period: oldState.period
    })
    
    const newFilters = JSON.stringify({
      categories: newState.categories || [],
      statuses: newState.statuses || [],
      period: newState.period
    })
    
    return oldFilters !== newFilters
  }
  
  // Show cross-tab synchronization notification
  showCrossTabNotification() {
    const notification = document.createElement('div')
    notification.className = 'fixed bottom-4 right-4 p-3 bg-slate-50 border border-slate-200 rounded-lg shadow-lg z-50'
    notification.innerHTML = `
      <div class="flex items-center space-x-2">
        <svg class="w-5 h-5 text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
        </svg>
        <span class="text-sm text-slate-700">Filtros actualizados desde otra pestaña</span>
      </div>
    `
    
    document.body.appendChild(notification)
    
    // Animate in
    notification.style.opacity = '0'
    notification.style.transform = 'translateY(10px)'
    requestAnimationFrame(() => {
      notification.style.transition = 'all 0.3s ease-out'
      notification.style.opacity = '1'
      notification.style.transform = 'translateY(0)'
    })
    
    // Auto-remove after 3 seconds
    setTimeout(() => {
      notification.style.opacity = '0'
      notification.style.transform = 'translateY(10px)'
      setTimeout(() => notification.remove(), 300)
    }, 3000)
  }
  
  // Set up periodic state validation
  setupStateValidation() {
    // Validate state every 30 seconds
    this.validationInterval = setInterval(() => {
      this.validateCurrentState()
    }, 30000)
  }
  
  // Validate current state against actual UI
  validateCurrentState() {
    const filterChipsController = this.findController('dashboard-filter-chips')
    if (!filterChipsController) return
    
    const uiState = {
      categories: filterChipsController.activeFiltersValue.categories || [],
      statuses: filterChipsController.activeFiltersValue.statuses || [],
      period: filterChipsController.activeFiltersValue.period
    }
    
    const savedState = {
      categories: this.stateManager.state.categories || [],
      statuses: this.stateManager.state.statuses || [],
      period: this.stateManager.state.period
    }
    
    // Check if states are in sync
    if (JSON.stringify(uiState) !== JSON.stringify(savedState)) {
      // UI state has diverged, update saved state
      this.stateManager.saveState(uiState)
    }
  }
  
  // Save current state
  saveCurrentState() {
    const filterChipsController = this.findController('dashboard-filter-chips')
    const virtualScrollController = this.findController('dashboard-virtual-scroll')
    const dashboardController = this.findController('dashboard-expenses')
    
    const currentState = {}
    
    if (filterChipsController) {
      Object.assign(currentState, {
        categories: filterChipsController.activeFiltersValue.categories || [],
        statuses: filterChipsController.activeFiltersValue.statuses || [],
        period: filterChipsController.activeFiltersValue.period
      })
    }
    
    if (virtualScrollController && virtualScrollController.hasViewportTarget) {
      currentState.scroll_position = virtualScrollController.viewportTarget.scrollTop
      currentState.virtual_enabled = virtualScrollController.enabled || false
    }
    
    if (dashboardController) {
      currentState.view_mode = dashboardController.viewModeValue
    }
    
    this.stateManager.saveState(currentState)
  }
  
  // Debounced state save
  debouncedSaveState = this.debounce(() => {
    this.saveCurrentState()
  }, 500)
  
  // Update persistence indicator
  updatePersistenceIndicator() {
    if (!this.hasPersistenceIndicatorTarget) return
    
    const hasFilters = this.stateManager.hasActiveFilters()
    const filterCount = this.stateManager.getFilterCount()
    
    if (hasFilters) {
      this.persistenceIndicatorTarget.innerHTML = `
        <div class="flex items-center space-x-1 text-xs text-teal-600">
          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
          </svg>
          <span>${filterCount} filtros guardados</span>
        </div>
      `
      this.persistenceIndicatorTarget.style.display = 'block'
    } else {
      this.persistenceIndicatorTarget.style.display = 'none'
    }
  }
  
  // Share current filter state
  shareFilters(event) {
    event?.preventDefault()
    
    const shareUrl = this.stateManager.exportState()
    
    // Check if Web Share API is available
    if (navigator.share) {
      navigator.share({
        title: 'Filtros de Gastos',
        text: `Compartir filtros: ${this.stateManager.getFilterSummary()}`,
        url: shareUrl
      }).catch(err => {
        // Fallback to clipboard
        this.copyToClipboard(shareUrl)
      })
    } else {
      // Copy to clipboard
      this.copyToClipboard(shareUrl)
    }
  }
  
  // Copy URL to clipboard
  copyToClipboard(url) {
    navigator.clipboard.writeText(url).then(() => {
      this.showToast('Enlace copiado al portapapeles', 'success')
    }).catch(() => {
      // Fallback for older browsers
      const input = document.createElement('input')
      input.value = url
      document.body.appendChild(input)
      input.select()
      document.execCommand('copy')
      document.body.removeChild(input)
      this.showToast('Enlace copiado al portapapeles', 'success')
    })
  }
  
  // Reset all filters and clear persistence
  resetFilters(event) {
    event?.preventDefault()
    
    if (!confirm('¿Estás seguro de que quieres restablecer todos los filtros y preferencias?')) {
      return
    }
    
    // Clear all state
    this.stateManager.clearState()
    
    // Reset UI components
    const filterChipsController = this.findController('dashboard-filter-chips')
    if (filterChipsController) {
      filterChipsController.clearAllFilters()
    }
    
    // Show confirmation
    this.showToast('Filtros y preferencias restablecidos', 'success')
    
    // Update indicator
    this.updatePersistenceIndicator()
  }
  
  // Clear filters and reload
  clearAndReload(event) {
    event?.preventDefault()
    
    // Clear state
    this.stateManager.clearState()
    
    // Reload page without filters
    const url = new URL(window.location)
    const preserveParams = ['locale']
    const newParams = new URLSearchParams()
    
    preserveParams.forEach(param => {
      if (url.searchParams.has(param)) {
        newParams.set(param, url.searchParams.get(param))
      }
    })
    
    window.location.href = `${url.pathname}?${newParams.toString()}`
  }
  
  // Show toast notification
  showToast(message, type = 'info') {
    const dashboardController = this.findController('dashboard-expenses')
    if (dashboardController && dashboardController.showToast) {
      dashboardController.showToast(message, type)
    } else {
      // Fallback toast implementation
      const toast = document.createElement('div')
      toast.className = `fixed bottom-4 right-4 p-4 rounded-lg shadow-lg z-50 ${
        type === 'success' ? 'bg-emerald-50 text-emerald-800 border border-emerald-200' :
        type === 'error' ? 'bg-rose-50 text-rose-800 border border-rose-200' :
        'bg-slate-50 text-slate-800 border border-slate-200'
      }`
      toast.textContent = message
      
      document.body.appendChild(toast)
      
      setTimeout(() => {
        toast.style.transition = 'opacity 0.3s ease-out'
        toast.style.opacity = '0'
        setTimeout(() => toast.remove(), 300)
      }, 3000)
    }
  }
  
  // Find another Stimulus controller
  findController(identifier) {
    const element = this.element.querySelector(`[data-controller*="${identifier}"]`)
    if (element) {
      return this.application.getControllerForElementAndIdentifier(element, identifier)
    }
    return null
  }
  
  // Debounce utility
  debounce(func, wait) {
    let timeout
    return function executedFunction(...args) {
      const later = () => {
        clearTimeout(timeout)
        func(...args)
      }
      clearTimeout(timeout)
      timeout = setTimeout(later, wait)
    }
  }
  
  // Dispatch custom events
  dispatch(eventName, options = {}) {
    const event = new CustomEvent(`filter-persistence:${eventName}`, {
      bubbles: true,
      cancelable: true,
      ...options
    })
    this.element.dispatchEvent(event)
  }
}