// ProgressThrottler - Client-side JavaScript class for throttling and optimizing
// ActionCable progress updates to prevent UI performance degradation.
//
// Key Features:
// - Throttles high-frequency updates to maintain UI responsiveness  
// - Batches DOM updates using requestAnimationFrame for smooth animations
// - Implements adaptive throttling based on browser performance
// - Provides priority-based update queuing
// - Includes built-in performance monitoring and metrics
// - Graceful degradation for slower browsers/devices
//
// Usage:
//   // Initialize throttler in your Stimulus controller
//   this.progressThrottler = new ProgressThrottler({
//     maxUpdateRate: 30, // Max 30 updates per second
//     adaptiveThrottling: true,
//     performanceMonitoring: true
//   });
//
//   // Add progress updates (automatically throttled)
//   this.progressThrottler.addUpdate('progress', {
//     percentage: 65,
//     element: this.progressBarTarget,
//     data: progressData
//   });
//
//   // Add high-priority updates (processed immediately)
//   this.progressThrottler.addUpdate('critical', {
//     type: 'error',
//     element: this.statusTarget,
//     data: errorData
//   }, 'high');

class ProgressThrottler {
  constructor(options = {}) {
    // Default configuration
    this.config = {
      maxUpdateRate: 30,              // Maximum updates per second
      batchSize: 10,                  // Max updates per batch
      adaptiveThrottling: true,       // Enable adaptive throttling
      performanceMonitoring: true,    // Enable performance tracking
      debugMode: false,               // Enable debug logging
      throttleByPriority: true,       // Different throttling by priority
      useRequestAnimationFrame: true, // Use RAF for smooth animations
      maxQueueSize: 100,              // Max queued updates
      performanceThreshold: 16.67     // Target 60fps (16.67ms per frame)
    };
    
    Object.assign(this.config, options);
    
    // Internal state
    this.updateQueue = [];
    this.lastUpdateTime = 0;
    this.frameId = null;
    this.isProcessing = false;
    this.statistics = this.initializeStatistics();
    this.performanceMetrics = this.initializePerformanceMetrics();
    
    // Priority-based throttling intervals (ms)
    this.priorityThrottleIntervals = {
      critical: 0,      // No throttling for critical updates
      high: 50,         // 20 FPS for high priority  
      medium: 100,      // 10 FPS for medium priority
      low: 200          // 5 FPS for low priority
    };
    
    // Adaptive throttling parameters
    this.adaptiveParams = {
      currentInterval: 1000 / this.config.maxUpdateRate,
      minInterval: 16.67,  // 60fps minimum
      maxInterval: 200,    // 5fps maximum
      adjustmentFactor: 1.1,
      performanceSamples: [],
      sampleSize: 10
    };
    
    this.bindMethods();
    this.startPerformanceMonitoring();
    
    if (this.config.debugMode) {
      console.log('[ProgressThrottler] Initialized with config:', this.config);
    }
  }
  
  // Add an update to the throttling queue
  // @param {string} updateType - Type of update (progress, status, activity)
  // @param {Object} updateData - Data for the update
  // @param {string} priority - Priority level (critical, high, medium, low)
  addUpdate(updateType, updateData, priority = 'medium') {
    const update = {
      id: this.generateUpdateId(),
      type: updateType,
      data: updateData,
      priority: priority,
      timestamp: performance.now(),
      attempts: 0
    };
    
    // Handle queue overflow
    if (this.updateQueue.length >= this.config.maxQueueSize) {
      this.handleQueueOverflow();
    }
    
    // Add to queue with priority sorting
    this.updateQueue.push(update);
    this.sortQueueByPriority();
    
    // Update statistics
    this.statistics.totalUpdatesQueued++;
    this.statistics.updatesByType[updateType] = (this.statistics.updatesByType[updateType] || 0) + 1;
    this.statistics.updatesByPriority[priority] = (this.statistics.updatesByPriority[priority] || 0) + 1;
    
    // Process updates if not already processing
    if (!this.isProcessing) {
      this.scheduleNextUpdate();
    }
    
    if (this.config.debugMode) {
      console.log('[ProgressThrottler] Added update:', update);
    }
  }
  
