import { Controller } from "@hotwired/stimulus"

// Sparkline Controller for Task 2.3.2
// Renders lightweight 7-day trend charts in tooltips
// Optimized for performance with < 50ms render time
export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    data: Array,
    min: Number,
    max: Number,
    average: Number,
    color: { type: String, default: "#0F766E" }, // teal-700
    highlightColor: { type: String, default: "#FB7185" }, // rose-400
    width: { type: Number, default: 200 },
    height: { type: Number, default: 60 },
    showLabels: { type: Boolean, default: false },
    showGrid: { type: Boolean, default: false }
  }

  connect() {
    this.chart = null
    this.renderTimeout = null
    
    // Wait for Chart.js to be available from CDN
    this.waitForChartJS().then(() => {
      // Only render if we have data
      if (this.hasDataValue && this.dataValue.length > 0) {
        this.renderSparkline()
      }
    }).catch(error => {
      console.warn('Chart.js not available, falling back to canvas rendering:', error)
      // Fall back to lightweight canvas implementation
      if (this.hasDataValue && this.dataValue.length > 0) {
        this.renderLightweightSparkline()
      }
    })
  }

  disconnect() {
    // Clear any pending timeouts
    if (this.renderTimeout) {
      clearTimeout(this.renderTimeout)
      this.renderTimeout = null
    }
    
    // Clean up chart instance properly to prevent memory leaks
    if (this.chart) {
      try {
        this.chart.destroy()
      } catch (error) {
        console.warn('Error destroying chart:', error)
      }
      this.chart = null
    }
    
    // Clear canvas if it exists
    if (this.hasCanvasTarget) {
      const ctx = this.canvasTarget.getContext('2d')
      ctx.clearRect(0, 0, this.canvasTarget.width, this.canvasTarget.height)
    }
  }
  
  // Wait for Chart.js to be loaded from CDN
  waitForChartJS(maxAttempts = 20, interval = 100) {
    return new Promise((resolve, reject) => {
      let attempts = 0
      
      const checkChart = () => {
        attempts++
        
        // Check if Chart is available globally (from CDN)
        if (typeof window.Chart !== 'undefined') {
          resolve(window.Chart)
        } else if (attempts >= maxAttempts) {
          reject(new Error('Chart.js not loaded after maximum attempts'))
        } else {
          setTimeout(checkChart, interval)
        }
      }
      
      checkChart()
    })
  }

  renderSparkline() {
    const startTime = performance.now()
    
    try {
      // Get Chart.js constructor (from CDN global)
      const ChartJS = window.Chart
      
      if (!ChartJS) {
        console.warn('Chart.js not available, using lightweight implementation')
        this.renderLightweightSparkline()
        return
      }
      
      // Create canvas if it doesn't exist
      if (!this.hasCanvasTarget) {
        this.createCanvas()
      }

      const ctx = this.canvasTarget.getContext('2d')
      
      // Destroy existing chart if any
      if (this.chart) {
        this.chart.destroy()
        this.chart = null
      }
      
      // Prepare data for Chart.js
      const chartData = this.prepareChartData()
      
      // Create the sparkline chart with error handling
      this.chart = new ChartJS(ctx, {
        type: 'line',
        data: chartData,
        options: this.getChartOptions()
      })

      // Log performance
      const renderTime = performance.now() - startTime
      if (renderTime > 50) {
        console.warn(`Sparkline render exceeded 50ms target: ${renderTime.toFixed(2)}ms`)
      }
    } catch (error) {
      console.error('Error rendering sparkline chart:', error)
      // Fall back to lightweight implementation
      this.renderLightweightSparkline()
    }
  }

  createCanvas() {
    const canvas = document.createElement('canvas')
    canvas.width = this.widthValue
    canvas.height = this.heightValue
    canvas.classList.add('sparkline-chart')
    canvas.dataset.sparklineTarget = 'canvas'
    this.element.appendChild(canvas)
  }

  prepareChartData() {
    // Extract amounts from data (expecting array of {date, amount} objects)
    const amounts = this.dataValue.map(d => d.amount || 0)
    const labels = this.showLabelsValue ? this.dataValue.map(d => this.formatDate(d.date)) : []
    
    // Find min and max indices for highlighting
    const minIndex = amounts.indexOf(Math.min(...amounts))
    const maxIndex = amounts.indexOf(Math.max(...amounts))
    
    // Create point colors array
    const pointColors = amounts.map((_, index) => {
      if (index === maxIndex) return this.highlightColorValue // Max point in rose
      if (index === minIndex) return '#10B981' // Min point in emerald
      return this.colorValue
    })
    
    return {
      labels: labels,
      datasets: [{
        label: '',
        data: amounts,
        borderColor: this.colorValue,
        backgroundColor: `${this.colorValue}10`, // 10% opacity
        borderWidth: 2,
        fill: true,
        tension: 0.4, // Smooth curves
        pointRadius: amounts.map((_, index) => {
          // Only show points for min/max
          return (index === minIndex || index === maxIndex) ? 3 : 0
        }),
        pointBackgroundColor: pointColors,
        pointBorderColor: pointColors,
        pointHoverRadius: 4
      }]
    }
  }

  getChartOptions() {
    return {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          display: false
        },
        tooltip: {
          enabled: false // Disable Chart.js tooltips as we're in a tooltip already
        }
      },
      scales: {
        x: {
          display: this.showGridValue,
          grid: {
            display: false
          },
          ticks: {
            display: this.showLabelsValue,
            font: {
              size: 9
            },
            color: '#64748B' // slate-600
          }
        },
        y: {
          display: this.showGridValue,
          beginAtZero: true,
          grid: {
            display: this.showGridValue,
            color: '#E2E8F0' // slate-200
          },
          ticks: {
            display: false
          }
        }
      },
      interaction: {
        intersect: false,
        mode: 'index'
      },
      animation: {
        duration: 300 // Fast animation for responsiveness
      },
      elements: {
        line: {
          borderJoinStyle: 'round'
        }
      }
    }
  }

  formatDate(dateString) {
    if (!dateString) return ''
    const date = new Date(dateString)
    return date.toLocaleDateString('es-CR', { day: 'numeric', month: 'short' })
  }

  // Update data dynamically
  updateData(newData) {
    this.dataValue = newData
    
    // Clean up existing chart
    if (this.chart) {
      try {
        this.chart.destroy()
        this.chart = null
      } catch (error) {
        console.warn('Error destroying chart during update:', error)
      }
    }
    
    // Re-render with new data
    if (typeof window.Chart !== 'undefined') {
      this.renderSparkline()
    } else {
      this.renderLightweightSparkline()
    }
  }

  // Draw average line overlay
  drawAverageLine() {
    if (!this.chart || !this.hasAverageValue) return
    
    const ctx = this.canvasTarget.getContext('2d')
    const chartArea = this.chart.chartArea
    const yScale = this.chart.scales.y
    
    // Calculate Y position for average
    const averageY = yScale.getPixelForValue(this.averageValue)
    
    // Draw dashed line
    ctx.save()
    ctx.strokeStyle = '#D97706' // amber-600
    ctx.lineWidth = 1
    ctx.setLineDash([5, 5])
    ctx.beginPath()
    ctx.moveTo(chartArea.left, averageY)
    ctx.lineTo(chartArea.right, averageY)
    ctx.stroke()
    ctx.restore()
  }

  // Pure canvas implementation for ultra-lightweight sparklines
  // Alternative to Chart.js for even better performance
  // Used as fallback when Chart.js is not available
  renderLightweightSparkline() {
    // Ensure we have a canvas
    if (!this.hasCanvasTarget) {
      this.createCanvas()
    }
    
    const canvas = this.canvasTarget
    const ctx = canvas.getContext('2d')
    const data = this.dataValue.map(d => d.amount || 0)
    
    if (data.length === 0) return
    
    // Clear canvas
    ctx.clearRect(0, 0, canvas.width, canvas.height)
    
    // Calculate dimensions
    const padding = 5
    const width = canvas.width - (padding * 2)
    const height = canvas.height - (padding * 2)
    const max = Math.max(...data) || 1
    const min = Math.min(...data) || 0
    const range = max - min || 1
    
    // Draw gradient fill
    const gradient = ctx.createLinearGradient(0, padding, 0, canvas.height - padding)
    gradient.addColorStop(0, `${this.colorValue}20`) // 20% opacity at top
    gradient.addColorStop(1, `${this.colorValue}00`) // 0% opacity at bottom
    
    // Start drawing the path
    ctx.beginPath()
    
    data.forEach((value, index) => {
      const x = padding + (index / (data.length - 1)) * width
      const y = padding + height - ((value - min) / range) * height
      
      if (index === 0) {
        ctx.moveTo(x, y)
      } else {
        // Use quadratic curves for smoothness
        const prevX = padding + ((index - 1) / (data.length - 1)) * width
        const prevY = padding + height - ((data[index - 1] - min) / range) * height
        const cpX = (prevX + x) / 2
        const cpY = (prevY + y) / 2
        ctx.quadraticCurveTo(prevX, prevY, cpX, cpY)
      }
    })
    
    // Complete the fill area
    const lastX = padding + width
    const lastY = padding + height - ((data[data.length - 1] - min) / range) * height
    
    // Store the line path
    const linePath = new Path2D()
    ctx.stroke()
    
    // Fill area under the line
    ctx.lineTo(lastX, canvas.height - padding)
    ctx.lineTo(padding, canvas.height - padding)
    ctx.closePath()
    ctx.fillStyle = gradient
    ctx.fill()
    
    // Draw the line
    ctx.beginPath()
    data.forEach((value, index) => {
      const x = padding + (index / (data.length - 1)) * width
      const y = padding + height - ((value - min) / range) * height
      
      if (index === 0) {
        ctx.moveTo(x, y)
      } else {
        ctx.lineTo(x, y)
      }
    })
    
    ctx.strokeStyle = this.colorValue
    ctx.lineWidth = 2
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    ctx.stroke()
    
    // Draw min/max points
    const minIndex = data.indexOf(Math.min(...data))
    const maxIndex = data.indexOf(Math.max(...data))
    
    // Max point (rose)
    const maxX = padding + (maxIndex / (data.length - 1)) * width
    const maxY = padding + height - ((data[maxIndex] - min) / range) * height
    ctx.beginPath()
    ctx.arc(maxX, maxY, 3, 0, Math.PI * 2)
    ctx.fillStyle = this.highlightColorValue
    ctx.fill()
    
    // Min point (emerald)
    const minX = padding + (minIndex / (data.length - 1)) * width
    const minY = padding + height - ((data[minIndex] - min) / range) * height
    ctx.beginPath()
    ctx.arc(minX, minY, 3, 0, Math.PI * 2)
    ctx.fillStyle = '#10B981'
    ctx.fill()
    
    // Draw average line if provided
    if (this.hasAverageValue) {
      const avgY = padding + height - ((this.averageValue - min) / range) * height
      ctx.save()
      ctx.strokeStyle = '#D97706' // amber-600
      ctx.lineWidth = 1
      ctx.setLineDash([3, 3])
      ctx.beginPath()
      ctx.moveTo(padding, avgY)
      ctx.lineTo(canvas.width - padding, avgY)
      ctx.stroke()
      ctx.restore()
    }
  }
}