// Filter State Manager Utility for Task 3.8
// Centralizes filter state persistence logic across URL, LocalStorage, and Session
// Provides comprehensive state management with smart defaults and validation

export default class FilterStateManager {
  static STORAGE_KEY = 'dashboard_filter_preferences'
  static URL_PARAM_VERSION = 'v1'
  static STATE_EXPIRY_HOURS = 24
  static MAX_URL_LENGTH = 2000
  
  constructor() {
    this.initializeState()
  }
  
  // Initialize state management
  initializeState() {
    this.state = {
      categories: [],
      statuses: [],
      period: null,
      view_mode: 'compact',
      scroll_position: 0,
      virtual_enabled: false,
      sort_by: null,
      sort_direction: null,
      search_query: null,
      min_amount: null,
      max_amount: null,
      last_updated: Date.now()
    }
    
    this.defaults = {
      view_mode: 'compact',
      virtual_enabled: false,
      scroll_position: 0
    }
    
    this.frequencyTracker = this.loadFrequencyData()
  }
  
  // Load state from all sources with priority chain
  loadState() {
    const urlState = this.loadFromURL()
    const localState = this.loadFromLocalStorage()
    const sessionState = this.loadFromSession()
    
    // Priority: URL > LocalStorage > Session > Defaults
    const mergedState = this.mergeStates(
      this.defaults,
      sessionState,
      localState,
      urlState
    )
    
    // Validate and sanitize
    this.state = this.validateState(mergedState)
    
    // Track usage for smart defaults
    this.trackUsage(this.state)
    
    return this.state
  }
  
  // Save state to all persistence layers
  saveState(state, options = {}) {
    const { 
      updateURL = true, 
      updateLocal = true, 
      updateSession = true,
      debounce = true 
    } = options
    
    // Update internal state
    this.state = { ...this.state, ...state, last_updated: Date.now() }
    
    // Validate before saving
    this.state = this.validateState(this.state)
    
    // Save to different layers based on options
    if (updateURL) {
      if (debounce) {
        this.debouncedURLUpdate(this.state)
      } else {
        this.saveToURL(this.state)
      }
    }
    
    if (updateLocal) {
      this.saveToLocalStorage(this.state)
    }
    
    if (updateSession) {
      this.saveToSession(this.state)
    }
    
    // Track usage patterns
    this.trackUsage(this.state)
    
    return this.state
  }
  
  // Load state from URL parameters
  loadFromURL() {
    const params = new URLSearchParams(window.location.search)
    const state = {}
    
    // Check for encoded state parameter (for complex state)
    const encodedState = params.get('filter_state')
    if (encodedState) {
      try {
        const decoded = this.decodeState(encodedState)
        return decoded
      } catch (e) {
        console.warn('Failed to decode URL state:', e)
      }
    }
    
    // Parse individual parameters
    const categoryIds = params.getAll('category_ids[]')
    if (categoryIds.length > 0) {
      state.categories = categoryIds.map(id => parseInt(id))
    }
    
    const status = params.get('status')
    if (status) {
      state.statuses = [status]
    }
    
    const period = params.get('period')
    if (period) {
      state.period = period
    }
    
    const viewMode = params.get('view_mode')
    if (viewMode) {
      state.view_mode = viewMode
    }
    
    const sortBy = params.get('sort_by')
    if (sortBy) {
      state.sort_by = sortBy
    }
    
    const sortDirection = params.get('sort_direction')
    if (sortDirection) {
      state.sort_direction = sortDirection
    }
    
    const searchQuery = params.get('search_query')
    if (searchQuery) {
      state.search_query = searchQuery
    }
    
    const scrollPos = params.get('scroll_pos')
    if (scrollPos) {
      state.scroll_position = parseInt(scrollPos)
    }
    
    const virtualEnabled = params.get('virtual')
    if (virtualEnabled !== null) {
      state.virtual_enabled = virtualEnabled === 'true'
    }
    
    return state
  }
  
