import { Controller } from "@hotwired/stimulus"
import FilterStateManager from "utilities/filter_state_manager"

// Dashboard Virtual Scroll Controller for Epic 3 Task 3.7
// Implements high-performance virtual scrolling for large expense datasets
// Uses Intersection Observer API for efficient viewport detection and DOM recycling
// Enhanced with Task 3.8: Scroll position persistence
export default class extends Controller {
  static targets = [
    "viewport",        // The scrollable container
    "scrollContent",   // The content that creates scroll height
    "itemContainer",   // Container for rendered items
    "loadingTop",      // Top loading indicator
    "loadingBottom",   // Bottom loading indicator
    "scrollPosition"   // Scroll position indicator
  ]
  
  static values = {
    totalItems: { type: Number, default: 0 },
    itemHeight: { type: Number, default: 72 },    // Default height for compact view
    expandedHeight: { type: Number, default: 96 }, // Height for expanded view
    visibleItems: { type: Number, default: 15 },   // Number of items to render
    bufferSize: { type: Number, default: 5 },      // Extra items to render outside viewport
    currentPage: { type: Number, default: 1 },
    hasMore: { type: Boolean, default: true },
    isLoading: { type: Boolean, default: false },
    viewMode: { type: String, default: "compact" },
    scrollPosition: { type: Number, default: 0 },
    lastCursor: { type: String, default: "" },
    activeFilters: { type: Object, default: {} }
  }
  
  // Performance optimization constants
  static SCROLL_DEBOUNCE_MS = 16  // 60fps target
  static LOAD_THRESHOLD = 0.8     // Load more when 80% scrolled
  static MIN_LOAD_DELAY = 300     // Minimum delay between loads
  static RECYCLE_POOL_SIZE = 30   // Number of DOM nodes to keep in pool
  
  connect() {
    // Initialize filter state manager for scroll persistence (Task 3.8)
    this.stateManager = new FilterStateManager()
    
    this.initializeVirtualScroll()
    this.setupIntersectionObserver()
    this.setupScrollListener()
    this.setupResizeObserver()
    this.createNodePool()
    this.loadInitialData()
    
    // Register with dashboard expenses controller
    this.registerWithDashboard()
    
    // Restore scroll position from persistence (Task 3.8)
    this.restoreScrollPosition()
    
    // Log initialization in development
    if (this.element.dataset.environment === "development") {
      console.log("Virtual Scroll initialized:", {
        totalItems: this.totalItemsValue,
        visibleItems: this.visibleItemsValue,
        itemHeight: this.itemHeightValue,
        viewMode: this.viewModeValue,
        restoredScrollPos: this.stateManager.state.scroll_position
      })
    }
  }
  
  disconnect() {
    // Clean up observers and listeners
    if (this.intersectionObserver) {
      this.intersectionObserver.disconnect()
    }
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
    }
    if (this.scrollRAF) {
      cancelAnimationFrame(this.scrollRAF)
    }
    
    // Clean up node pool
    this.cleanupNodePool()
    
