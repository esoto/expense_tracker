import { Controller } from "@hotwired/stimulus"

/**
 * Virtual Scroll Controller
 * Implements virtual scrolling for large expense lists using Intersection Observer
 * Efficiently handles 1000+ expenses by only rendering visible items
 */
export default class extends Controller {
  static targets = [
    "container",
    "viewport",
    "spacer",
    "list",
    "loader",
    "scrollInfo"
  ]
  
  static values = {
    itemHeight: { type: Number, default: 60 },
    bufferSize: { type: Number, default: 5 },
    pageSize: { type: Number, default: 50 },
    totalItems: { type: Number, default: 0 },
    currentPage: { type: Number, default: 1 },
    loading: { type: Boolean, default: false },
    enabled: { type: Boolean, default: true },
    threshold: { type: Number, default: 500 }
  }
  
  connect() {
    // Check if virtual scrolling should be enabled
    this.checkIfVirtualScrollingNeeded()
    
    if (!this.enabledValue) {
      return
    }
    
    this.items = []
    this.visibleRange = { start: 0, end: 0 }
    this.scrollTop = 0
    this.containerHeight = 0
    
    // Initialize virtual scrolling
    this.initializeVirtualScroll()
    
    // Set up intersection observer for infinite scroll
    this.setupIntersectionObserver()
    
    // Set up scroll listener
    this.setupScrollListener()
    
    // Set up resize observer
    this.setupResizeObserver()
    
    // Initial render
    this.updateVisibleItems()
  }
  
  disconnect() {
    // Clean up observers
    if (this.intersectionObserver) {
      this.intersectionObserver.disconnect()
    }
    
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
    }
    