  // Process the next batch of updates
  processNextBatch() {
    if (this.updateQueue.length === 0) {
      this.isProcessing = false;
      return;
    }
    
    const startTime = performance.now();
    const currentTime = startTime;
    
    // Determine batch size based on queue size and priority
    const batchSize = this.calculateOptimalBatchSize();
    const batch = this.updateQueue.splice(0, batchSize);
    
    if (this.config.debugMode) {
      console.log('[ProgressThrottler] Processing batch:', batch.length, 'updates');
    }
    
    // Process updates in the batch
    const processedUpdates = [];
    for (const update of batch) {
      try {
        this.processUpdate(update);
        processedUpdates.push(update);
        this.statistics.totalUpdatesProcessed++;
      } catch (error) {
        console.error('[ProgressThrottler] Error processing update:', error);
        this.statistics.totalUpdateErrors++;
        
        // Retry logic for failed updates
        if (update.attempts < 3) {
          update.attempts++;
          this.updateQueue.unshift(update); // Add back to front for retry
        }
      }
    }
    
    // Update performance metrics
    const processingTime = performance.now() - startTime;
    this.updatePerformanceMetrics(processingTime, processedUpdates.length);
    
    // Schedule next batch if more updates are queued
    if (this.updateQueue.length > 0) {
      this.scheduleNextUpdate();
    } else {
      this.isProcessing = false;
    }
  }
  
  // Process an individual update
  processUpdate(update) {
    const { type, data, priority } = update;
    
    switch (type) {
      case 'progress':
        this.updateProgress(data);
        break;
      case 'account':
        this.updateAccount(data);
        break;
      case 'activity':
        this.updateActivity(data);
        break;
      case 'status':
        this.updateStatus(data);
        break;
      case 'critical':
        this.updateCritical(data);
        break;
      default:
        console.warn('[ProgressThrottler] Unknown update type:', type);
    }
    
    // Fire custom event for update processed
    this.dispatchUpdateEvent(update);
  }
  
  // Update progress indicators
  updateProgress(data) {
    const { percentage, element, animateTransition = true } = data;
    
    if (!element) {
      console.warn('[ProgressThrottler] No element provided for progress update');
      return;
    }
    
    // Batch DOM updates
    this.batchDOMUpdate(() => {
      // Update progress bar width
      if (element.classList.contains('progress-bar')) {
        const newWidth = `${Math.min(Math.max(percentage, 0), 100)}%`;
        
        if (animateTransition && this.supportsCSS3Transitions()) {
          element.style.transition = 'width 0.3s ease-out';
        }
        
        element.style.width = newWidth;
      }
      
      // Update progress text
      const textElement = element.querySelector('.progress-text') || 
                         element.nextElementSibling?.classList.contains('progress-text') ? 
                         element.nextElementSibling : null;
      
      if (textElement) {
        textElement.textContent = `${Math.round(percentage)}%`;
      }
      
      // Update ARIA attributes for accessibility
      element.setAttribute('aria-valuenow', Math.round(percentage));
      
      // Update data attributes
      element.dataset.progress = percentage;
    });
  }
  
  // Update account status
  updateAccount(data) {
    const { accountId, status, element, progress, processed, total } = data;
    
    if (!element) return;
    
    this.batchDOMUpdate(() => {
      // Update status indicator
      const statusElement = element.querySelector(`[data-account-id="${accountId}"] .status`);
      if (statusElement) {
        statusElement.textContent = this.translateStatus(status);
        statusElement.className = `status status-${status}`;
      }
      
      // Update progress if provided
      if (progress !== undefined) {
        const progressElement = element.querySelector(`[data-account-id="${accountId}"] .progress-bar`);
        if (progressElement) {
          progressElement.style.width = `${progress}%`;
        }
      }
      
      // Update counts
      if (processed !== undefined && total !== undefined) {
        const countElement = element.querySelector(`[data-account-id="${accountId}"] .count`);
        if (countElement) {
          countElement.textContent = `${processed}/${total}`;
        }
      }
    });
  }
  