    // Unregister from dashboard
    this.unregisterFromDashboard()
  }
  
  // Initialize virtual scrolling system
  initializeVirtualScroll() {
    // Calculate dimensions based on viewport
    this.calculateDimensions()
    
    // Set up virtual space
    this.setupVirtualSpace()
    
    // Initialize scroll state
    this.scrollState = {
      position: 0,
      direction: 'down',
      velocity: 0,
      lastTime: Date.now(),
      momentum: false
    }
    
    // Initialize render state
    this.renderState = {
      startIndex: 0,
      endIndex: this.visibleItemsValue + this.bufferSizeValue,
      renderedItems: new Map(),
      pendingUpdates: []
    }
    
    // Initialize load state
    this.loadState = {
      lastLoadTime: 0,
      loadQueue: [],
      retryCount: 0,
      cursor: null
    }
  }
  
  // Calculate dimensions based on viewport and view mode
  calculateDimensions() {
    const viewportHeight = this.viewportTarget.clientHeight
    const itemHeight = this.viewModeValue === "expanded" ? 
                      this.expandedHeightValue : 
                      this.itemHeightValue
    
    // Calculate visible items based on viewport
    this.visibleItemsValue = Math.ceil(viewportHeight / itemHeight) + 1
    
    // Update dimensions
    this.dimensions = {
      viewportHeight,
      itemHeight,
      totalHeight: this.totalItemsValue * itemHeight,
      visibleItems: this.visibleItemsValue,
      bufferItems: this.bufferSizeValue
    }
  }
  
  // Set up virtual scrolling space
  setupVirtualSpace() {
    // Set content height to enable scrolling
    if (this.hasScrollContentTarget) {
      this.scrollContentTarget.style.height = `${this.dimensions.totalHeight}px`
      this.scrollContentTarget.style.position = 'relative'
    }
    
    // Configure item container
    if (this.hasItemContainerTarget) {
      this.itemContainerTarget.style.position = 'relative'
      this.itemContainerTarget.style.height = '100%'
    }
  }
  
  // Set up Intersection Observer for viewport detection
  setupIntersectionObserver() {
    const options = {
      root: this.viewportTarget,
      rootMargin: `${this.dimensions.itemHeight * 2}px 0px`,
      threshold: [0, 0.1, 0.5, 0.9, 1.0]
    }
    
    this.intersectionObserver = new IntersectionObserver((entries) => {
      this.handleIntersections(entries)
    }, options)
    
    // Observe sentinel elements for infinite loading
    this.createSentinels()
  }
  
  // Create sentinel elements for infinite loading triggers
  createSentinels() {
    // Top sentinel for upward scrolling
    this.topSentinel = document.createElement('div')
    this.topSentinel.className = 'virtual-scroll-sentinel top'
    this.topSentinel.style.height = '1px'
    this.topSentinel.style.position = 'absolute'
    this.topSentinel.style.top = '0'
    this.topSentinel.dataset.sentinel = 'top'
    
    // Bottom sentinel for downward scrolling
    this.bottomSentinel = document.createElement('div')
    this.bottomSentinel.className = 'virtual-scroll-sentinel bottom'
    this.bottomSentinel.style.height = '1px'
    this.bottomSentinel.style.position = 'absolute'
    this.bottomSentinel.style.bottom = '0'
    this.bottomSentinel.dataset.sentinel = 'bottom'
    
    if (this.hasScrollContentTarget) {
      this.scrollContentTarget.appendChild(this.topSentinel)
      this.scrollContentTarget.appendChild(this.bottomSentinel)
      
      // Start observing sentinels
      this.intersectionObserver.observe(this.topSentinel)
      this.intersectionObserver.observe(this.bottomSentinel)
    }
  }
  
  // Handle intersection observations
  handleIntersections(entries) {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        const sentinel = entry.target.dataset.sentinel
        
        if (sentinel === 'bottom' && this.hasMoreValue && !this.isLoadingValue) {
          // Load more items when bottom sentinel is visible
          this.loadMoreItems()
        } else if (sentinel === 'top' && this.renderState.startIndex > 0) {
          // Consider loading previous items if scrolling up
          this.considerPreviousItems()
        }
      }
    })
  }
  
  // Set up scroll listener with throttling
  setupScrollListener() {
    this.scrollHandler = this.throttle(() => {
      this.handleScroll()
    }, DashboardVirtualScrollController.SCROLL_DEBOUNCE_MS)
    
    if (this.hasViewportTarget) {
      this.viewportTarget.addEventListener('scroll', this.scrollHandler, { passive: true })
    }
  }
  
  // Handle scroll events
  handleScroll() {
    if (!this.hasViewportTarget) return
    
    const scrollTop = this.viewportTarget.scrollTop
    const scrollHeight = this.viewportTarget.scrollHeight
    const clientHeight = this.viewportTarget.clientHeight
    
    // Update scroll state
    const currentTime = Date.now()
    const timeDelta = currentTime - this.scrollState.lastTime
    const scrollDelta = scrollTop - this.scrollState.position
    
    this.scrollState.velocity = timeDelta > 0 ? scrollDelta / timeDelta : 0
    this.scrollState.direction = scrollDelta > 0 ? 'down' : 'up'
    this.scrollState.position = scrollTop
    this.scrollState.lastTime = currentTime
    
    // Calculate visible range
    const startIndex = Math.floor(scrollTop / this.dimensions.itemHeight)
    const endIndex = Math.ceil((scrollTop + clientHeight) / this.dimensions.itemHeight)
    
    // Update render range with buffer
    this.updateRenderRange(startIndex, endIndex)
    
    // Check if we need to load more data
    const scrollPercentage = (scrollTop + clientHeight) / scrollHeight
    if (scrollPercentage > DashboardVirtualScrollController.LOAD_THRESHOLD && 
        this.hasMoreValue && 
        !this.isLoadingValue) {
      this.loadMoreItems()
    }
    
    // Update scroll position indicator
    this.updateScrollIndicator(scrollPercentage)
    
    // Persist scroll position (Task 3.8) - debounced
    this.persistScrollPosition(scrollTop)
  }
  
  // Update the range of items to render
  updateRenderRange(startIndex, endIndex) {
    // Add buffer items
    const bufferedStart = Math.max(0, startIndex - this.bufferSizeValue)
    const bufferedEnd = Math.min(this.totalItemsValue, endIndex + this.bufferSizeValue)
    
    // Check if range has changed significantly
    if (Math.abs(bufferedStart - this.renderState.startIndex) > 2 ||
        Math.abs(bufferedEnd - this.renderState.endIndex) > 2) {
      
      // Schedule render update
      this.scheduleRenderUpdate(bufferedStart, bufferedEnd)
    }
  }
  
  // Schedule a render update using requestAnimationFrame
  scheduleRenderUpdate(startIndex, endIndex) {
    // Cancel any pending render
    if (this.renderRAF) {
      cancelAnimationFrame(this.renderRAF)
    }
    
    this.renderRAF = requestAnimationFrame(() => {
      this.renderItems(startIndex, endIndex)
    })
  }
  
  // Render visible items
  renderItems(startIndex, endIndex) {
    const fragment = document.createDocumentFragment()
    const itemsToRender = []
    
    // Collect items that need rendering
    for (let i = startIndex; i < endIndex; i++) {
      if (!this.renderState.renderedItems.has(i)) {
        const item = this.getItemData(i)
        if (item) {
          itemsToRender.push({ index: i, data: item })
        }
      }
    }
    
    // Render new items using node pool
    itemsToRender.forEach(({ index, data }) => {
      const node = this.getNodeFromPool()
      this.populateNode(node, data, index)
      fragment.appendChild(node)
      this.renderState.renderedItems.set(index, node)
    })
    
    // Remove items outside render range
    this.cleanupOutOfRangeItems(startIndex, endIndex)
    
    // Append new items to container
    if (fragment.childNodes.length > 0) {
      this.itemContainerTarget.appendChild(fragment)
    }
    
    // Update render state
    this.renderState.startIndex = startIndex
    this.renderState.endIndex = endIndex
    
    // Trigger rendered event
    this.dispatch("rendered", {
      detail: {
        startIndex,
        endIndex,
        itemCount: endIndex - startIndex
      }
    })
  }
  
  // Create a pool of reusable DOM nodes
  createNodePool() {
    this.nodePool = []
    this.nodePoolSize = DashboardVirtualScrollController.RECYCLE_POOL_SIZE
    
    // Pre-create nodes for recycling
    for (let i = 0; i < this.nodePoolSize; i++) {
      const node = this.createExpenseNode()
      this.nodePool.push(node)
    }
  }
  
  // Get a node from the pool or create a new one
  getNodeFromPool() {
    if (this.nodePool.length > 0) {
      return this.nodePool.pop()
    }
    return this.createExpenseNode()
  }
  
  // Return a node to the pool for reuse
  returnNodeToPool(node) {
    if (this.nodePool.length < this.nodePoolSize) {
      // Reset node state
      this.resetNode(node)
      this.nodePool.push(node)
    }
  }
  
  // Create a new expense node
  createExpenseNode() {
    const node = document.createElement('div')
    node.className = 'virtual-expense-item'
    node.style.position = 'absolute'
    node.style.width = '100%'
    node.style.height = `${this.dimensions.itemHeight}px`
    node.dataset.virtual = 'true'
    
    // Create inner structure matching existing expense rows
    node.innerHTML = `
      <div class="dashboard-expense-row group" tabindex="0" role="article">
        <div class="hidden absolute left-3 top-1/2 -translate-y-1/2" data-selection-container>
          <input type="checkbox" class="rounded border-slate-300 text-teal-600 focus:ring-teal-500">
        </div>
        <div class="flex items-center space-x-4 flex-1">
          <div class="flex-shrink-0">
            <div class="expense-category-badge">?</div>
          </div>
          <div class="expense-details flex-1">
            <p class="expense-merchant">Loading...</p>
            <p class="expense-metadata">
              <span class="date"></span>
              <span>•</span>
              <span class="category"></span>
              <span>•</span>
              <span class="bank"></span>
            </p>
            <div class="expense-expanded-details hidden"></div>
          </div>
        </div>
        <div class="flex items-center space-x-3">
          <div class="text-right">
            <p class="expense-amount"></p>
            <p class="expense-date"></p>
          </div>
          <div class="inline-quick-actions opacity-0"></div>
        </div>
      </div>
    `
    
    return node
  }
  
  // Populate a node with expense data
  populateNode(node, expense, index) {
    // Position the node
    node.style.transform = `translateY(${index * this.dimensions.itemHeight}px)`
    node.dataset.index = index
    node.dataset.expenseId = expense.id
    
    const row = node.querySelector('.dashboard-expense-row')
    row.dataset.expenseId = expense.id
    row.dataset.expenseStatus = expense.status
    
    // Update category badge
    const badge = node.querySelector('.expense-category-badge')
    if (expense.category) {
      badge.style.backgroundColor = expense.category.color
      badge.textContent = expense.category.name.charAt(0)
      badge.title = expense.category.name
      badge.classList.remove('uncategorized')
    } else {
      badge.style.backgroundColor = ''
      badge.textContent = '?'
      badge.title = 'Sin categoría'
      badge.classList.add('uncategorized')
    }
    
    // Update expense details
    node.querySelector('.expense-merchant').textContent = expense.merchant_name || 'Comercio desconocido'
    node.querySelector('.expense-metadata .date').textContent = this.formatDate(expense.transaction_date)
    node.querySelector('.expense-metadata .category').textContent = expense.category?.name || 'Sin categoría'
    node.querySelector('.expense-metadata .bank').textContent = expense.bank_name
    
    // Update amount
    node.querySelector('.expense-amount').textContent = this.formatCurrency(expense.amount, expense.currency)
    node.querySelector('.expense-date').textContent = this.formatDateTime(expense.created_at)
    
    // Handle expanded view details
    if (this.viewModeValue === 'expanded') {
      const expandedDetails = node.querySelector('.expense-expanded-details')
      expandedDetails.classList.remove('hidden')
      if (expense.description) {
        expandedDetails.innerHTML = `
          <p class="text-xs text-slate-600 line-clamp-2">${expense.description}</p>
        `
      }
    }
    
    // Set up inline actions
    this.setupInlineActions(node, expense)
    
    // Set up selection if in selection mode
    if (this.isSelectionMode()) {
      this.setupSelection(node, expense)
    }
  }
  
  // Reset a node for reuse
  resetNode(node) {
    node.dataset.index = ''
    node.dataset.expenseId = ''
    node.style.transform = ''
    
    // Reset content to loading state
    const badge = node.querySelector('.expense-category-badge')
    badge.style.backgroundColor = ''
    badge.textContent = '?'
    badge.className = 'expense-category-badge uncategorized'
    
    node.querySelector('.expense-merchant').textContent = 'Loading...'
    node.querySelector('.expense-metadata .date').textContent = ''
    node.querySelector('.expense-metadata .category').textContent = ''
    node.querySelector('.expense-metadata .bank').textContent = ''
    node.querySelector('.expense-amount').textContent = ''
    node.querySelector('.expense-date').textContent = ''
    
    // Hide expanded details
    node.querySelector('.expense-expanded-details').classList.add('hidden')
    
    // Clear inline actions
    node.querySelector('.inline-quick-actions').innerHTML = ''
  }
  
  // Clean up items outside the render range
  cleanupOutOfRangeItems(startIndex, endIndex) {
    const itemsToRemove = []
    
    this.renderState.renderedItems.forEach((node, index) => {
      if (index < startIndex - this.bufferSizeValue || 
          index > endIndex + this.bufferSizeValue) {
        itemsToRemove.push(index)
      }
    })
    
    itemsToRemove.forEach(index => {
      const node = this.renderState.renderedItems.get(index)
      if (node && node.parentNode) {
        node.parentNode.removeChild(node)
        this.returnNodeToPool(node)
      }
      this.renderState.renderedItems.delete(index)
    })
  }
  
  // Load initial data
  async loadInitialData() {
    if (this.isLoadingValue) return
    
    this.isLoadingValue = true
    this.showLoadingIndicator()
    
    try {
      const response = await this.fetchExpenses({
        page: 1,
        per_page: this.visibleItemsValue * 2,
        ...this.activeFiltersValue
      })
      
      if (response.success) {
        this.processLoadedData(response.data, true)
      }
    } catch (error) {
      console.error("Error loading initial data:", error)
      this.showError("Error al cargar gastos")
    } finally {
      this.isLoadingValue = false
      this.hideLoadingIndicator()
    }
  }
  
  // Load more items for infinite scrolling
  async loadMoreItems() {
    if (this.isLoadingValue || !this.hasMoreValue) return
    
    // Check minimum delay between loads
    const now = Date.now()
    if (now - this.loadState.lastLoadTime < DashboardVirtualScrollController.MIN_LOAD_DELAY) {
      return
    }
    
    this.isLoadingValue = true
    this.loadState.lastLoadTime = now
    this.showLoadingIndicator('bottom')
    
    try {
      const params = {
        cursor: this.lastCursorValue,
        per_page: this.visibleItemsValue * 2,
        ...this.activeFiltersValue
      }
      
      const response = await this.fetchExpenses(params)
      
      if (response.success) {
        this.processLoadedData(response.data, false)
      }
    } catch (error) {
      console.error("Error loading more items:", error)
      this.handleLoadError(error)
    } finally {
      this.isLoadingValue = false
      this.hideLoadingIndicator('bottom')
    }
  }
  
  // Fetch expenses from the server
  async fetchExpenses(params) {
    const url = new URL('/expenses/virtual_scroll', window.location.origin)
    Object.keys(params).forEach(key => {
      if (params[key] !== undefined && params[key] !== null) {
        url.searchParams.append(key, params[key])
      }
    })
    
    const response = await fetch(url, {
      headers: {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`)
    }
    
    const data = await response.json()
    return {
      success: true,
      data: data
    }
  }
  
  // Process loaded data
  processLoadedData(data, isInitial) {
    // Store expense data
    if (!this.expenseData) {
      this.expenseData = new Map()
    }
    
    // Add new expenses to data store
    const startIndex = isInitial ? 0 : this.expenseData.size
    data.expenses.forEach((expense, index) => {
      this.expenseData.set(startIndex + index, expense)
    })
    
    // Update state
    this.totalItemsValue = isInitial ? data.total_count : this.expenseData.size
    this.hasMoreValue = data.has_more
    this.lastCursorValue = data.next_cursor
    
    // Update virtual space
    this.setupVirtualSpace()
    
    // Render visible items
    const scrollTop = this.viewportTarget.scrollTop
    const startRenderIndex = Math.floor(scrollTop / this.dimensions.itemHeight)
    const endRenderIndex = Math.ceil((scrollTop + this.dimensions.viewportHeight) / this.dimensions.itemHeight)
    
    this.renderItems(startRenderIndex, endRenderIndex)
    
    // Dispatch loaded event
    this.dispatch("loaded", {
      detail: {
        itemsLoaded: data.expenses.length,
        totalItems: this.totalItemsValue,
        hasMore: this.hasMoreValue
      }
    })
  }
  
  // Get item data by index
  getItemData(index) {
    return this.expenseData ? this.expenseData.get(index) : null
  }
  
  // Set up resize observer
  setupResizeObserver() {
    this.resizeObserver = new ResizeObserver(() => {
      this.handleResize()
    })
    
    if (this.hasViewportTarget) {
      this.resizeObserver.observe(this.viewportTarget)
    }
  }
  
  // Handle viewport resize
  handleResize() {
    // Recalculate dimensions
    this.calculateDimensions()
    
    // Update virtual space
    this.setupVirtualSpace()
    
    // Re-render visible items
    const scrollTop = this.viewportTarget.scrollTop
    const startIndex = Math.floor(scrollTop / this.dimensions.itemHeight)
    const endIndex = Math.ceil((scrollTop + this.dimensions.viewportHeight) / this.dimensions.itemHeight)
    
    this.renderItems(startIndex, endIndex)
  }
  
  // Update view mode (called from dashboard controller)
  updateViewMode(mode) {
    if (this.viewModeValue === mode) return
    
    this.viewModeValue = mode
    
    // Recalculate dimensions for new item height
    this.calculateDimensions()
    
    // Update all rendered items
    this.renderState.renderedItems.forEach((node, index) => {
      const expense = this.getItemData(index)
      if (expense) {
        // Update node height
        node.style.height = `${this.dimensions.itemHeight}px`
        node.style.transform = `translateY(${index * this.dimensions.itemHeight}px)`
        
        // Update expanded details visibility
        const expandedDetails = node.querySelector('.expense-expanded-details')
        if (mode === 'expanded') {
          expandedDetails.classList.remove('hidden')
        } else {
          expandedDetails.classList.add('hidden')
        }
      }
    })
    
    // Update virtual space
    this.setupVirtualSpace()
  }
  
  // Apply filters and reload data
  applyFilters(filters) {
    this.activeFiltersValue = filters
    
    // Reset state
    this.expenseData = new Map()
    this.renderState.renderedItems.clear()
    this.totalItemsValue = 0
    this.lastCursorValue = ""
    this.currentPageValue = 1
    
    // Clear rendered items
    if (this.hasItemContainerTarget) {
      this.itemContainerTarget.innerHTML = ''
    }
    
    // Reload with new filters
    this.loadInitialData()
  }
  
  // Register with dashboard expenses controller
  registerWithDashboard() {
    const dashboardController = this.application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller="dashboard-expenses"]'),
      'dashboard-expenses'
    )
    
    if (dashboardController) {
      dashboardController.virtualScrollController = this
    }
  }
  
  // Unregister from dashboard
  unregisterFromDashboard() {
    const dashboardController = this.application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller="dashboard-expenses"]'),
      'dashboard-expenses'
    )
    
    if (dashboardController && dashboardController.virtualScrollController === this) {
      dashboardController.virtualScrollController = null
    }
  }
  
  // Check if selection mode is active
  isSelectionMode() {
    const dashboardController = this.application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller="dashboard-expenses"]'),
      'dashboard-expenses'
    )
    
    return dashboardController ? dashboardController.selectionModeValue : false
  }
  
  // Set up inline actions for an expense node
  setupInlineActions(node, expense) {
    const actionsContainer = node.querySelector('.inline-quick-actions')
    
    actionsContainer.innerHTML = `
      <div class="flex items-center space-x-1">
        <button type="button" class="p-1 text-slate-400 hover:text-teal-600" title="Categorizar (C)">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"></path>
          </svg>
        </button>
        <button type="button" class="p-1 ${expense.status === 'pending' ? 'text-amber-500' : 'text-emerald-500'}" title="Cambiar estado (S)">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="${expense.status === 'pending' ? 'M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z' : 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z'}"></path>
          </svg>
        </button>
        <button type="button" class="p-1 text-slate-400 hover:text-amber-600" title="Duplicar (D)">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"></path>
          </svg>
        </button>
        <button type="button" class="p-1 text-slate-400 hover:text-rose-600" title="Eliminar (Del)">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
          </svg>
        </button>
      </div>
    `
  }
  
  // Set up selection checkbox for an expense node
  setupSelection(node, expense) {
    const selectionContainer = node.querySelector('[data-selection-container]')
    if (selectionContainer) {
      selectionContainer.classList.remove('hidden')
      const checkbox = selectionContainer.querySelector('input[type="checkbox"]')
      if (checkbox) {
        checkbox.dataset.expenseId = expense.id
      }
    }
  }
  
  // Show loading indicator
  showLoadingIndicator(position = 'top') {
    if (position === 'top' && this.hasLoadingTopTarget) {
      this.loadingTopTarget.classList.remove('hidden')
    } else if (position === 'bottom' && this.hasLoadingBottomTarget) {
      this.loadingBottomTarget.classList.remove('hidden')
    }
  }
  
  // Hide loading indicator
  hideLoadingIndicator(position = 'all') {
    if ((position === 'top' || position === 'all') && this.hasLoadingTopTarget) {
      this.loadingTopTarget.classList.add('hidden')
    }
    if ((position === 'bottom' || position === 'all') && this.hasLoadingBottomTarget) {
      this.loadingBottomTarget.classList.add('hidden')
    }
  }
  
  // Update scroll position indicator
  updateScrollIndicator(percentage) {
    if (this.hasScrollPositionTarget) {
      this.scrollPositionTarget.textContent = `${Math.round(percentage * 100)}%`
      
      // Update visual indicator
      const indicator = this.scrollPositionTarget.querySelector('.indicator')
      if (indicator) {
        indicator.style.height = `${percentage * 100}%`
      }
    }
  }
  
  // Show error message
  showError(message) {
    // Dispatch error event for dashboard to handle
    this.dispatch("error", { detail: { message } })
  }
  
  // Handle load errors with retry logic
  handleLoadError(error) {
    this.loadState.retryCount++
    
    if (this.loadState.retryCount < 3) {
      // Retry with exponential backoff
      const delay = Math.pow(2, this.loadState.retryCount) * 1000
      setTimeout(() => {
        this.loadMoreItems()
      }, delay)
    } else {
      this.showError("Error al cargar más gastos. Por favor, recarga la página.")
      this.loadState.retryCount = 0
    }
  }
  
  // Consider loading previous items when scrolling up
  considerPreviousItems() {
    // This is a placeholder for future implementation
    // Could be used to load older items when scrolling up
  }
  
  // Clean up node pool
  cleanupNodePool() {
    this.nodePool = []
    this.renderState.renderedItems.forEach(node => {
      if (node && node.parentNode) {
        node.parentNode.removeChild(node)
      }
    })
    this.renderState.renderedItems.clear()
  }
  
  // Format date
  formatDate(dateString) {
    const date = new Date(dateString)
    return date.toLocaleDateString('es-CR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric'
    })
  }
  
  // Format date time
  formatDateTime(dateString) {
    const date = new Date(dateString)
    return date.toLocaleDateString('es-CR', {
      day: '2-digit',
      month: '2-digit',
      hour: '2-digit',
      minute: '2-digit'
    })
  }
  
  // Format currency
  formatCurrency(amount, currency = 'CRC') {
    const symbol = currency === 'USD' ? '$' : '₡'
    return `${symbol}${Number(amount).toLocaleString('es-CR')}`
  }
  
  // Throttle function for scroll events
  throttle(func, limit) {
    let inThrottle
    return function() {
      const args = arguments
      const context = this
      if (!inThrottle) {
        func.apply(context, args)
        inThrottle = true
        setTimeout(() => inThrottle = false, limit)
      }
    }
  }
  
  // Dispatch custom events
  dispatch(eventName, options = {}) {
    const event = new CustomEvent(`virtual-scroll:${eventName}`, {
      bubbles: true,
      cancelable: true,
      ...options
    })
    this.element.dispatchEvent(event)
  }
  
  // Restore scroll position from persistence (Task 3.8)
  restoreScrollPosition() {
    const persistedState = this.stateManager.loadState()
    
    if (persistedState.scroll_position && persistedState.scroll_position > 0) {
      // Wait for initial render then restore position
      setTimeout(() => {
        if (this.hasViewportTarget) {
          this.viewportTarget.scrollTop = persistedState.scroll_position
          
          // Show subtle indicator
          this.showScrollRestoredIndicator(persistedState.scroll_position)
        }
      }, 100)
    }
  }
  
  // Persist scroll position (Task 3.8)
  persistScrollPosition = this.debounce((position) => {
    // Only persist significant scroll changes
    if (Math.abs(position - (this.lastPersistedScroll || 0)) > 50) {
      this.stateManager.saveState(
        { scroll_position: Math.round(position) },
        { updateURL: false, updateLocal: true, updateSession: true }
      )
      this.lastPersistedScroll = position
      
      // Dispatch event for persistence controller
      this.dispatch('scrolled', {
        detail: { position: Math.round(position) }
      })
    }
  }, 500)
  
  // Show indicator when scroll position is restored
  showScrollRestoredIndicator(position) {
    const indicator = document.createElement('div')
    indicator.className = 'fixed bottom-4 left-4 px-3 py-2 bg-teal-50 text-teal-700 text-sm rounded-lg shadow-md z-40'
    indicator.innerHTML = `
      <div class="flex items-center space-x-2">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 11l5-5m0 0l5 5m-5-5v12"></path>
        </svg>
        <span>Posición restaurada</span>
      </div>
    `
    
    document.body.appendChild(indicator)
    
    // Fade in
    indicator.style.opacity = '0'
    indicator.style.transform = 'translateY(10px)'
    requestAnimationFrame(() => {
      indicator.style.transition = 'all 0.3s ease-out'
      indicator.style.opacity = '1'
      indicator.style.transform = 'translateY(0)'
    })
    
    // Auto-remove after 2 seconds
    setTimeout(() => {
      indicator.style.opacity = '0'
      indicator.style.transform = 'translateY(10px)'
      setTimeout(() => indicator.remove(), 300)
    }, 2000)
  }
  
  // Debounce utility (if not already defined)
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
}