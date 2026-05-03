/**
 * spec/javascript/controllers/queue_monitor_controller_xss_spec.js
 *
 * XSS hardening specs for H4: queue_monitor_controller — lines 250, 283, 330 (PER-543)
 *
 * NOTE: No JS test runner is configured (no package.json / Jest).
 * These specs are ready to run once Jest + jsdom are set up.
 */

import { Application } from "@hotwired/stimulus"
import QueueMonitorController from "../../../app/javascript/controllers/queue_monitor_controller"

// Stub ActionCable so the controller can connect in jsdom
jest.mock("@rails/actioncable", () => ({
  createConsumer: () => ({
    subscriptions: {
      create: () => ({ unsubscribe: jest.fn() })
    }
  })
}))

describe("QueueMonitorController — XSS hardening (PER-543)", () => {
  const XSS_PAYLOAD = '<script>alert(1)</script>'
  let application
  let element
  let controller

  beforeEach(() => {
    document.body.innerHTML = `
      <div data-controller="queue-monitor"
           data-queue-monitor-api-endpoint-value="/api/queue/status.json"
           data-queue-monitor-refresh-interval-value="999999">
        <div data-queue-monitor-target="activeJobsSection" style="display:none"></div>
        <div data-queue-monitor-target="activeJobsList"></div>
        <div data-queue-monitor-target="failedJobsSection" style="display:none"></div>
        <div data-queue-monitor-target="failedJobsList"></div>
        <div data-queue-monitor-target="queueBreakdown" style="display:none"></div>
        <div data-queue-monitor-target="queueList"></div>
        <span data-queue-monitor-target="healthIndicator"></span>
        <span data-queue-monitor-target="healthDot"></span>
        <span data-queue-monitor-target="healthText"></span>
        <span data-queue-monitor-target="pendingCount">0</span>
        <span data-queue-monitor-target="processingCount">0</span>
        <span data-queue-monitor-target="completedCount">0</span>
        <span data-queue-monitor-target="failedCount">0</span>
        <div data-queue-monitor-target="queueDepthBar"></div>
        <span data-queue-monitor-target="queueDepthMax">0</span>
        <span data-queue-monitor-target="processingRate">0</span>
        <span data-queue-monitor-target="estimatedTime">-</span>
        <button data-queue-monitor-target="pauseButton"></button>
        <span data-queue-monitor-target="pauseIcon"></span>
        <span data-queue-monitor-target="pauseText"></span>
        <span data-queue-monitor-target="workerCount">0</span>
        <span data-queue-monitor-target="utilization">0%</span>
        <span data-queue-monitor-target="lastUpdate">-</span>
        <button data-queue-monitor-target="retryAllButton"></button>
        <span data-queue-monitor-target="noFailedText"></span>
      </div>
    `

    application = Application.start()
    application.register("queue-monitor", QueueMonitorController)

    element = document.querySelector('[data-controller="queue-monitor"]')
    controller = application.getControllerForElementAndIdentifier(element, "queue-monitor")
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
  })

  describe("updateActiveJobs — H4 line 250", () => {
    it("renders XSS payload in class_name as text, not as DOM elements", () => {
      controller.updateActiveJobs([{
        class_name: XSS_PAYLOAD,
        queue_name: 'default',
        priority: 1,
        duration: null,
        process_info: null
      }])

      const list = document.querySelector('[data-queue-monitor-target="activeJobsList"]')
      expect(list.textContent).toContain(XSS_PAYLOAD)
      expect(document.querySelector('script')).toBeNull()
    })

    it("renders XSS payload in queue_name as text", () => {
      controller.updateActiveJobs([{
        class_name: 'SomeJob',
        queue_name: XSS_PAYLOAD,
        priority: 1,
        duration: null,
        process_info: null
      }])

      const list = document.querySelector('[data-queue-monitor-target="activeJobsList"]')
      expect(list.textContent).toContain(XSS_PAYLOAD)
      expect(document.querySelector('script')).toBeNull()
    })

    it("renders XSS payload in process_info as text", () => {
      controller.updateActiveJobs([{
        class_name: 'SomeJob',
        queue_name: 'default',
        priority: 1,
        duration: null,
        process_info: { pid: XSS_PAYLOAD, hostname: 'host' }
      }])

      expect(document.querySelector('script')).toBeNull()
    })
  })

  describe("updateFailedJobs — H4 line 283", () => {
    it("renders XSS payload in error message as text", () => {
      controller.updateFailedJobs([{
        id: 1,
        class_name: 'SomeJob',
        queue_name: 'default',
        error: XSS_PAYLOAD,
        created_at: new Date().toISOString()
      }])

      const list = document.querySelector('[data-queue-monitor-target="failedJobsList"]')
      expect(list.textContent).toContain(XSS_PAYLOAD)
      expect(document.querySelector('script')).toBeNull()
    })

    it("renders XSS payload in class_name as text in failed job", () => {
      controller.updateFailedJobs([{
        id: 1,
        class_name: XSS_PAYLOAD,
        queue_name: 'default',
        error: 'some error',
        created_at: new Date().toISOString()
      }])

      expect(document.querySelector('script')).toBeNull()
    })

    it("sets data-job-id attribute safely, not via innerHTML", () => {
      const jobId = 'safe-id'
      controller.updateFailedJobs([{
        id: jobId,
        class_name: 'Job',
        queue_name: 'default',
        error: 'error',
        created_at: new Date().toISOString()
      }])

      const list = document.querySelector('[data-queue-monitor-target="failedJobsList"]')
      const buttons = list.querySelectorAll('button[data-job-id]')
      buttons.forEach(btn => {
        expect(btn.getAttribute('data-job-id')).toBe(jobId)
      })
    })
  })

  describe("updateQueueBreakdown — H4 line 330", () => {
    it("renders XSS payload in queue name as text", () => {
      controller.updateQueueBreakdown({ [XSS_PAYLOAD]: 5 })

      const list = document.querySelector('[data-queue-monitor-target="queueList"]')
      expect(list.textContent).toContain(XSS_PAYLOAD)
      expect(document.querySelector('script')).toBeNull()
    })

    it("renders queue count as text", () => {
      controller.updateQueueBreakdown({ 'critical': 42 })

      const list = document.querySelector('[data-queue-monitor-target="queueList"]')
      expect(list.textContent).toContain('42')
      expect(list.textContent).toContain('critical')
    })
  })
})
