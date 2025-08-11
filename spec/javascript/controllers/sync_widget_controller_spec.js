// spec/javascript/controllers/sync_widget_controller_spec.js
import { Application } from "@hotwired/stimulus"
import SyncWidgetController from "../../../app/javascript/controllers/sync_widget_controller"
import { createConsumer } from "@rails/actioncable"

// Mock ActionCable
jest.mock("@rails/actioncable", () => ({
  createConsumer: jest.fn()
}))

describe("SyncWidgetController", () => {
  let application
  let controller
  let element
  let mockConsumer
  let mockSubscription

  beforeEach(() => {
    // Setup DOM
    document.body.innerHTML = `
      <div data-controller="sync-widget" 
           data-sync-widget-session-id-value="123"
           data-sync-widget-active-value="true"
           data-sync-widget-debug-value="false">
        <div data-sync-widget-target="progressBar"></div>
        <div data-sync-widget-target="progressPercentage">0%</div>
        <div data-sync-widget-target="processedCount">0</div>
        <div data-sync-widget-target="detectedCount">0</div>
        <div data-sync-widget-target="timeRemaining">--</div>
        <div data-sync-widget-target="connectionStatus">Disconnected</div>
        <button data-sync-widget-target="retryButton" class="hidden">Retry</button>
        <div data-sync-widget-target="accountsList"></div>
      </div>
    `

    // Setup Stimulus
    application = Application.start()
    application.register("sync-widget", SyncWidgetController)

    // Get controller instance
    element = document.querySelector('[data-controller="sync-widget"]')
    controller = application.getControllerForElementAndIdentifier(element, "sync-widget")

    // Setup ActionCable mocks
    mockSubscription = {
      unsubscribe: jest.fn(),
      perform: jest.fn()
    }

    mockConsumer = {
      subscriptions: {
        create: jest.fn().mockReturnValue(mockSubscription)
      },
      disconnect: jest.fn()
    }

    createConsumer.mockReturnValue(mockConsumer)

    // Mock console methods
    global.console.info = jest.fn()
    global.console.warn = jest.fn()
    global.console.error = jest.fn()
    global.console.debug = jest.fn()

    // Mock sessionStorage
    const sessionStorageMock = {
      getItem: jest.fn(),
      setItem: jest.fn(),
      removeItem: jest.fn(),
      clear: jest.fn()
    }
    Object.defineProperty(window, 'sessionStorage', {
      value: sessionStorageMock,
      writable: true
    })
  })

  afterEach(() => {
    // Cleanup
    application.stop()
    document.body.innerHTML = ""
    jest.clearAllMocks()
  })

  describe("Connection Management", () => {
    test("initializes with correct default values", () => {
      expect(controller.sessionIdValue).toBe(123)
      expect(controller.activeValue).toBe(true)
      expect(controller.connectionStateValue).toBe("disconnected")
      expect(controller.retryCountValue).toBe(0)
      expect(controller.maxRetriesValue).toBe(5)
    })

    test("subscribes to channel when active", () => {
      expect(mockConsumer.subscriptions.create).toHaveBeenCalledWith(
        expect.objectContaining({
          channel: "SyncStatusChannel",
          session_id: 123
        }),
        expect.any(Object)
      )
    })

    test("handles successful connection", () => {
      const callbacks = mockConsumer.subscriptions.create.mock.calls[0][1]
      callbacks.connected()

      expect(controller.connectionStateValue).toBe("connected")
      expect(controller.retryCountValue).toBe(0)
    })

    test("handles disconnection and schedules reconnect", () => {
      jest.useFakeTimers()
      const callbacks = mockConsumer.subscriptions.create.mock.calls[0][1]
      
      callbacks.disconnected()

      expect(controller.connectionStateValue).toBe("disconnected")
      expect(setTimeout).toHaveBeenCalled()
      
      jest.useRealTimers()
    })

    test("handles rejection properly", () => {
      const callbacks = mockConsumer.subscriptions.create.mock.calls[0][1]
      callbacks.rejected()

      expect(controller.connectionStateValue).toBe("rejected")
      expect(controller.retryButtonTarget.classList.contains('hidden')).toBe(false)
    })
  })

  describe("Exponential Backoff", () => {
    test("calculates backoff delay correctly", () => {
      controller.retryCountValue = 0
      const delay1 = controller.calculateBackoffDelay()
      expect(delay1).toBeGreaterThanOrEqual(1000)
      expect(delay1).toBeLessThanOrEqual(2000)

      controller.retryCountValue = 2
      const delay2 = controller.calculateBackoffDelay()
      expect(delay2).toBeGreaterThanOrEqual(4000)
      expect(delay2).toBeLessThanOrEqual(5000)

      controller.retryCountValue = 10
      const delay3 = controller.calculateBackoffDelay()
      expect(delay3).toBeLessThanOrEqual(30000) // Max 30 seconds
    })

    test("stops retrying after max attempts", () => {
      controller.retryCountValue = 5
      controller.maxRetriesValue = 5
      
      controller.scheduleReconnect()

      expect(controller.retryButtonTarget.classList.contains('hidden')).toBe(false)
      expect(setTimeout).not.toHaveBeenCalled()
    })

    test("manual retry resets retry count", () => {
      controller.retryCountValue = 3
      controller.manualRetry()

      expect(controller.retryCountValue).toBe(0)
      expect(mockConsumer.subscriptions.create).toHaveBeenCalled()
    })
  })

  describe("Visibility Handling", () => {
    test("pauses updates when tab becomes hidden", () => {
      const callbacks = mockConsumer.subscriptions.create.mock.calls[0][1]
      callbacks.connected()

      Object.defineProperty(document, 'hidden', {
        value: true,
        writable: true
      })

      document.dispatchEvent(new Event('visibilitychange'))

      expect(controller.isPaused).toBe(true)
      expect(mockSubscription.perform).toHaveBeenCalledWith('pause_updates')
    })

    test("resumes updates when tab becomes visible", () => {
      controller.isPaused = true
      const callbacks = mockConsumer.subscriptions.create.mock.calls[0][1]
      callbacks.connected()

      Object.defineProperty(document, 'hidden', {
        value: false,
        writable: true
      })

      document.dispatchEvent(new Event('visibilitychange'))

      expect(controller.isPaused).toBe(false)
      expect(mockSubscription.perform).toHaveBeenCalledWith('resume_updates')
      expect(mockSubscription.perform).toHaveBeenCalledWith('request_status')
    })
  })

  describe("Network Monitoring", () => {
    test("handles offline event", () => {
      window.dispatchEvent(new Event('offline'))

      expect(controller.connectionStateValue).toBe("offline")
      expect(controller.isPaused).toBe(true)
    })

    test("handles online event and attempts reconnection", () => {
      jest.useFakeTimers()
      
      window.dispatchEvent(new Event('online'))

      expect(controller.connectionStateValue).toBe("reconnecting")
      expect(controller.retryCountValue).toBe(0)
      expect(controller.isPaused).toBe(false)
      expect(setTimeout).toHaveBeenCalled()
      
      jest.useRealTimers()
    })
  })

  describe("State Caching", () => {
    test("caches state updates", () => {
      const data = {
        type: 'progress_update',
        progress_percentage: 50,
        processed_emails: 100
      }

      controller.cacheState(data)

      expect(sessionStorage.setItem).toHaveBeenCalledWith(
        'sync_state_123',
        expect.stringContaining('"progress_percentage":50')
      )
    })

    test("loads cached state if recent", () => {
      const cachedData = {
        type: 'progress_update',
        progress_percentage: 75,
        timestamp: Date.now() - 60000 // 1 minute old
      }

      sessionStorage.getItem.mockReturnValue(JSON.stringify(cachedData))
      
      controller.loadCachedState()

      expect(controller.progressPercentageTarget.textContent).toBe('75%')
    })

    test("ignores stale cached state", () => {
      const cachedData = {
        type: 'progress_update',
        progress_percentage: 75,
        timestamp: Date.now() - 400000 // Over 5 minutes old
      }

      sessionStorage.getItem.mockReturnValue(JSON.stringify(cachedData))
      
      controller.loadCachedState()

      expect(sessionStorage.removeItem).toHaveBeenCalledWith('sync_state_123')
      expect(controller.progressPercentageTarget.textContent).toBe('0%')
    })

    test("clears cache on completion", (done) => {
      controller.handleCompletion({
        processed_emails: 500,
        detected_expenses: 25
      })

      expect(controller.isCompleted).toBe(true)

      setTimeout(() => {
        expect(sessionStorage.removeItem).toHaveBeenCalledWith('sync_state_123')
        done()
      }, 2100)
    })
  })

  describe("Update Throttling", () => {
    test("throttles rapid updates", (done) => {
      jest.useFakeTimers()

      // Send multiple rapid updates
      for (let i = 0; i < 10; i++) {
        controller.handleUpdate({
          type: 'progress_update',
          progress_percentage: i * 10
        })
      }

      expect(controller.updateQueue.length).toBe(10)

      // Fast-forward timers
      jest.advanceTimersByTime(100)

      // Should have processed all updates
      setTimeout(() => {
        expect(controller.updateQueue.length).toBe(0)
        expect(controller.progressPercentageTarget.textContent).toBe('90%')
        done()
      }, 0)

      jest.useRealTimers()
    })

    test("skips updates when paused", () => {
      controller.isPaused = true

      controller.handleUpdate({
        type: 'progress_update',
        progress_percentage: 50
      })

      expect(controller.progressPercentageTarget.textContent).toBe('0%')
    })
  })

  describe("Memory Leak Prevention", () => {
    test("cleans up all resources on disconnect", () => {
      jest.useFakeTimers()

      // Setup some state
      controller.reconnectTimer = setTimeout(() => {}, 1000)
      controller.updateThrottleTimer = setTimeout(() => {}, 100)

      // Disconnect
      controller.disconnect()

      expect(controller.subscription).toBeNull()
      expect(controller.consumer).toBeNull()
      expect(controller.reconnectTimer).toBeNull()
      expect(controller.updateThrottleTimer).toBeNull()
      expect(mockSubscription.unsubscribe).toHaveBeenCalled()
      expect(mockConsumer.disconnect).toHaveBeenCalled()

      jest.useRealTimers()
    })

    test("removes event listeners on disconnect", () => {
      const removeEventListenerSpy = jest.spyOn(document, 'removeEventListener')
      const windowRemoveEventListenerSpy = jest.spyOn(window, 'removeEventListener')

      controller.disconnect()

      expect(removeEventListenerSpy).toHaveBeenCalledWith('visibilitychange', expect.any(Function))
      expect(windowRemoveEventListenerSpy).toHaveBeenCalledWith('online', expect.any(Function))
      expect(windowRemoveEventListenerSpy).toHaveBeenCalledWith('offline', expect.any(Function))
    })
  })

  describe("Progress Updates", () => {
    test("updates progress bar correctly", () => {
      controller.updateProgress({
        progress_percentage: 65,
        processed_emails: 130,
        detected_expenses: 15,
        time_remaining: "2 minutos"
      })

      expect(controller.progressBarTarget.style.width).toBe('65%')
      expect(controller.progressPercentageTarget.textContent).toBe('65%')
      expect(controller.processedCountTarget.textContent).toBe('130')
      expect(controller.detectedCountTarget.textContent).toBe('15')
      expect(controller.timeRemainingTarget.textContent).toBe('2 minutos')
    })

    test("handles completion correctly", () => {
      controller.handleCompletion({
        processed_emails: 500,
        detected_expenses: 25
      })

      expect(controller.progressBarTarget.style.width).toBe('100%')
      expect(controller.progressPercentageTarget.textContent).toBe('100%')
      expect(controller.processedCountTarget.textContent).toBe('500')
      expect(controller.detectedCountTarget.textContent).toBe('25')
    })

    test("handles failure correctly", () => {
      controller.handleFailure({
        error: "Connection timeout"
      })

      expect(controller.progressBarTarget.classList.contains('bg-rose-600')).toBe(true)
      expect(controller.progressBarTarget.classList.contains('bg-teal-700')).toBe(false)
    })
  })

  describe("Debug Logging", () => {
    test("logs when debug is enabled", () => {
      controller.debugValue = true

      controller.log("info", "Test message", { data: "test" })

      expect(console.info).toHaveBeenCalledWith(
        expect.stringContaining("SyncWidget:"),
        "Test message",
        { data: "test" }
      )
    })

    test("does not log when debug is disabled", () => {
      controller.debugValue = false
      element.dataset.debug = "false"

      controller.log("info", "Test message")

      expect(console.info).not.toHaveBeenCalled()
    })

    test("sends errors to server in production", () => {
      global.fetch = jest.fn().mockResolvedValue({ ok: true })
      window.Rails = { env: 'production' }
      controller.debugValue = true

      controller.log("error", "Critical error", { code: 500 })

      expect(fetch).toHaveBeenCalledWith(
        '/api/client_errors',
        expect.objectContaining({
          method: 'POST',
          headers: expect.objectContaining({
            'Content-Type': 'application/json'
          })
        })
      )
    })
  })

  describe("Connection Status UI", () => {
    test("updates connection status display", () => {
      controller.updateConnectionStatus("Connecting...")

      expect(controller.connectionStatusTarget.textContent).toBe("Connecting...")
    })

    test("applies correct color classes for status", () => {
      controller.connectionStateValue = "connected"
      controller.updateConnectionStatus("Connected")

      expect(controller.connectionStatusTarget.classList.contains('text-emerald-600')).toBe(true)

      controller.connectionStateValue = "error"
      controller.updateConnectionStatus("Error")

      expect(controller.connectionStatusTarget.classList.contains('text-rose-600')).toBe(true)
    })
  })
})