  // Save state to URL parameters
  saveToURL(state) {
    const url = new URL(window.location)
    
    // Clear existing filter params
    this.clearURLParams(url)
    
    // Check if we should use encoded state (for complex/large states)
    const stateString = JSON.stringify(state)
    if (stateString.length > 200 || this.shouldEncodeState(state)) {
      // Use encoded state for complex filters
      const encoded = this.encodeState(state)
      url.searchParams.set('filter_state', encoded)
    } else {
      // Use individual parameters for simple states
      if (state.categories && state.categories.length > 0) {
        state.categories.forEach(id => {
          url.searchParams.append('category_ids[]', id)
        })
      }
      
      if (state.statuses && state.statuses.length > 0) {
        state.statuses.forEach(status => {
          url.searchParams.append('status', status)
        })
      }
      
      if (state.period) {
        url.searchParams.set('period', state.period)
      }
      
      if (state.view_mode && state.view_mode !== this.defaults.view_mode) {
        url.searchParams.set('view_mode', state.view_mode)
      }
      
      if (state.sort_by) {
        url.searchParams.set('sort_by', state.sort_by)
      }
      
      if (state.sort_direction) {
        url.searchParams.set('sort_direction', state.sort_direction)
      }
      
      if (state.search_query) {
        url.searchParams.set('search_query', state.search_query)
      }
      
      if (state.scroll_position > 0) {
        url.searchParams.set('scroll_pos', state.scroll_position)
      }
      
      if (state.virtual_enabled) {
        url.searchParams.set('virtual', 'true')
      }
    }
    
    // Only update if URL length is reasonable
    if (url.href.length <= FilterStateManager.MAX_URL_LENGTH) {
      window.history.replaceState({}, '', url)
    } else {
      console.warn('URL too long, skipping URL update')
    }
  }
  
  // Load state from LocalStorage
  loadFromLocalStorage() {
    try {
      const stored = localStorage.getItem(FilterStateManager.STORAGE_KEY)
      if (!stored) return {}
      
      const data = JSON.parse(stored)
      
      // Check if data is expired
      if (this.isStateExpired(data)) {
        localStorage.removeItem(FilterStateManager.STORAGE_KEY)
        return {}
      }
      
      return data
    } catch (e) {
      console.warn('Failed to load from LocalStorage:', e)
      return {}
    }
  }
  
  // Save state to LocalStorage
  saveToLocalStorage(state) {
    try {
      const data = {
        ...state,
        last_updated: Date.now(),
        version: FilterStateManager.URL_PARAM_VERSION
      }
      localStorage.setItem(FilterStateManager.STORAGE_KEY, JSON.stringify(data))
    } catch (e) {
      console.warn('Failed to save to LocalStorage:', e)
    }
  }
  
  // Load state from session storage
  loadFromSession() {
    try {
      const stored = sessionStorage.getItem(FilterStateManager.STORAGE_KEY)
      if (!stored) return {}
      
      return JSON.parse(stored)
    } catch (e) {
      console.warn('Failed to load from SessionStorage:', e)
      return {}
    }
  }
  
  // Save state to session storage
  saveToSession(state) {
    try {
      sessionStorage.setItem(FilterStateManager.STORAGE_KEY, JSON.stringify(state))
    } catch (e) {
      console.warn('Failed to save to SessionStorage:', e)
    }
  }
  
  // Clear all persisted state
  clearState() {
    // Clear URL
    const url = new URL(window.location)
    this.clearURLParams(url)
    window.history.replaceState({}, '', url)
    
    // Clear storages
    localStorage.removeItem(FilterStateManager.STORAGE_KEY)
    sessionStorage.removeItem(FilterStateManager.STORAGE_KEY)
    
    // Reset to defaults
    this.state = { ...this.defaults, last_updated: Date.now() }
    
    return this.state
  }
  
  // Clear filter-related URL parameters
  clearURLParams(url) {
    const filterParams = [
      'filter_state',
      'category_ids[]',
      'status',
      'period',
      'view_mode',
      'sort_by',
      'sort_direction',
      'search_query',
      'scroll_pos',
      'virtual',
      'min_amount',
      'max_amount'
    ]
    
    // Remove all filter params
    filterParams.forEach(param => {
      // Handle array params
      if (param.endsWith('[]')) {
        const baseParam = param.slice(0, -2)
        const values = url.searchParams.getAll(param)
        values.forEach(() => {
          url.searchParams.delete(param)
        })
      } else {
        url.searchParams.delete(param)
      }
    })
  }
  
