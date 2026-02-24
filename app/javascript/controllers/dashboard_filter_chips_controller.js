import { Controller } from "@hotwired/stimulus"
import FilterStateManager from "utilities/filter_state_manager"

// Dashboard Filter Chips Controller
// Manages filter chip selection, state management, and real-time filtering
// Implements Task 3.6: Dashboard Filter Chips for Epic 3
// Enhanced with Task 3.8: Filter Persistence integration
export default class extends Controller {
  static targets = [
    "chip",
    "categoryChip",
    "statusChip",
    "periodChip", 
    "clearButton",
    "expenseContainer",
    "loadingIndicator",
    "filterCount"
  ]

  static values = {
    activeFilters: Object,
    dashboardUrl: String
  }

  connect() {
    // Initialize filter state manager for persistence (Task 3.8)
    this.stateManager = new FilterStateManager()
    
    // Load persisted state first
    const persistedState = this.stateManager.loadState()
    
    // Initialize active filters from persisted state or defaults
    this.activeFiltersValue = {
      categories: persistedState.categories || [],
      statuses: persistedState.statuses || [],
      period: persistedState.period || null
    }
    
    // Initialize from URL parameters if present (URL has priority)
    this.initializeFromUrlParams()
    
    // Set up keyboard navigation
    this.setupKeyboardNavigation()
    
    // Update visual state
    this.updateChipStates()
    this.updateClearButtonVisibility()
    
    // Check if filters were restored
    if (this.hasActiveFilters()) {
      this.showRestoredIndicator()
    }
  }

  disconnect() {
    // Clean up any event listeners
    if (this.abortController) {
      this.abortController.abort()
    }
  }

  // Initialize filters from URL parameters
  initializeFromUrlParams() {
    const params = new URLSearchParams(window.location.search)
    
    // Parse category IDs
    const categoryIds = params.getAll('category_ids[]')
    if (categoryIds.length > 0) {
      this.activeFiltersValue.categories = categoryIds.map(id => parseInt(id))
    }
    
    // Parse status filter
    const status = params.get('status')
    if (status) {
      this.activeFiltersValue.statuses = [status]
    }
    
    // Parse period filter
    const period = params.get('period')
    if (period) {
      this.activeFiltersValue.period = period
    }
  }

  // Toggle category filter chip
  toggleCategory(event) {
    event.preventDefault()
    const chip = event.currentTarget
    const categoryId = parseInt(chip.dataset.categoryId)
    
    const index = this.activeFiltersValue.categories.indexOf(categoryId)
    if (index > -1) {
      this.activeFiltersValue.categories.splice(index, 1)
    } else {
      this.activeFiltersValue.categories.push(categoryId)
    }
    
    this.applyFilters()
  }

  // Toggle status filter chip
  toggleStatus(event) {
    event.preventDefault()
    const chip = event.currentTarget
    const status = chip.dataset.status
    
    const index = this.activeFiltersValue.statuses.indexOf(status)
    if (index > -1) {
      this.activeFiltersValue.statuses.splice(index, 1)
    } else {
      this.activeFiltersValue.statuses.push(status)
    }
    
    this.applyFilters()
  }

  // Select period filter chip (exclusive - only one period at a time)
  selectPeriod(event) {
    event.preventDefault()
    const chip = event.currentTarget
    const period = chip.dataset.period
    
    if (this.activeFiltersValue.period === period) {
      this.activeFiltersValue.period = null
    } else {
      this.activeFiltersValue.period = period
    }
    
    this.applyFilters()
  }

  // Clear all filters
  clearAllFilters(event) {
    if (event) event.preventDefault()
    
    this.activeFiltersValue = {
      categories: [],
      statuses: [],
      period: null
    }
    
    // Clear persistence (Task 3.8)
    this.stateManager.clearState()
    
    this.applyFilters()
  }

