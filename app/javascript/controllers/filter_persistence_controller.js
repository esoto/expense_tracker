import { Controller } from "@hotwired/stimulus"

/**
 * Filter Persistence Controller
 * Saves and restores filter state using localStorage/sessionStorage
 * Maintains filter state across navigation and page reloads
 */
export default class extends Controller {
  static targets = [
    "filterForm",
    "filterInput",
    "restoreButton",
    "clearStorageButton"
  ]
  
  static values = {
    storageKey: { type: String, default: "expense_filters" },
    storageType: { type: String, default: "session" }, // 'session' or 'local'
    autoRestore: { type: Boolean, default: true },
    autoSave: { type: Boolean, default: true },
    maxAge: { type: Number, default: 86400000 } // 24 hours in ms
  }
  
  connect() {
    // Set up storage
    this.storage = this.storageTypeValue === 'local' ? localStorage : sessionStorage
    
    // Auto-restore filters if enabled
    if (this.autoRestoreValue) {
      this.restoreFilters()
    }
    
    // Set up auto-save listeners
    if (this.autoSaveValue) {
      this.setupAutoSave()
    }
    
    // Check if we have saved filters to show restore button
    this.updateRestoreButtonVisibility()
    
    // Listen for storage events (cross-tab sync)
    this.setupStorageListener()
    
    // Clean up old stored filters
    this.cleanupOldFilters()
  }
  
  disconnect() {
    // Remove storage listener
    if (this.storageHandler) {
      window.removeEventListener('storage', this.storageHandler)
    }
    
    // Clear any pending save timers
    if (this.saveTimer) {
      clearTimeout(this.saveTimer)
    }
  }
  
  /**
   * Set up auto-save functionality
   */
  setupAutoSave() {
    // Debounced save on input changes
    if (this.hasFilterInputTarget) {
      this.filterInputTargets.forEach(input => {
        input.addEventListener('change', () => this.debouncedSave())
        
        // For text inputs, save on input with longer debounce
        if (input.type === 'text' || input.type === 'search') {
          input.addEventListener('input', () => this.debouncedSave(1000))
        }
      })
    }
    
    // Save on form submit
    if (this.hasFilterFormTarget) {
      this.filterFormTarget.addEventListener('submit', (e) => {
        this.saveFilters()
      })
    }
  }
  