    // Remove scroll listener
    if (this.scrollHandler) {
      this.viewportTarget?.removeEventListener('scroll', this.scrollHandler)
    }
  }
  
  /**
   * Check if virtual scrolling should be enabled
   */
  checkIfVirtualScrollingNeeded() {
    const rows = this.element.querySelectorAll('tbody tr')
    this.totalItemsValue = rows.length
    
    // Only enable virtual scrolling for large datasets
    if (this.totalItemsValue < this.thresholdValue) {
      this.enabledValue = false
      return
    }
    
    // Store initial items
    this.items = Array.from(rows).map((row, index) => ({
      id: row.dataset.expenseId || index,
      element: row.cloneNode(true),
      height: this.itemHeightValue,
      index: index
    }))
  }
  
  /**
   * Initialize virtual scrolling setup
   */
  initializeVirtualScroll() {
    if (!this.hasViewportTarget) return
    
    // Set viewport styles
    this.viewportTarget.style.position = 'relative'
    this.viewportTarget.style.overflow = 'auto'
    this.viewportTarget.style.height = '600px' // Fixed height for scrolling
    
    // Create spacer for total height
    if (!this.hasSpacerTarget) {
      const spacer = document.createElement('div')
      spacer.setAttribute('data-virtual-scroll-target', 'spacer')
      spacer.style.position = 'absolute'
      spacer.style.top = '0'
      spacer.style.left = '0'
      spacer.style.width = '1px'
      spacer.style.pointerEvents = 'none'
      this.viewportTarget.appendChild(spacer)
      this.spacerTarget = spacer
    }
    
    // Update spacer height
    this.updateSpacerHeight()
    
    // Create list container for visible items
    if (!this.hasListTarget) {
      const list = document.createElement('div')
      list.setAttribute('data-virtual-scroll-target', 'list')
      list.style.position = 'relative'
      this.viewportTarget.appendChild(list)
      this.listTarget = list
    }
  }
  
  /**
   * Set up intersection observer for infinite scroll
   */
  setupIntersectionObserver() {
    if (!this.hasLoaderTarget) {
      // Create loader element
      const loader = document.createElement('div')
      loader.setAttribute('data-virtual-scroll-target', 'loader')
      loader.className = 'flex justify-center p-4'
      loader.innerHTML = `
        <div class="text-slate-600">
          <svg class="animate-spin h-5 w-5 text-teal-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
        </div>
      `
      loader.style.display = 'none'
      this.viewportTarget.appendChild(loader)
      this.loaderTarget = loader
    }
    
    // Set up intersection observer
    const options = {
      root: this.viewportTarget,
      rootMargin: '100px',
      threshold: 0.1
    }
    
    this.intersectionObserver = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting && !this.loadingValue) {
          this.loadMoreItems()
        }
      })
    }, options)
    
    // Observe loader
    this.intersectionObserver.observe(this.loaderTarget)
  }
  
  /**
   * Set up scroll listener for virtual scrolling
   */
  setupScrollListener() {
    this.scrollHandler = this.throttle(() => {
      this.handleScroll()
    }, 16) // ~60fps
    
    this.viewportTarget.addEventListener('scroll', this.scrollHandler, { passive: true })
  }
  
  /**
   * Set up resize observer
   */
  setupResizeObserver() {
    this.resizeObserver = new ResizeObserver(() => {
      this.handleResize()
    })
    
    this.resizeObserver.observe(this.viewportTarget)
  }
  
  /**
   * Handle scroll events
   */
  handleScroll() {
    this.scrollTop = this.viewportTarget.scrollTop
    this.updateVisibleItems()
    
    // Update scroll info if present
    if (this.hasScrollInfoTarget) {
      const scrollPercentage = Math.round((this.scrollTop / this.getScrollHeight()) * 100)
      this.scrollInfoTarget.textContent = `${this.visibleRange.start + 1}-${this.visibleRange.end} de ${this.totalItemsValue} (${scrollPercentage}%)`
    }
  }
  
  /**
   * Handle resize events
   */
  handleResize() {
    this.containerHeight = this.viewportTarget.clientHeight
    this.updateVisibleItems()
  }
  
  /**
   * Update visible items based on scroll position
   */
  updateVisibleItems() {
    if (!this.items.length) return
    
    const scrollTop = this.scrollTop || 0
    const containerHeight = this.containerHeight || this.viewportTarget.clientHeight
    
    // Calculate visible range with buffer
    const startIndex = Math.max(0, Math.floor(scrollTop / this.itemHeightValue) - this.bufferSizeValue)
    const endIndex = Math.min(
      this.items.length,
      Math.ceil((scrollTop + containerHeight) / this.itemHeightValue) + this.bufferSizeValue
    )
    
    // Check if range has changed
    if (startIndex === this.visibleRange.start && endIndex === this.visibleRange.end) {
      return
    }
    
    this.visibleRange = { start: startIndex, end: endIndex }
    
    // Clear current list
    this.listTarget.innerHTML = ''
    
    // Create document fragment for better performance
    const fragment = document.createDocumentFragment()
    
    // Render visible items
    for (let i = startIndex; i < endIndex; i++) {
      const item = this.items[i]
      if (!item) continue
      
      const element = item.element.cloneNode(true)
      element.style.position = 'absolute'
      element.style.top = `${i * this.itemHeightValue}px`
      element.style.left = '0'
      element.style.right = '0'
      
      // Re-attach Stimulus controllers
      this.reattachControllers(element)
      
      fragment.appendChild(element)
    }
    
    // Append all at once
    this.listTarget.appendChild(fragment)
    
    // Dispatch event for other controllers
    this.dispatch('itemsRendered', {
      detail: {
        startIndex,
        endIndex,
        totalItems: this.items.length
      }
    })
  }
  
  /**
   * Load more items (for infinite scroll)
   */
  async loadMoreItems() {
    if (this.loadingValue || !this.hasMoreItems()) return
    
    this.loadingValue = true
    this.loaderTarget.style.display = 'block'
    
    try {
      // Build URL with current filters and next page
      const params = new URLSearchParams(window.location.search)
      params.set('page', this.currentPageValue + 1)
      params.set('per_page', this.pageSizeValue)
      
      const response = await fetch(`/expenses?${params.toString()}`, {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (!response.ok) throw new Error('Failed to load more items')
      
      const data = await response.json()
      
      if (data.data && data.data.length > 0) {
        // Add new items to the list
        this.addNewItems(data.data)
        this.currentPageValue++
        
        // Update total items count
        if (data.meta && data.meta.total) {
          this.totalItemsValue = data.meta.total
        }
      }
    } catch (error) {
      console.error('Error loading more items:', error)
      this.showError('Error al cargar más gastos')
    } finally {
      this.loadingValue = false
      this.loaderTarget.style.display = 'none'
    }
  }
  
  /**
   * Add new items to the virtual list
   */
  addNewItems(newItems) {
    newItems.forEach(itemData => {
      const row = this.createRowElement(itemData)
      this.items.push({
        id: itemData.id,
        element: row,
        height: this.itemHeightValue,
        index: this.items.length
      })
    })
    
    // Update spacer height
    this.updateSpacerHeight()
    
    // Re-render if needed
    this.updateVisibleItems()
  }
  
  /**
   * Create row element from data
   */
  createRowElement(data) {
    const row = document.createElement('tr')
    row.dataset.expenseId = data.id
    row.className = 'hover:bg-slate-50 transition-colors'
    
    // Build row HTML (simplified version)
    row.innerHTML = `
      <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-900">
        ${this.formatDate(data.transaction_date)}
      </td>
      <td class="px-6 py-4 text-sm text-slate-900">
        ${data.merchant_name || 'Sin comercio'}
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm">
        ${data.category ? `
          <span class="px-2 py-1 text-xs rounded-full bg-${data.category.color}-100 text-${data.category.color}-800">
            ${data.category.name}
          </span>
        ` : '<span class="text-slate-500">Sin categoría</span>'}
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-slate-900">
        ${data.currency === 'USD' ? '$' : '₡'}${this.formatAmount(data.amount)}
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-600">
        ${data.bank_name || '-'}
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm">
        <span class="px-2 py-1 text-xs rounded-full bg-${this.getStatusColor(data.status)}-100 text-${this.getStatusColor(data.status)}-800">
          ${this.getStatusLabel(data.status)}
        </span>
      </td>
    `
    
    return row
  }
  
  /**
   * Re-attach Stimulus controllers to cloned elements
   */
  reattachControllers(element) {
    // Find all elements with data-controller attribute
    const controllerElements = element.querySelectorAll('[data-controller]')
    controllerElements.forEach(el => {
      // Trigger Stimulus to reconnect
      const event = new CustomEvent('turbo:load', { bubbles: true })
      el.dispatchEvent(event)
    })
  }
  
  /**
   * Update spacer height based on total items
   */
  updateSpacerHeight() {
    if (this.hasSpacerTarget) {
      const totalHeight = this.items.length * this.itemHeightValue
      this.spacerTarget.style.height = `${totalHeight}px`
    }
  }
  
  /**
   * Get total scroll height
   */
  getScrollHeight() {
    return this.items.length * this.itemHeightValue
  }
  
  /**
   * Check if there are more items to load
   */
  hasMoreItems() {
    return this.items.length < this.totalItemsValue
  }
  
  /**
   * Show error message
   */
  showError(message) {
    const toast = document.createElement('div')
    toast.className = 'fixed bottom-4 right-4 bg-rose-100 border border-rose-200 text-rose-700 px-4 py-3 rounded-lg shadow-lg'
    toast.textContent = message
    document.body.appendChild(toast)
    
    setTimeout(() => {
      toast.remove()
    }, 3000)
  }
  
  /**
   * Throttle function for performance
   */
  throttle(func, wait) {
    let timeout
    let lastTime = 0
    
    return function executedFunction(...args) {
      const now = Date.now()
      
      if (now - lastTime >= wait) {
        func(...args)
        lastTime = now
      } else {
        clearTimeout(timeout)
        timeout = setTimeout(() => {
          func(...args)
          lastTime = Date.now()
        }, wait - (now - lastTime))
      }
    }
  }
  
  /**
   * Format date
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
   * Format amount
   */
  formatAmount(amount) {
    return parseFloat(amount).toLocaleString('es-CR')
  }
  
  /**
   * Get status color
   */
  getStatusColor(status) {
    const colors = {
      'pending': 'amber',
      'processed': 'emerald',
      'failed': 'rose',
      'duplicate': 'slate'
    }
    return colors[status] || 'slate'
  }
  
  /**
   * Get status label
   */
  getStatusLabel(status) {
    const labels = {
      'pending': 'Pendiente',
      'processed': 'Procesado',
      'failed': 'Fallido',
      'duplicate': 'Duplicado'
    }
    return labels[status] || status
  }
}