  // Apply filters and update expense list
  async applyFilters() {
    // Update visual states immediately
    this.updateChipStates()
    this.updateClearButtonVisibility()
    this.updateFilterCount()
    
    // Show loading state
    this.showLoading()
    
    // Build filter parameters
    const params = this.buildFilterParams()
    
    // Save to persistence layer (Task 3.8)
    this.stateManager.saveState({
      categories: this.activeFiltersValue.categories,
      statuses: this.activeFiltersValue.statuses,
      period: this.activeFiltersValue.period
    })
    
    // Update URL without page reload
    this.updateUrlParams(params)
    
    // Abort any pending request
    if (this.abortController) {
      this.abortController.abort()
    }
    
    try {
      this.abortController = new AbortController()
      
      // Fetch filtered expenses
      const url = new URL(this.dashboardUrlValue || '/expenses/dashboard', window.location.origin)
      params.forEach((value, key) => url.searchParams.append(key, value))
      url.searchParams.append('partial', 'expenses_list')
      
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Accept': 'text/html',
          'X-Requested-With': 'XMLHttpRequest'
        },
        signal: this.abortController.signal
      })
      
      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`)
      
      const html = await response.text()
      
      // Update expense container with smooth transition
      await this.updateExpenseList(html)
      
      // Dispatch custom event for other controllers
      this.dispatch('filtersApplied', {
        detail: {
          filters: this.activeFiltersValue,
          params: Object.fromEntries(params),
          persisted: true // Indicate filters are persisted (Task 3.8)
        }
      })
      
    } catch (error) {
      if (error.name !== 'AbortError') {
        console.error('Error applying filters:', error)
        this.showError('Error al aplicar filtros. Por favor intente de nuevo.')
      }
    } finally {
      this.hideLoading()
    }
  }

  // Build URL parameters from active filters
  buildFilterParams() {
    const params = new URLSearchParams()
    
    // Add category filters
    this.activeFiltersValue.categories.forEach(categoryId => {
      params.append('category_ids[]', categoryId)
    })
    
    // Add status filters
    this.activeFiltersValue.statuses.forEach(status => {
      params.append('status', status)
    })
    
    // Add period filter
    if (this.activeFiltersValue.period) {
      params.append('period', this.activeFiltersValue.period)
    }
    
    // Preserve other parameters
    const currentParams = new URLSearchParams(window.location.search)
    const preserveKeys = ['view_mode', 'sort_by', 'sort_direction']
    preserveKeys.forEach(key => {
      if (currentParams.has(key) && !params.has(key)) {
        params.append(key, currentParams.get(key))
      }
    })
    
    return params
  }

  // Update URL parameters without page reload
  updateUrlParams(params) {
    const url = new URL(window.location)
    
    // Clear existing filter params
    const clearKeys = ['category_ids[]', 'status', 'period']
    clearKeys.forEach(key => url.searchParams.delete(key))
    
    // Set new params
    params.forEach((value, key) => {
      if (clearKeys.includes(key) || clearKeys.some(k => key.startsWith(k.replace('[]', '')))) {
        url.searchParams.append(key, value)
      } else {
        url.searchParams.set(key, value)
      }
    })
    
    // Update browser history
    window.history.replaceState({}, '', url)
  }

  // Update visual state of filter chips
  updateChipStates() {
    // Update category chips
    this.categoryChipTargets.forEach(chip => {
      const categoryId = parseInt(chip.dataset.categoryId)
      const isActive = this.activeFiltersValue.categories.includes(categoryId)
      this.setChipActive(chip, isActive)
    })
    
    // Update status chips
    this.statusChipTargets.forEach(chip => {
      const status = chip.dataset.status
      const isActive = this.activeFiltersValue.statuses.includes(status)
      this.setChipActive(chip, isActive)
    })
    
    // Update period chips
    this.periodChipTargets.forEach(chip => {
      const period = chip.dataset.period
      const isActive = this.activeFiltersValue.period === period
      this.setChipActive(chip, isActive)
    })
  }

  // Set chip active/inactive visual state
  setChipActive(chip, isActive) {
    if (isActive) {
      chip.classList.remove('bg-white', 'text-slate-700', 'border-slate-300', 'hover:bg-slate-50')
      chip.classList.add('bg-teal-700', 'text-white', 'border-teal-700', 'hover:bg-teal-800')
      chip.setAttribute('aria-pressed', 'true')
    } else {
      chip.classList.remove('bg-teal-700', 'text-white', 'border-teal-700', 'hover:bg-teal-800')
      chip.classList.add('bg-white', 'text-slate-700', 'border-slate-300', 'hover:bg-slate-50')
      chip.setAttribute('aria-pressed', 'false')
    }
  }

  // Update clear button visibility
  updateClearButtonVisibility() {
    const hasActiveFilters = this.hasActiveFilters()
    
    if (this.hasClearButtonTarget) {
      if (hasActiveFilters) {
        this.clearButtonTarget.classList.remove('hidden')
        this.clearButtonTarget.classList.add('flex')
      } else {
        this.clearButtonTarget.classList.remove('flex')
        this.clearButtonTarget.classList.add('hidden')
      }
    }
  }

  // Update filter count badge
  updateFilterCount() {
    if (this.hasFilterCountTarget) {
      const count = this.getActiveFilterCount()
      if (count > 0) {
        this.filterCountTarget.textContent = count
        this.filterCountTarget.classList.remove('hidden')
      } else {
        this.filterCountTarget.classList.add('hidden')
      }
    }
  }

  // Check if any filters are active
  hasActiveFilters() {
    return this.activeFiltersValue.categories.length > 0 ||
           this.activeFiltersValue.statuses.length > 0 ||
           this.activeFiltersValue.period !== null
  }

  // Get count of active filters
  getActiveFilterCount() {
    return this.activeFiltersValue.categories.length +
           this.activeFiltersValue.statuses.length +
           (this.activeFiltersValue.period ? 1 : 0)
  }

  // Update expense list with animation
  async updateExpenseList(html) {
    if (!this.hasExpenseContainerTarget) return
    
    // Fade out current content
    this.expenseContainerTarget.style.opacity = '0.5'
    this.expenseContainerTarget.style.transition = 'opacity 0.2s ease-out'
    
    // Wait for fade out
    await new Promise(resolve => setTimeout(resolve, 200))
    
    // Update content
    this.expenseContainerTarget.innerHTML = html
    
    // Fade in new content
    this.expenseContainerTarget.style.opacity = '1'
    
    // Dispatch event for expense list update
    this.dispatch('expenseListUpdated', {
      detail: { filters: this.activeFiltersValue }
    })
  }

  // Show loading indicator
  showLoading() {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.remove('hidden')
    }
    
    // Add loading state to chips
    this.chipTargets.forEach(chip => {
      chip.classList.add('opacity-50', 'pointer-events-none')
    })
  }

  // Hide loading indicator
  hideLoading() {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.add('hidden')
    }
    
    // Remove loading state from chips
    this.chipTargets.forEach(chip => {
      chip.classList.remove('opacity-50', 'pointer-events-none')
    })
  }

  // Show error message
  showError(message) {
    // Create toast notification
    const toast = document.createElement('div')
    toast.className = 'fixed bottom-4 right-4 bg-rose-50 border border-rose-200 text-rose-700 px-4 py-3 rounded-lg shadow-lg z-50'
    toast.innerHTML = `
      <div class="flex items-center gap-2">
        <svg class="w-5 h-5 text-rose-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
        <span>${message}</span>
      </div>
    `
    
    document.body.appendChild(toast)
    
    // Remove after 3 seconds
    setTimeout(() => {
      toast.classList.add('opacity-0', 'transition-opacity', 'duration-300')
      setTimeout(() => toast.remove(), 300)
    }, 3000)
  }

  // Keyboard navigation setup
  setupKeyboardNavigation() {
    this.element.addEventListener('keydown', (event) => {
      // Clear all filters with Escape key
      if (event.key === 'Escape' && this.hasActiveFilters()) {
        event.preventDefault()
        this.clearAllFilters()
      }
      
      // Navigate chips with arrow keys
      if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
        this.navigateChips(event)
      }
      
      // Toggle chip with Enter or Space
      if ((event.key === 'Enter' || event.key === ' ') && event.target.matches('[data-dashboard-filter-chips-target*="Chip"]')) {
        event.preventDefault()
        event.target.click()
      }
    })
  }

  // Navigate between chips with arrow keys
  navigateChips(event) {
    const chips = Array.from(this.chipTargets)
    const currentIndex = chips.indexOf(event.target)
    
    if (currentIndex === -1) return
    
    let nextIndex
    if (event.key === 'ArrowLeft') {
      nextIndex = currentIndex === 0 ? chips.length - 1 : currentIndex - 1
    } else {
      nextIndex = currentIndex === chips.length - 1 ? 0 : currentIndex + 1
    }
    
    chips[nextIndex].focus()
    event.preventDefault()
  }
  
  // Show indicator when filters are restored from persistence (Task 3.8)
  showRestoredIndicator() {
    const filterCount = this.getActiveFilterCount()
    const summary = this.stateManager.getFilterSummary()
    
    // Create a subtle indicator
    const indicator = document.createElement('div')
    indicator.className = 'inline-flex items-center px-2 py-1 bg-teal-50 text-teal-700 text-xs rounded-full ml-2'
    indicator.innerHTML = `
      <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
      </svg>
      Filtros restaurados
    `
    indicator.title = summary
    
    // Add to filter container if it exists
    const filterContainer = this.element.querySelector('.filter-chips-container')
    if (filterContainer) {
      filterContainer.appendChild(indicator)
      
      // Fade out after 3 seconds
      setTimeout(() => {
        indicator.style.transition = 'opacity 0.3s ease-out'
        indicator.style.opacity = '0'
        setTimeout(() => indicator.remove(), 300)
      }, 3000)
    }
  }
}