  // Merge multiple state sources with priority
  mergeStates(...states) {
    const merged = {}
    
    states.forEach(state => {
      if (!state) return
      
      Object.keys(state).forEach(key => {
        const value = state[key]
        
        // Skip null/undefined values
        if (value === null || value === undefined) return
        
        // Handle arrays specially (don't merge, replace)
        if (Array.isArray(value)) {
          if (value.length > 0) {
            merged[key] = value
          }
        } else {
          merged[key] = value
        }
      })
    })
    
    return merged
  }
  
  // Validate and sanitize state
  validateState(state) {
    const validated = { ...state }
    
    // Validate categories (must be array of numbers)
    if (validated.categories) {
      validated.categories = validated.categories
        .filter(id => typeof id === 'number' || !isNaN(parseInt(id)))
        .map(id => parseInt(id))
    }
    
    // Validate statuses
    if (validated.statuses) {
      const validStatuses = ['pending', 'processed']
      validated.statuses = validated.statuses.filter(s => validStatuses.includes(s))
    }
    
    // Validate period
    if (validated.period) {
      const validPeriods = ['today', 'week', 'month', 'year', 'all']
      if (!validPeriods.includes(validated.period)) {
        validated.period = null
      }
    }
    
    // Validate view mode
    if (validated.view_mode) {
      const validModes = ['compact', 'expanded']
      if (!validModes.includes(validated.view_mode)) {
        validated.view_mode = this.defaults.view_mode
      }
    }
    
    // Validate sort
    if (validated.sort_direction) {
      const validDirections = ['asc', 'desc']
      if (!validDirections.includes(validated.sort_direction)) {
        validated.sort_direction = null
      }
    }
    
    // Sanitize search query
    if (validated.search_query) {
      validated.search_query = validated.search_query.trim().substring(0, 100)
    }
    
    // Validate scroll position
    if (validated.scroll_position) {
      validated.scroll_position = Math.max(0, parseInt(validated.scroll_position) || 0)
    }
    
    return validated
  }
  
  // Check if state is expired
  isStateExpired(state) {
    if (!state.last_updated) return true
    
    const expiryMs = FilterStateManager.STATE_EXPIRY_HOURS * 60 * 60 * 1000
    return Date.now() - state.last_updated > expiryMs
  }
  