  // Update activity feed
  updateActivity(data) {
    const { message, activityType, element, timestamp } = data;
    
    if (!element) return;
    
    this.batchDOMUpdate(() => {
      const activityItem = document.createElement('div');
      activityItem.className = `activity-item activity-${activityType}`;
      activityItem.innerHTML = `
        <span class="activity-message">${this.escapeHtml(message)}</span>
        <span class="activity-time">${this.formatTimestamp(timestamp)}</span>
      `;
      
      // Add to top of activity feed
      element.insertBefore(activityItem, element.firstChild);
      
      // Limit activity items to prevent memory issues
      const maxItems = 20;
      const items = element.querySelectorAll('.activity-item');
      if (items.length > maxItems) {
        for (let i = maxItems; i < items.length; i++) {
          items[i].remove();
        }
      }
      
      // Auto-scroll to show latest activity
      if (element.scrollTop === 0) {
        element.scrollTop = 0;
      }
    });
  }
  
  // Update overall status
  updateStatus(data) {
    const { status, element, message } = data;
    
    if (!element) return;
    
    this.batchDOMUpdate(() => {
      element.textContent = message || this.translateStatus(status);
      element.className = `status status-${status}`;
      
      // Update status indicator colors using CSS custom properties
      const statusColor = this.getStatusColor(status);
      element.style.setProperty('--status-color', statusColor);
    });
  }
  
  // Handle critical updates (bypass throttling)
  updateCritical(data) {
    const { type, message, element } = data;
    
    // Process immediately without throttling
    this.batchDOMUpdate(() => {
      if (type === 'error') {
        this.showErrorNotification(message, element);
      } else if (type === 'completion') {
        this.showCompletionMessage(message, element);
      } else if (type === 'connection_lost') {
        this.showConnectionLostWarning(element);
      }
    });
  }
  
  // Schedule the next update batch
  scheduleNextUpdate() {
    if (this.isProcessing) return;
    
    this.isProcessing = true;
    const delay = this.calculateThrottleDelay();
    
    if (this.config.useRequestAnimationFrame && delay < 16) {
      // Use requestAnimationFrame for smooth updates
      this.frameId = requestAnimationFrame(() => this.processNextBatch());
    } else {
      // Use setTimeout for longer delays
      setTimeout(() => this.processNextBatch(), delay);
    }
  }
  
  // Calculate appropriate throttle delay
  calculateThrottleDelay() {
    if (!this.config.adaptiveThrottling) {
      return 1000 / this.config.maxUpdateRate;
    }
    
    // Get highest priority in queue
    const highestPriority = this.getHighestPriorityInQueue();
    const basePriorityDelay = this.priorityThrottleIntervals[highestPriority] || 100;
    
    // Adjust based on performance metrics
    const performanceAdjustment = this.calculatePerformanceAdjustment();
    
    return Math.max(
      basePriorityDelay * performanceAdjustment,
      this.adaptiveParams.minInterval
    );
  }
  
  // Calculate optimal batch size
  calculateOptimalBatchSize() {
    const queueLength = this.updateQueue.length;
    const recentPerformance = this.getRecentPerformanceAverage();
    
    // Adjust batch size based on performance
    let batchSize = this.config.batchSize;
    
    if (recentPerformance > this.config.performanceThreshold * 1.5) {
      // Performance is poor, reduce batch size
      batchSize = Math.max(1, Math.floor(batchSize * 0.7));
    } else if (recentPerformance < this.config.performanceThreshold * 0.8) {
      // Performance is good, can increase batch size
      batchSize = Math.min(this.config.maxQueueSize, Math.floor(batchSize * 1.3));
    }
    
    return Math.min(batchSize, queueLength);
  }
  
  // Batch DOM updates using requestAnimationFrame
  batchDOMUpdate(updateFunction) {
    if (this.config.useRequestAnimationFrame) {
      requestAnimationFrame(updateFunction);
    } else {
      updateFunction();
    }
  }
  
