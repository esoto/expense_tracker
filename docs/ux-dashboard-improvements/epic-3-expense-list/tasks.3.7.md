## Task 3.7: Virtual Scrolling Implementation

**Task ID:** EXP-3.7  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** Medium (Critical for 1000+ expenses)  
**Estimated Hours:** 10  
**Dependencies:** Task 3.1 (optimized queries), Task 3.4 (selection system)  
**Blocks:** None

### Description
Implement high-performance virtual scrolling for efficiently displaying large expense lists (1000+ items) maintaining 60fps performance. Includes memory management, progressive enhancement, and fallback strategies.

### Acceptance Criteria
- [ ] Smooth 60fps scrolling with 10,000+ items
- [ ] DOM nodes limited to <200 at any time
- [ ] Memory usage <50MB for 10k items
- [ ] Scroll position preserved on navigation
- [ ] Search/filter integration seamless
- [ ] Selection state maintained during scroll
- [ ] Graceful fallback to pagination
- [ ] Accessibility maintained (screen readers)
- [ ] Mobile touch scrolling optimized

### Technical Implementation

#### 1. Virtual Scroll Controller

```javascript
// app/javascript/controllers/virtual_scroll_controller.js
import { Controller } from "@hotwired/stimulus"
import { VirtualList } from '@tanstack/virtual'

export default class extends Controller {
  static targets = ["container", "viewport", "items", "spacer", "loader"]
  static values = { 
    totalItems: Number,
    itemHeight: Number,
    pageSize: Number,
    url: String,
    threshold: Number
  }
  
  connect() {
    this.itemHeightValue = this.itemHeightValue || 60
    this.pageSizeValue = this.pageSizeValue || 50
    this.thresholdValue = this.thresholdValue || 5
    
    this.initializeVirtualizer()
    this.setupIntersectionObserver()
    this.setupScrollListener()
    this.loadInitialData()
    this.initializeItemPool()
  }
  
  initializeVirtualizer() {
    this.virtualizer = new VirtualList({
      count: this.totalItemsValue,
      getScrollElement: () => this.containerTarget,
      estimateSize: () => this.itemHeightValue,
      overscan: this.thresholdValue,
      horizontal: false,
      lanes: 1,
      
      // Performance optimizations
      measureElement: (el) => el.getBoundingClientRect().height,
      initialRect: { width: 0, height: this.itemHeightValue },
      scrollMargin: 0,
      gap: 0,
      
      // Memory management
      maxRangeSize: 200,  // Max items in memory
      enableSmoothScroll: true
    })
    
    // Custom render queue for 60fps
    this.renderQueue = new RenderQueue(60)
    this.dataCache = new Map()
    this.visibleRange = { start: 0, end: 0 }
  }
  
  setupIntersectionObserver() {
    // Observer for loading more data
    this.observer = new IntersectionObserver(
      (entries) => this.handleIntersection(entries),
      {
        root: this.containerTarget,
        rootMargin: '200px',  // Load 200px before visible
        threshold: [0, 0.5, 1.0]
      }
    )
    
    // Observe sentinel elements
    if (this.hasLoaderTarget) {
      this.observer.observe(this.loaderTarget)
    }
  }
  
  setupScrollListener() {
    this.scrollHandler = this.debounce(this.handleScroll.bind(this), 16)
    this.containerTarget.addEventListener('scroll', this.scrollHandler, { passive: true })
  }
  
  async loadInitialData() {
    const startIndex = 0
    const endIndex = Math.min(this.pageSizeValue * 2, this.totalItemsValue)
    
    try {
      const data = await this.fetchData(startIndex, endIndex)
      this.cacheData(data, startIndex)
      this.renderItems(data, startIndex)
      this.updateSpacerHeight()
    } catch (error) {
      this.handleLoadError(error)
    }
  }
  
  async fetchData(start, end) {
    // Check cache first
    const cached = this.getCachedRange(start, end)
    if (cached.complete) return cached.data
    
    const response = await fetch(`${this.urlValue}?start=${start}&end=${end}`, {
      headers: {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest'
      },
      signal: this.abortController?.signal
    })
    
    if (!response.ok) throw new Error(`Failed to fetch: ${response.status}`)
    
    const data = await response.json()
    return data.expenses || data
  }
  
  renderItems(items, startIndex) {
    // Use DocumentFragment for batch DOM updates
    const fragment = document.createDocumentFragment()
    
    items.forEach((item, index) => {
      const element = this.itemPool.acquire()
      this.populateElement(element, item)
      element.dataset.index = startIndex + index
      element.dataset.id = item.id
      
      // Set absolute positioning
      element.style.position = 'absolute'
      element.style.top = `${(startIndex + index) * this.itemHeightValue}px`
      element.style.width = '100%'
      
      fragment.appendChild(element)
    })
    
    // Single DOM update
    this.renderQueue.enqueue(() => {
      this.itemsTarget.appendChild(fragment)
      this.updateVisibleRange()
      this.recycleOffscreenItems()
    })
  }
  
  populateElement(element, data) {
    // Update element with expense data
    element.querySelector('.expense-amount').textContent = data.formatted_amount
    element.querySelector('.expense-merchant').textContent = data.merchant_name
    element.querySelector('.expense-date').textContent = data.transaction_date
    element.querySelector('.expense-category').textContent = data.category_name
    
    // Update checkbox if exists
    const checkbox = element.querySelector('input[type="checkbox"]')
    if (checkbox) {
      checkbox.dataset.expenseId = data.id
      checkbox.checked = this.isSelected(data.id)
    }
  }
  
  handleScroll() {
    const scrollTop = this.containerTarget.scrollTop
    const containerHeight = this.containerTarget.clientHeight
    
    // Calculate visible range
    const visibleStart = Math.floor(scrollTop / this.itemHeightValue)
    const visibleEnd = Math.ceil((scrollTop + containerHeight) / this.itemHeightValue)
    
    // Add overscan
    const start = Math.max(0, visibleStart - this.thresholdValue)
    const end = Math.min(this.totalItemsValue, visibleEnd + this.thresholdValue)
    
    // Load data if needed
    if (this.needsData(start, end)) {
      this.loadRange(start, end)
    }
    
    // Update visible items
    this.visibleRange = { start: visibleStart, end: visibleEnd }
    this.updateVisibleItems(start, end)
    
    // Recycle off-screen items
    this.recycleOffscreenItems()
    
    // Update performance metrics
    this.updatePerformanceMetrics()
  }
  
  recycleOffscreenItems() {
    const buffer = this.thresholdValue * 2
    const items = this.itemsTarget.querySelectorAll('[data-index]')
    
    items.forEach(item => {
      const index = parseInt(item.dataset.index)
      
      if (index < this.visibleRange.start - buffer || 
          index > this.visibleRange.end + buffer) {
        this.itemPool.release(item)
      }
    })
  }
  
  // Item pool for DOM element reuse
  initializeItemPool() {
    this.itemPool = {
      available: [],
      inUse: new Set(),
      template: document.getElementById('expense-row-template'),
      maxSize: 200,
      
      acquire() {
        let element
        
        if (this.available.length > 0) {
          element = this.available.pop()
        } else if (this.inUse.size < this.maxSize) {
          element = this.createElement()
        } else {
          // Force reclaim oldest
          element = this.reclaimOldest()
        }
        
        this.inUse.add(element)
        return element
      },
      
      release(element) {
        if (this.inUse.has(element)) {
          this.inUse.delete(element)
          this.resetElement(element)
          this.available.push(element)
          element.remove()  // Remove from DOM
        }
      },
      
      createElement() {
        const clone = this.template.content.cloneNode(true)
        return clone.firstElementChild
      },
      
      resetElement(element) {
        element.className = 'expense-row'
        element.removeAttribute('data-index')
        element.removeAttribute('data-id')
        element.style.transform = ''
      },
      
      reclaimOldest() {
        const oldest = this.inUse.values().next().value
        this.release(oldest)
        return this.acquire()
      }
    }
  }
  
  // Performance monitoring
  updatePerformanceMetrics() {
    if (!window.performance) return
    
    const metrics = {
      fps: this.calculateFPS(),
      memory: this.getMemoryUsage(),
      domNodes: this.itemsTarget.children.length,
      cacheSize: this.dataCache.size,
      renderTime: this.renderQueue.averageTime
    }
    
    // Dispatch metrics event
    this.dispatch('metrics', { detail: metrics })
    
    // Log warnings
    if (metrics.fps < 30) {
      console.warn('Virtual scroll FPS below 30:', metrics.fps)
    }
    if (metrics.domNodes > 200) {
      console.warn('Too many DOM nodes:', metrics.domNodes)
    }
  }
  
  calculateFPS() {
    const now = performance.now()
    if (!this.lastFrameTime) {
      this.lastFrameTime = now
      return 60
    }
    
    const delta = now - this.lastFrameTime
    this.lastFrameTime = now
    return Math.round(1000 / delta)
  }
  
  getMemoryUsage() {
    if (performance.memory) {
      return Math.round(performance.memory.usedJSHeapSize / 1048576)  // MB
    }
    return 0
  }
  
  // Utility functions
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
  
  disconnect() {
    this.containerTarget.removeEventListener('scroll', this.scrollHandler)
    this.observer?.disconnect()
    this.abortController?.abort()
    this.virtualizer?.destroy()
  }
}

// Render queue for 60fps
class RenderQueue {
  constructor(targetFPS = 60) {
    this.queue = []
    this.frameTime = 1000 / targetFPS
    this.processing = false
    this.totalTime = 0
    this.frameCount = 0
  }
  
  enqueue(callback) {
    this.queue.push(callback)
    if (!this.processing) this.process()
  }
  
  process() {
    this.processing = true
    const startTime = performance.now()
    
    requestAnimationFrame(() => {
      while (this.queue.length > 0 && 
             performance.now() - startTime < this.frameTime * 0.8) {
        const task = this.queue.shift()
        task()
      }
      
      this.totalTime += performance.now() - startTime
      this.frameCount++
      
      if (this.queue.length > 0) {
        this.process()
      } else {
        this.processing = false
      }
    })
  }
  
  get averageTime() {
    return this.frameCount > 0 ? this.totalTime / this.frameCount : 0
  }
}
```

