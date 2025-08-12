import { Controller } from "@hotwired/stimulus"

// Animated Metric Controller
// Provides smooth number animations and trend indicators for dashboard metrics
// Handles currency formatting and percentage changes with visual feedback
export default class extends Controller {
  static targets = ["value", "trend", "sparkline", "container"]
  static values = {
    from: Number,
    to: Number,
    duration: { type: Number, default: 1000 },
    decimals: { type: Number, default: 0 },
    prefix: { type: String, default: "" },
    suffix: { type: String, default: "" },
    trendValue: Number,
    isIncrease: Boolean
  }

  connect() {
    // Initialize with animation
    this.animateValue()
    
    // Animate trend if present
    if (this.hasTrendTarget && this.hasTrendValueValue) {
      this.animateTrend()
    }

    // Create sparkline if target exists
    if (this.hasSparklineTarget) {
      this.drawSparkline()
    }

    // Add hover effect
    this.addHoverEffects()
  }

  animateValue() {
    if (!this.hasValueTarget) return

    const start = this.hasFromValue ? this.fromValue : 0
    const end = this.hasToValue ? this.toValue : parseFloat(this.valueTarget.textContent.replace(/[^0-9.-]/g, '')) || 0
    const duration = this.durationValue
    const startTime = performance.now()

    const animate = (currentTime) => {
      const elapsed = currentTime - startTime
      const progress = Math.min(elapsed / duration, 1)
      
      // Easing function for smooth animation
      const easeOutQuart = 1 - Math.pow(1 - progress, 4)
      const current = start + (end - start) * easeOutQuart

      // Format and display the number
      this.valueTarget.textContent = this.formatNumber(current)

      if (progress < 1) {
        requestAnimationFrame(animate)
      } else {
        // Final value to ensure accuracy
        this.valueTarget.textContent = this.formatNumber(end)
        
        // Add completion effect
        this.pulseEffect()
      }
    }

    requestAnimationFrame(animate)
  }

  animateTrend() {
    const trendElement = this.trendTarget
    const value = this.trendValueValue
    const isIncrease = this.hasIsIncreaseValue ? this.isIncreaseValue : value > 0

    // Set initial state
    trendElement.style.opacity = '0'
    trendElement.style.transform = 'translateY(10px)'

    // Animate in
    setTimeout(() => {
      trendElement.style.transition = 'all 0.5s ease-out'
      trendElement.style.opacity = '1'
      trendElement.style.transform = 'translateY(0)'

      // Update content with arrow
      const arrow = isIncrease ? '↑' : '↓'
      const sign = value > 0 ? '+' : ''
      const color = isIncrease ? 'text-rose-600' : 'text-emerald-600'
      
      trendElement.innerHTML = `
        <span class="${color} font-semibold">
          ${arrow} ${sign}${Math.abs(value).toFixed(1)}%
        </span>
        <span class="text-slate-500 text-sm ml-2">vs mes anterior</span>
      `
    }, 100)
  }

  drawSparkline() {
    const canvas = document.createElement('canvas')
    canvas.width = 120
    canvas.height = 30
    canvas.className = 'mt-2'
    
    const ctx = canvas.getContext('2d')
    
    // Generate sample data (in production, this would come from the backend)
    const data = this.generateSparklineData()
    
    // Calculate dimensions
    const padding = 2
    const width = canvas.width - (padding * 2)
    const height = canvas.height - (padding * 2)
    const max = Math.max(...data)
    const min = Math.min(...data)
    const range = max - min || 1
    
    // Draw sparkline
    ctx.beginPath()
    ctx.strokeStyle = '#0F766E'
    ctx.lineWidth = 2
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    
    data.forEach((value, index) => {
      const x = padding + (index / (data.length - 1)) * width
      const y = padding + height - ((value - min) / range) * height
      
      if (index === 0) {
        ctx.moveTo(x, y)
      } else {
        ctx.lineTo(x, y)
      }
    })
    
    ctx.stroke()
    
    // Add gradient fill
    const gradient = ctx.createLinearGradient(0, 0, 0, canvas.height)
    gradient.addColorStop(0, 'rgba(15, 118, 110, 0.2)')
    gradient.addColorStop(1, 'rgba(15, 118, 110, 0.0)')
    
    ctx.lineTo(canvas.width - padding, canvas.height - padding)
    ctx.lineTo(padding, canvas.height - padding)
    ctx.closePath()
    ctx.fillStyle = gradient
    ctx.fill()
    
    this.sparklineTarget.appendChild(canvas)
  }

  generateSparklineData() {
    // Generate 7 data points for the sparkline
    const points = []
    let lastValue = 50
    
    for (let i = 0; i < 7; i++) {
      const change = (Math.random() - 0.5) * 20
      lastValue = Math.max(10, Math.min(90, lastValue + change))
      points.push(lastValue)
    }
    
    return points
  }

  formatNumber(value) {
    const formatted = new Intl.NumberFormat('es-CR', {
      minimumFractionDigits: this.decimalsValue,
      maximumFractionDigits: this.decimalsValue
    }).format(value)
    
    return `${this.prefixValue}${formatted}${this.suffixValue}`
  }

  pulseEffect() {
    if (!this.hasContainerTarget) return
    
    this.containerTarget.classList.add('animate-pulse-once')
    setTimeout(() => {
      this.containerTarget.classList.remove('animate-pulse-once')
    }, 600)
  }

  addHoverEffects() {
    if (!this.hasContainerTarget) return
    
    this.containerTarget.addEventListener('mouseenter', () => {
      this.containerTarget.style.transform = 'translateY(-2px)'
      this.containerTarget.style.boxShadow = '0 10px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04)'
    })
    
    this.containerTarget.addEventListener('mouseleave', () => {
      this.containerTarget.style.transform = 'translateY(0)'
      this.containerTarget.style.boxShadow = ''
    })
  }

  // Public method to update the value (can be called from other controllers or Turbo)
  updateValue(newValue) {
    const oldValue = this.hasToValue ? this.toValue : parseFloat(this.valueTarget.textContent.replace(/[^0-9.-]/g, '')) || 0
    this.fromValue = oldValue
    this.toValue = newValue
    this.animateValue()
  }
}