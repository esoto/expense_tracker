import { Controller } from "@hotwired/stimulus"

/**
 * Filter Chips Controller
 * Displays active filters as visual chips that can be removed with a click
 * Integrates with ExpenseFilterService to show and manage filter state
 */
export default class extends Controller {
  static targets = [
    "container",
    "chip",
    "clearAll"
  ]
  
  static values = {
    filters: { type: Object, default: {} },
    baseUrl: { type: String, default: "/expenses" }
  }
  
  connect() {
    this.parseCurrentFilters()
    this.renderChips()
  }
  
  /**
   * Parse filters from URL parameters
   */
  parseCurrentFilters() {
    const params = new URLSearchParams(window.location.search)
    const filters = {}
    
    // Date range filters
    if (params.get('start_date') && params.get('end_date')) {
      filters.dateRange = {
        type: 'date_range',
        label: `${this.formatDate(params.get('start_date'))} - ${this.formatDate(params.get('end_date'))}`,
        params: { start_date: params.get('start_date'), end_date: params.get('end_date') }
      }
    } else if (params.get('period')) {
      const periodLabels = {
        'day': 'Hoy',
        'week': 'Esta semana',
        'month': 'Este mes',
        'year': 'Este año'
      }
      filters.period = {
        type: 'period',
        label: periodLabels[params.get('period')] || params.get('period'),
        params: { period: params.get('period') }
      }
    }
    
    // Category filter
    if (params.get('category')) {
      filters.category = {
        type: 'category',
        label: `Categoría: ${params.get('category')}`,
        params: { category: params.get('category') }
      }
    }
    
    // Bank filter
    if (params.get('bank')) {
      filters.bank = {
        type: 'bank',
        label: `Banco: ${params.get('bank')}`,
        params: { bank: params.get('bank') }
      }
    }
    
    // Status filter
    if (params.get('status')) {
      const statusLabels = {
        'pending': 'Pendiente',
        'processed': 'Procesado',
        'failed': 'Fallido',
        'duplicate': 'Duplicado',
        'uncategorized': 'Sin categoría'
      }
      filters.status = {
        type: 'status',
        label: statusLabels[params.get('status')] || params.get('status'),
        params: { status: params.get('status') }
      }
    }
    
    // Amount range filter
    if (params.get('min_amount') || params.get('max_amount')) {
      const min = params.get('min_amount')
      const max = params.get('max_amount')
      let label = 'Monto: '
      
      if (min && max) {
        label += `₡${this.formatNumber(min)} - ₡${this.formatNumber(max)}`
      } else if (min) {
        label += `> ₡${this.formatNumber(min)}`
      } else {
        label += `< ₡${this.formatNumber(max)}`
      }
      
      filters.amount = {
        type: 'amount',
        label: label,
        params: { min_amount: min, max_amount: max }
      }
    }
    
    // Search query
    if (params.get('search_query')) {
      filters.search = {
        type: 'search',
        label: `Búsqueda: "${params.get('search_query')}"`,
        params: { search_query: params.get('search_query') }
      }
    }
    
    this.filtersValue = filters
  }
  
  /**
   * Render filter chips
   */
  renderChips() {
    if (!this.hasContainerTarget) return
    
    const filterCount = Object.keys(this.filtersValue).length
    
    if (filterCount === 0) {
      this.containerTarget.classList.add('hidden')
      return
    }
    
    this.containerTarget.classList.remove('hidden')
    this.containerTarget.innerHTML = ''
    
    // Create chips container
    const chipsWrapper = document.createElement('div')
    chipsWrapper.className = 'flex flex-wrap items-center gap-2'
    
    // Add label
    const label = document.createElement('span')
    label.className = 'text-sm font-medium text-slate-600'
    label.textContent = 'Filtros activos:'
    chipsWrapper.appendChild(label)
    
    // Add filter chips
    Object.entries(this.filtersValue).forEach(([key, filter]) => {
      const chip = this.createChip(key, filter)
      chipsWrapper.appendChild(chip)
    })
    
    // Add clear all button if multiple filters
    if (filterCount > 1) {
      const clearAllBtn = document.createElement('button')
      clearAllBtn.className = 'text-sm text-rose-600 hover:text-rose-700 font-medium ml-2'
      clearAllBtn.textContent = 'Limpiar todos'
      clearAllBtn.setAttribute('data-action', 'click->filter-chips#clearAllFilters')
      clearAllBtn.setAttribute('data-filter-chips-target', 'clearAll')
      chipsWrapper.appendChild(clearAllBtn)
    }
    
    this.containerTarget.appendChild(chipsWrapper)
  }
  
  /**
   * Create individual filter chip
   */
  createChip(key, filter) {
    const chip = document.createElement('div')
    chip.className = 'inline-flex items-center gap-1 px-3 py-1 bg-teal-100 text-teal-800 rounded-full text-sm font-medium'
    chip.setAttribute('data-filter-chips-target', 'chip')
    chip.setAttribute('data-filter-key', key)
    
    // Add label
    const label = document.createElement('span')
    label.textContent = filter.label
    chip.appendChild(label)
    
    // Add remove button
    const removeBtn = document.createElement('button')
    removeBtn.className = 'ml-1 hover:text-teal-900 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500 rounded-full'
    removeBtn.setAttribute('aria-label', `Remover filtro: ${filter.label}`)
    removeBtn.setAttribute('data-action', 'click->filter-chips#removeFilter')
    removeBtn.setAttribute('data-filter-key', key)
    
    removeBtn.innerHTML = `
      <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
        <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"></path>
      </svg>
    `
    
    chip.appendChild(removeBtn)
    
    return chip
  }
  
  /**
   * Remove individual filter
   */
  removeFilter(event) {
    event.preventDefault()
    const filterKey = event.currentTarget.getAttribute('data-filter-key')
    
    // Build new URL without this filter
    const params = new URLSearchParams(window.location.search)
    const filter = this.filtersValue[filterKey]
    
    if (filter && filter.params) {
      Object.keys(filter.params).forEach(param => {
        params.delete(param)
      })
    }
    
    // Redirect to new URL
    this.navigateWithFilters(params)
  }
  
  /**
   * Clear all filters
   */
  clearAllFilters(event) {
    event.preventDefault()
    
    // Navigate to base URL without filters
    window.location.href = this.baseUrlValue
  }
  
  /**
   * Navigate with updated filters
   */
  navigateWithFilters(params) {
    const url = params.toString() ? `${this.baseUrlValue}?${params.toString()}` : this.baseUrlValue
    window.location.href = url
  }
  
  /**
   * Format date for display
   */
  formatDate(dateString) {
    try {
      const date = new Date(dateString)
      return date.toLocaleDateString('es-CR', { 
        day: '2-digit', 
        month: '2-digit', 
        year: 'numeric' 
      })
    } catch {
      return dateString
    }
  }
  
  /**
   * Format number with thousands separator
   */
  formatNumber(num) {
    return parseFloat(num).toLocaleString('es-CR')
  }
}