#### 2. Fallback Implementation

```javascript
// app/javascript/controllers/pagination_fallback_controller.js
export default class extends Controller {
  connect() {
    if (!this.supportsVirtualScrolling()) {
      this.initializePagination()
    }
  }
  
  supportsVirtualScrolling() {
    return 'IntersectionObserver' in window &&
           'requestIdleCallback' in window &&
           CSS.supports('contain', 'layout') &&
           !this.isMobileDevice()
  }
  
  isMobileDevice() {
    return /Android|webOS|iPhone|iPad|iPod/i.test(navigator.userAgent)
  }
  
  initializePagination() {
    // Traditional pagination for unsupported browsers
    this.element.dataset.controller = 'pagination'
  }
}
```

#### 3. Backend Support

```ruby
# app/controllers/api/expenses_controller.rb
class Api::ExpensesController < ApplicationController
  def virtual_scroll
    start_index = params[:start].to_i
    end_index = params[:end].to_i
    limit = [end_index - start_index, 100].min  # Max 100 items per request
    
    expenses = Expense
      .for_list_display
      .where(email_account_id: current_user_account_ids)
      .offset(start_index)
      .limit(limit)
      .includes(:category)
    
    render json: {
      expenses: expenses.map { |e| ExpenseSerializer.new(e).as_json },
      total: Expense.where(email_account_id: current_user_account_ids).count,
      has_more: end_index < total_count
    }
  end
end
```