  // Encode state for URL parameter
  encodeState(state) {
    const simplified = this.simplifyState(state)
    const json = JSON.stringify(simplified)
    return btoa(encodeURIComponent(json))
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=/g, '')
  }
  
  // Decode state from URL parameter
  decodeState(encoded) {
    try {
      // Restore Base64 padding
      const padding = 4 - (encoded.length % 4)
      if (padding < 4) {
        encoded += '='.repeat(padding)
      }
      
      // Restore Base64 characters
      encoded = encoded.replace(/-/g, '+').replace(/_/g, '/')
      
      const json = decodeURIComponent(atob(encoded))
      return JSON.parse(json)
    } catch (e) {
      console.error('Failed to decode state:', e)
      return {}
    }
  }
  
  // Simplify state for encoding (remove defaults)
  simplifyState(state) {
    const simplified = {}
    
    Object.keys(state).forEach(key => {
      const value = state[key]
      const defaultValue = this.defaults[key]
      
      // Only include non-default values
      if (value !== defaultValue) {
        // Skip empty arrays
        if (Array.isArray(value) && value.length === 0) return
        // Skip null/undefined
        if (value === null || value === undefined) return
        // Skip metadata fields
        if (key === 'last_updated' || key === 'version') return
        
        simplified[key] = value
      }
    })
    
    return simplified
  }
  
  // Check if state should be encoded
  shouldEncodeState(state) {
    // Encode if we have complex filters
    return (state.categories && state.categories.length > 3) ||
           (state.min_amount !== null && state.max_amount !== null) ||
           (state.search_query && state.search_query.length > 20)
  }
  
  // Debounced URL update
  debouncedURLUpdate = this.debounce((state) => {
    this.saveToURL(state)
  }, 500)
  
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
  
  // Track filter usage for smart defaults
  trackUsage(state) {
    if (!state.categories || state.categories.length === 0) return
    
    // Update frequency data
    state.categories.forEach(categoryId => {
      if (!this.frequencyTracker.categories[categoryId]) {
        this.frequencyTracker.categories[categoryId] = 0
      }
      this.frequencyTracker.categories[categoryId]++
    })
    
    if (state.period) {
      if (!this.frequencyTracker.periods[state.period]) {
        this.frequencyTracker.periods[state.period] = 0
      }
      this.frequencyTracker.periods[state.period]++
    }
    
    if (state.view_mode) {
      if (!this.frequencyTracker.viewModes[state.view_mode]) {
        this.frequencyTracker.viewModes[state.view_mode] = 0
      }
      this.frequencyTracker.viewModes[state.view_mode]++
    }
    
    // Save frequency data
    this.saveFrequencyData()
  }
  
  // Load frequency tracking data
  loadFrequencyData() {
    try {
      const stored = localStorage.getItem('dashboard_filter_frequency')
      if (stored) {
        return JSON.parse(stored)
      }
    } catch (e) {
      console.warn('Failed to load frequency data:', e)
    }
    
    return {
      categories: {},
      periods: {},
      viewModes: {},
      combinations: []
    }
  }
  
  // Save frequency tracking data
  saveFrequencyData() {
    try {
      localStorage.setItem('dashboard_filter_frequency', JSON.stringify(this.frequencyTracker))
    } catch (e) {
      console.warn('Failed to save frequency data:', e)
    }
  }
  
  // Get smart defaults based on usage patterns
  getSmartDefaults() {
    const defaults = { ...this.defaults }
    
    // Most used categories
    const topCategories = Object.entries(this.frequencyTracker.categories)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([id]) => parseInt(id))
    
    if (topCategories.length > 0) {
      defaults.suggestedCategories = topCategories
    }
    
    // Most used period
    const topPeriod = Object.entries(this.frequencyTracker.periods)
      .sort((a, b) => b[1] - a[1])[0]
    
    if (topPeriod) {
      defaults.suggestedPeriod = topPeriod[0]
    }
    
    // Preferred view mode
    const topViewMode = Object.entries(this.frequencyTracker.viewModes)
      .sort((a, b) => b[1] - a[1])[0]
    
    if (topViewMode) {
      defaults.view_mode = topViewMode[0]
    }
    
    return defaults
  }
  
  // Export state for sharing
  exportState() {
    const state = this.simplifyState(this.state)
    const url = new URL(window.location)
    
    // Clear existing params
    this.clearURLParams(url)
    
    // Add encoded state
    const encoded = this.encodeState(state)
    url.searchParams.set('filter_state', encoded)
    
    return url.href
  }
  
  // Import state from URL
  importState(url) {
    try {
      const parsedUrl = new URL(url)
      const encoded = parsedUrl.searchParams.get('filter_state')
      
      if (encoded) {
        const state = this.decodeState(encoded)
        this.saveState(state)
        return true
      }
    } catch (e) {
      console.error('Failed to import state:', e)
    }
    
    return false
  }
  
  // Check if any filters are active
  hasActiveFilters() {
    return (this.state.categories && this.state.categories.length > 0) ||
           (this.state.statuses && this.state.statuses.length > 0) ||
           this.state.period !== null ||
           this.state.search_query !== null ||
           this.state.min_amount !== null ||
           this.state.max_amount !== null
  }
  
  // Get filter count for UI
  getFilterCount() {
    let count = 0
    
    if (this.state.categories && this.state.categories.length > 0) {
      count += this.state.categories.length
    }
    
    if (this.state.statuses && this.state.statuses.length > 0) {
      count += this.state.statuses.length
    }
    
    if (this.state.period) count++
    if (this.state.search_query) count++
    if (this.state.min_amount !== null || this.state.max_amount !== null) count++
    
    return count
  }
  
  // Get human-readable filter summary
  getFilterSummary() {
    const parts = []
    
    if (this.state.categories && this.state.categories.length > 0) {
      parts.push(`${this.state.categories.length} categorías`)
    }
    
    if (this.state.statuses && this.state.statuses.length > 0) {
      const statusText = this.state.statuses.map(s => 
        s === 'pending' ? 'pendiente' : 'procesado'
      ).join(', ')
      parts.push(`Estado: ${statusText}`)
    }
    
    if (this.state.period) {
      const periodMap = {
        today: 'Hoy',
        week: 'Esta semana',
        month: 'Este mes',
        year: 'Este año',
        all: 'Todo'
      }
      parts.push(periodMap[this.state.period] || this.state.period)
    }
    
    if (this.state.search_query) {
      parts.push(`Búsqueda: "${this.state.search_query}"`)
    }
    
    return parts.join(' • ')
  }
}