  /**
   * Debounced save function
   */
  debouncedSave(delay = 500) {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer)
    }
    
    this.saveTimer = setTimeout(() => {
      this.saveFilters()
    }, delay)
  }
  
  /**
   * Save current filters to storage
   */
  saveFilters() {
    const filters = this.getCurrentFilters()
    
    if (Object.keys(filters).length === 0) {
      // Don't save empty filters
      this.clearStoredFilters()
      return
    }
    
    const data = {
      filters: filters,
      timestamp: Date.now(),
      url: window.location.pathname
    }
    
    try {
      this.storage.setItem(this.storageKeyValue, JSON.stringify(data))
      this.showNotification('Filtros guardados', 'success')
      this.updateRestoreButtonVisibility()
      
      // Dispatch event
      this.dispatch('filtersSaved', { detail: { filters } })
    } catch (error) {
      console.error('Error saving filters:', error)
      this.showNotification('Error al guardar filtros', 'error')
    }
  }
  
  /**
   * Restore filters from storage
   */
  restoreFilters() {
    try {
      const stored = this.storage.getItem(this.storageKeyValue)
      if (!stored) return false
      
      const data = JSON.parse(stored)
      
      // Check if data is expired
      if (this.isExpired(data.timestamp)) {
        this.clearStoredFilters()
        return false
      }
      
      // Check if we're on the same page
      if (data.url && data.url !== window.location.pathname) {
        return false
      }
      
      // Apply filters if not already in URL
      if (!this.hasFiltersInUrl()) {
        this.applyFilters(data.filters)
        this.showNotification('Filtros restaurados', 'info')
        return true
      }
      
      return false
    } catch (error) {
      console.error('Error restoring filters:', error)
      this.clearStoredFilters()
      return false
    }
  }
  
  /**
   * Get current filters from form or URL
   */
  getCurrentFilters() {
    const filters = {}
    
    // Get from URL parameters
    const params = new URLSearchParams(window.location.search)
    
    // Define filter parameters to save
    const filterParams = [
      'category', 'bank', 'status',
      'start_date', 'end_date', 'period',
      'min_amount', 'max_amount',
      'search_query', 'sort_by', 'sort_direction'
    ]
    
    filterParams.forEach(param => {
      const value = params.get(param)
      if (value) {
        filters[param] = value
      }
    })
    
    // Get array parameters
    const arrayParams = ['category_ids[]', 'banks[]']
    arrayParams.forEach(param => {
      const values = params.getAll(param)
      if (values.length > 0) {
        filters[param] = values
      }
    })
    
    return filters
  }
  
  /**
   * Apply filters to the page
   */
  applyFilters(filters) {
    const params = new URLSearchParams()
    
    Object.entries(filters).forEach(([key, value]) => {
      if (Array.isArray(value)) {
        value.forEach(v => params.append(key, v))
      } else {
        params.set(key, value)
      }
    })
    
    // Navigate to filtered URL
    const url = params.toString() ? `${window.location.pathname}?${params.toString()}` : window.location.pathname
    window.location.href = url
  }
  
  /**
   * Clear stored filters
   */
  clearStoredFilters() {
    try {
      this.storage.removeItem(this.storageKeyValue)
      this.updateRestoreButtonVisibility()
      this.showNotification('Filtros limpiados', 'info')
      
      // Dispatch event
      this.dispatch('filtersCleared')
    } catch (error) {
      console.error('Error clearing filters:', error)
    }
  }
  
  /**
   * Check if filters are present in URL
   */
  hasFiltersInUrl() {
    const params = new URLSearchParams(window.location.search)
    const filterParams = [
      'category', 'bank', 'status',
      'start_date', 'end_date', 'period',
      'min_amount', 'max_amount',
      'search_query'
    ]
    
    return filterParams.some(param => params.has(param))
  }
  
  /**
   * Check if stored data is expired
   */
  isExpired(timestamp) {
    return Date.now() - timestamp > this.maxAgeValue
  }
  
  /**
   * Update restore button visibility
   */
  updateRestoreButtonVisibility() {
    if (!this.hasRestoreButtonTarget) return
    
    try {
      const stored = this.storage.getItem(this.storageKeyValue)
      if (stored) {
        const data = JSON.parse(stored)
        if (!this.isExpired(data.timestamp) && Object.keys(data.filters).length > 0) {
          this.restoreButtonTarget.classList.remove('hidden')
          
          // Update button text with filter count
          const filterCount = Object.keys(data.filters).length
          this.restoreButtonTarget.textContent = `Restaurar ${filterCount} filtro${filterCount > 1 ? 's' : ''}`
          return
        }
      }
    } catch (error) {
      console.error('Error checking stored filters:', error)
    }
    
    this.restoreButtonTarget.classList.add('hidden')
  }
  
  /**
   * Set up storage event listener for cross-tab sync
   */
  setupStorageListener() {
    this.storageHandler = (event) => {
      if (event.key === this.storageKeyValue) {
        if (event.newValue) {
          // Filters were saved in another tab
          this.updateRestoreButtonVisibility()
          
          // Optionally show notification
          if (this.storageTypeValue === 'local') {
            this.showNotification('Filtros actualizados en otra pestaña', 'info')
          }
        } else {
          // Filters were cleared in another tab
          this.updateRestoreButtonVisibility()
        }
      }
    }
    
    window.addEventListener('storage', this.storageHandler)
  }
  
  /**
   * Clean up old stored filters
   */
  cleanupOldFilters() {
    try {
      // Check all keys in storage
      const keysToRemove = []
      
      for (let i = 0; i < this.storage.length; i++) {
        const key = this.storage.key(i)
        
        // Check if it's a filter key
        if (key && key.startsWith('expense_filters')) {
          const stored = this.storage.getItem(key)
          if (stored) {
            const data = JSON.parse(stored)
            if (this.isExpired(data.timestamp)) {
              keysToRemove.push(key)
            }
          }
        }
      }
      
      // Remove expired keys
      keysToRemove.forEach(key => this.storage.removeItem(key))
    } catch (error) {
      console.error('Error cleaning up old filters:', error)
    }
  }
  
  /**
   * Export filters as JSON
   */
  exportFilters() {
    const filters = this.getCurrentFilters()
    const data = {
      filters: filters,
      timestamp: Date.now(),
      version: '1.0'
    }
    
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `expense_filters_${Date.now()}.json`
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
    
    this.showNotification('Filtros exportados', 'success')
  }
  
  /**
   * Import filters from JSON
   */
  async importFilters(file) {
    try {
      const text = await file.text()
      const data = JSON.parse(text)
      
      if (data.filters) {
        this.applyFilters(data.filters)
        this.showNotification('Filtros importados', 'success')
      } else {
        throw new Error('Invalid filter file')
      }
    } catch (error) {
      console.error('Error importing filters:', error)
      this.showNotification('Error al importar filtros', 'error')
    }
  }
  
  /**
   * Show notification
   */
  showNotification(message, type = 'info') {
    // Create or update notification element
    let notification = document.getElementById('filter-persistence-notification')
    
    if (!notification) {
      notification = document.createElement('div')
      notification.id = 'filter-persistence-notification'
      notification.className = 'fixed bottom-4 left-4 px-4 py-2 rounded-lg shadow-lg transition-all transform translate-y-0 opacity-100 z-50'
      document.body.appendChild(notification)
    }
    
    // Set type-specific styles
    const typeStyles = {
      'success': 'bg-emerald-100 text-emerald-800 border border-emerald-200',
      'error': 'bg-rose-100 text-rose-800 border border-rose-200',
      'info': 'bg-teal-100 text-teal-800 border border-teal-200'
    }
    
    notification.className = `fixed bottom-4 left-4 px-4 py-2 rounded-lg shadow-lg transition-all transform translate-y-0 opacity-100 z-50 ${typeStyles[type] || typeStyles.info}`
    notification.textContent = message
    
    // Auto-hide after 3 seconds
    setTimeout(() => {
      notification.classList.add('opacity-0', 'translate-y-2')
      setTimeout(() => {
        if (notification.parentNode) {
          notification.parentNode.removeChild(notification)
        }
      }, 300)
    }, 3000)
  }
  
  /**
   * Handle restore button click
   */
  restore() {
    this.restoreFilters()
  }
  
  /**
   * Handle clear storage button click
   */
  clearStorage() {
    this.clearStoredFilters()
  }
}