### Performance Targets

| Metric | Target | Acceptable | Critical |
|--------|--------|------------|----------|
| Scroll FPS | 60 | 45-59 | <45 |
| Initial render | <200ms | <500ms | >500ms |
| Scroll response | <16ms | <33ms | >33ms |
| Memory usage | <50MB | <100MB | >100MB |
| DOM nodes | <200 | <300 | >300 |
| Cache hit rate | >80% | >60% | <60% |

### Browser Compatibility

| Browser | Support | Fallback |
|---------|---------|----------|
| Chrome 90+ | Full | - |
| Firefox 88+ | Full | - |
| Safari 14+ | Full | - |
| Edge 90+ | Full | - |
| Mobile browsers | Disabled | Pagination |
| IE 11 | No | Pagination |

### Testing Requirements

```ruby
# spec/system/virtual_scrolling_spec.rb
RSpec.describe "Virtual Scrolling", type: :system, js: true do
  before do
    create_list(:expense, 1000, email_account: account)
    visit expenses_path
  end
  
  it "maintains 60fps performance" do
    fps_readings = []
    
    # Scroll and measure FPS
    10.times do
      execute_script("window.scrollBy(0, 500)")
      sleep 0.1
      fps = execute_script("return window.currentFPS || 60")
      fps_readings << fps
    end
    
    average_fps = fps_readings.sum / fps_readings.size
    expect(average_fps).to be >= 55
  end
  
  it "limits DOM nodes" do
    # Scroll to middle
    execute_script("window.scrollTo(0, document.body.scrollHeight / 2)")
    sleep 0.5
    
    dom_nodes = all('.expense-row').count
    expect(dom_nodes).to be < 200
  end
  
  it "preserves selection during scroll" do
    # Select some items
    first('.expense-checkbox').click
    
    # Scroll away and back
    execute_script("window.scrollTo(0, 5000)")
    sleep 0.5
    execute_script("window.scrollTo(0, 0)")
    sleep 0.5
    
    # Check selection preserved
    expect(first('.expense-checkbox')).to be_checked
  end
end
```

### Mobile Considerations

- Disable virtual scrolling on mobile (use pagination)
- Touch scrolling optimization with `passive: true`
- Momentum scrolling with `-webkit-overflow-scrolling: touch`
- Reduced overscan (3 items instead of 5)

### Definition of Done

- [ ] 60fps scrolling with 10k items
- [ ] Memory usage under control (<50MB)
- [ ] DOM nodes always <200
- [ ] Graceful degradation for older browsers
- [ ] Accessibility preserved
- [ ] Performance metrics tracked
- [ ] Mobile experience optimized
- [ ] Documentation complete
