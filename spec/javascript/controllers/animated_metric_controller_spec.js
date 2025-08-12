import { Application } from "@hotwired/stimulus"
import AnimatedMetricController from "animated_metric_controller"

describe("AnimatedMetricController", () => {
  let application
  let element

  beforeEach(() => {
    // Set up DOM
    document.body.innerHTML = `
      <div data-controller="animated-metric"
           data-animated-metric-to-value="50000"
           data-animated-metric-prefix-value="₡"
           data-animated-metric-decimals-value="0"
           data-animated-metric-duration-value="500"
           data-animated-metric-trend-value-value="12.5"
           data-animated-metric-is-increase-value="true">
        <div data-animated-metric-target="container">
          <span data-animated-metric-target="value">0</span>
          <div data-animated-metric-target="trend"></div>
          <div data-animated-metric-target="sparkline"></div>
        </div>
      </div>
    `

    element = document.querySelector('[data-controller="animated-metric"]')
    
    // Set up Stimulus
    application = Application.start()
    application.register("animated-metric", AnimatedMetricController)
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ''
  })

  describe("connect", () => {
    it("initializes and starts animation", (done) => {
      const valueTarget = element.querySelector('[data-animated-metric-target="value"]')
      
      // Wait for animation to complete
      setTimeout(() => {
        expect(valueTarget.textContent).toContain("50")
        expect(valueTarget.textContent).toContain("₡")
        done()
      }, 600)
    })

    it("animates trend indicator when present", (done) => {
      const trendTarget = element.querySelector('[data-animated-metric-target="trend"]')
      
      setTimeout(() => {
        expect(trendTarget.innerHTML).toContain("12.5%")
        expect(trendTarget.innerHTML).toContain("↑")
        expect(trendTarget.innerHTML).toContain("text-rose-600")
        done()
      }, 200)
    })

    it("creates sparkline when target exists", (done) => {
      const sparklineTarget = element.querySelector('[data-animated-metric-target="sparkline"]')
      
      setTimeout(() => {
        const canvas = sparklineTarget.querySelector('canvas')
        expect(canvas).toBeTruthy()
        expect(canvas.width).toBe(120)
        expect(canvas.height).toBe(30)
        done()
      }, 100)
    })
  })

  describe("formatNumber", () => {
    it("formats numbers with prefix and suffix", () => {
      const controller = application.getControllerForElementAndIdentifier(element, "animated-metric")
      controller.prefixValue = "₡"
      controller.suffixValue = ""
      controller.decimalsValue = 0
      
      const formatted = controller.formatNumber(12500)
      expect(formatted).toContain("₡")
      expect(formatted).toContain("12")
      expect(formatted).toContain("500")
    })
  })

  describe("updateValue", () => {
    it("updates value with animation from current to new", (done) => {
      const controller = application.getControllerForElementAndIdentifier(element, "animated-metric")
      const valueTarget = element.querySelector('[data-animated-metric-target="value"]')
      
      // Set initial value
      valueTarget.textContent = "₡10,000"
      
      // Update to new value
      controller.updateValue(25000)
      
      // Check after animation
      setTimeout(() => {
        expect(valueTarget.textContent).toContain("25")
        done()
      }, 600)
    })
  })

  describe("hover effects", () => {
    it("adds transform on hover", () => {
      const container = element.querySelector('[data-animated-metric-target="container"]')
      
      // Trigger mouseenter
      const mouseEnterEvent = new MouseEvent('mouseenter')
      container.dispatchEvent(mouseEnterEvent)
      
      expect(container.style.transform).toBe('translateY(-2px)')
      
      // Trigger mouseleave
      const mouseLeaveEvent = new MouseEvent('mouseleave')
      container.dispatchEvent(mouseLeaveEvent)
      
      expect(container.style.transform).toBe('translateY(0)')
    })
  })

  describe("trend animation", () => {
    it("shows decrease indicator for negative trends", () => {
      element.setAttribute('data-animated-metric-trend-value-value', '-8.5')
      element.setAttribute('data-animated-metric-is-increase-value', 'false')
      
      const controller = application.getControllerForElementAndIdentifier(element, "animated-metric")
      controller.animateTrend()
      
      setTimeout(() => {
        const trendTarget = element.querySelector('[data-animated-metric-target="trend"]')
        expect(trendTarget.innerHTML).toContain("↓")
        expect(trendTarget.innerHTML).toContain("text-emerald-600")
        expect(trendTarget.innerHTML).toContain("8.5%")
      }, 200)
    })
  })
})