  // Get statistics about throttler performance
  getStatistics() {
    const currentTime = performance.now();
    const runtime = currentTime - this.statistics.startTime;
    
    return {
      ...this.statistics,
      runtime: runtime,
      averageProcessingTime: this.performanceMetrics.totalProcessingTime / 
                           Math.max(this.performanceMetrics.batchesProcessed, 1),
      updatesPerSecond: (this.statistics.totalUpdatesProcessed / runtime) * 1000,
      currentQueueSize: this.updateQueue.length,
      adaptiveInterval: this.adaptiveParams.currentInterval
    };
  }
  
  // Reset throttler state
  reset() {
    this.updateQueue.length = 0;
    this.isProcessing = false;
    
    if (this.frameId) {
      cancelAnimationFrame(this.frameId);
      this.frameId = null;
    }
    
    this.statistics = this.initializeStatistics();
    this.performanceMetrics = this.initializePerformanceMetrics();
  }
  
  // Clean up resources
  destroy() {
    this.reset();
    this.stopPerformanceMonitoring();
  }
  
  // Helper methods
  
  bindMethods() {
    this.processNextBatch = this.processNextBatch.bind(this);
  }
  
  generateUpdateId() {
    return `update_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }
  
  initializeStatistics() {
    return {
      startTime: performance.now(),
      totalUpdatesQueued: 0,
      totalUpdatesProcessed: 0,
      totalUpdateErrors: 0,
      updatesByType: {},
      updatesByPriority: {}
    };
  }
  
  initializePerformanceMetrics() {
    return {
      batchesProcessed: 0,
      totalProcessingTime: 0,
      averageProcessingTime: 0,
      maxProcessingTime: 0,
      minProcessingTime: Infinity
    };
  }
  
  sortQueueByPriority() {
    const priorityOrder = { critical: 0, high: 1, medium: 2, low: 3 };
    
    this.updateQueue.sort((a, b) => {
      const priorityA = priorityOrder[a.priority] || 2;
      const priorityB = priorityOrder[b.priority] || 2;
      
      if (priorityA !== priorityB) {
        return priorityA - priorityB;
      }
      
      // Secondary sort by timestamp for same priority
      return a.timestamp - b.timestamp;
    });
  }
  
  getHighestPriorityInQueue() {
    if (this.updateQueue.length === 0) return 'medium';
    
    return this.updateQueue[0].priority || 'medium';
  }
  
  handleQueueOverflow() {
    // Remove oldest low-priority updates to make room
    const lowPriorityIndex = this.updateQueue.findIndex(update => update.priority === 'low');
    
    if (lowPriorityIndex !== -1) {
      this.updateQueue.splice(lowPriorityIndex, 1);
      this.statistics.totalUpdatesDropped = (this.statistics.totalUpdatesDropped || 0) + 1;
    } else {
      // If no low priority updates, remove oldest medium priority
      const mediumPriorityIndex = this.updateQueue.findIndex(update => update.priority === 'medium');
      if (mediumPriorityIndex !== -1) {
        this.updateQueue.splice(mediumPriorityIndex, 1);
        this.statistics.totalUpdatesDropped = (this.statistics.totalUpdatesDropped || 0) + 1;
      }
    }
  }
  
  updatePerformanceMetrics(processingTime, updatesProcessed) {
    this.performanceMetrics.batchesProcessed++;
    this.performanceMetrics.totalProcessingTime += processingTime;
    this.performanceMetrics.maxProcessingTime = Math.max(this.performanceMetrics.maxProcessingTime, processingTime);
    this.performanceMetrics.minProcessingTime = Math.min(this.performanceMetrics.minProcessingTime, processingTime);
    this.performanceMetrics.averageProcessingTime = 
      this.performanceMetrics.totalProcessingTime / this.performanceMetrics.batchesProcessed;
    
    // Update adaptive throttling parameters
    if (this.config.adaptiveThrottling) {
      this.adaptiveParams.performanceSamples.push(processingTime);
      
      if (this.adaptiveParams.performanceSamples.length > this.adaptiveParams.sampleSize) {
        this.adaptiveParams.performanceSamples.shift();
      }
      
      this.adjustAdaptiveThrottling();
    }
  }
  
  adjustAdaptiveThrottling() {
    const avgPerformance = this.getRecentPerformanceAverage();
    const target = this.config.performanceThreshold;
    
    if (avgPerformance > target * 1.2) {
      // Performance is poor, increase interval (reduce frequency)
      this.adaptiveParams.currentInterval = Math.min(
        this.adaptiveParams.currentInterval * this.adaptiveParams.adjustmentFactor,
        this.adaptiveParams.maxInterval
      );
    } else if (avgPerformance < target * 0.8) {
      // Performance is good, decrease interval (increase frequency)
      this.adaptiveParams.currentInterval = Math.max(
        this.adaptiveParams.currentInterval / this.adaptiveParams.adjustmentFactor,
        this.adaptiveParams.minInterval
      );
    }
  }
  
  getRecentPerformanceAverage() {
    const samples = this.adaptiveParams.performanceSamples;
    if (samples.length === 0) return this.config.performanceThreshold;
    
    return samples.reduce((sum, sample) => sum + sample, 0) / samples.length;
  }
  
  calculatePerformanceAdjustment() {
    const recentPerformance = this.getRecentPerformanceAverage();
    const target = this.config.performanceThreshold;
    
    return Math.max(0.5, Math.min(2.0, recentPerformance / target));
  }
  
  startPerformanceMonitoring() {
    if (!this.config.performanceMonitoring) return;
    
    // Monitor performance every 5 seconds
    this.performanceMonitoringInterval = setInterval(() => {
      const stats = this.getStatistics();
      
      if (this.config.debugMode) {
        console.log('[ProgressThrottler] Performance Stats:', stats);
      }
      
      // Dispatch performance event for external monitoring
      this.dispatchPerformanceEvent(stats);
    }, 5000);
  }
  
  stopPerformanceMonitoring() {
    if (this.performanceMonitoringInterval) {
      clearInterval(this.performanceMonitoringInterval);
      this.performanceMonitoringInterval = null;
    }
  }
  
  dispatchUpdateEvent(update) {
    const event = new CustomEvent('progressthrottler:update', {
      detail: { update, statistics: this.getStatistics() }
    });
    document.dispatchEvent(event);
  }
  
  dispatchPerformanceEvent(stats) {
    const event = new CustomEvent('progressthrottler:performance', {
      detail: stats
    });
    document.dispatchEvent(event);
  }
  
  // UI Helper methods
  translateStatus(status) {
    const translations = {
      pending: 'Pendiente',
      processing: 'Procesando',
      completed: 'Completado',
      failed: 'Fallido',
      paused: 'Pausado'
    };
    
    return translations[status] || status;
  }
  
  getStatusColor(status) {
    const colors = {
      pending: '#6b7280',    // slate-500
      processing: '#0f766e', // teal-700  
      completed: '#10b981',  // emerald-500
      failed: '#ef4444',     // red-500
      paused: '#f59e0b'      // amber-500
    };
    
    return colors[status] || colors.pending;
  }
  
  escapeHtml(text) {
    const map = {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#039;'
    };
    
    return text.replace(/[&<>"']/g, (m) => map[m]);
  }
  
  formatTimestamp(timestamp) {
    const date = new Date(timestamp);
    return date.toLocaleTimeString();
  }
  
  supportsCSS3Transitions() {
    const testEl = document.createElement('div');
    return 'transition' in testEl.style || 'webkitTransition' in testEl.style;
  }
  
  showErrorNotification(message, element) {
    // Implementation for error notifications
    if (element) {
      element.innerHTML = `<div class="error-notification">${this.escapeHtml(message)}</div>`;
    }
  }
  
  showCompletionMessage(message, element) {
    // Implementation for completion messages
    if (element) {
      element.innerHTML = `<div class="completion-notification">${this.escapeHtml(message)}</div>`;
    }
  }
  
  showConnectionLostWarning(element) {
    // Implementation for connection warnings
    if (element) {
      element.innerHTML = '<div class="warning-notification">Conexión perdida. Reintentando...</div>';
    }
  }
}

// Export for use in other modules
export default ProgressThrottler;