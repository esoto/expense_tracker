import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from 'chart.js'

Chart.register(...registerables)

export default class extends Controller {
  static targets = ["canvas"]
  static values = { 
    type: String,
    data: Object,
    options: Object
  }

  connect() {
    this.initializeChart()
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }

  initializeChart() {
    const ctx = this.canvasTarget.getContext('2d')
    
    const chartData = this.prepareChartData()
    const chartOptions = this.prepareChartOptions()

    this.chart = new Chart(ctx, {
      type: this.typeValue || 'line',
      data: chartData,
      options: chartOptions
    })
  }

  prepareChartData() {
    const rawData = this.dataValue
    
    // If data is already in Chart.js format, return it
    if (rawData.labels && rawData.datasets) {
      return rawData
    }

    // Convert object data to Chart.js format
    const labels = Object.keys(rawData)
    const values = Object.values(rawData)

    return {
      labels: labels.map(label => this.formatLabel(label)),
      datasets: [{
        label: 'Valor',
        data: values,
        borderColor: 'rgb(15, 118, 110)', // teal-700
        backgroundColor: 'rgba(15, 118, 110, 0.1)',
        tension: 0.3,
        fill: true
      }]
    }
  }

  prepareChartOptions() {
    const defaultOptions = {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          display: false
        },
        tooltip: {
          backgroundColor: 'rgba(30, 41, 59, 0.9)', // slate-800
          titleColor: '#fff',
          bodyColor: '#fff',
          borderColor: 'rgba(203, 213, 225, 0.2)', // slate-300
          borderWidth: 1,
          padding: 12,
          displayColors: false,
          callbacks: {
            label: (context) => {
              let label = context.dataset.label || ''
              if (label) {
                label += ': '
              }
              
              // Format based on data type
              if (context.parsed.y !== null) {
                if (this.typeValue === 'percentage') {
                  label += context.parsed.y.toFixed(2) + '%'
                } else if (this.typeValue === 'duration') {
                  label += this.formatDuration(context.parsed.y)
                } else {
                  label += context.parsed.y.toLocaleString()
                }
              }
              return label
            }
          }
        }
      },
      scales: {
        x: {
          grid: {
            display: false
          },
          ticks: {
            color: 'rgb(100, 116, 139)', // slate-500
            font: {
              size: 11
            }
          }
        },
        y: {
          grid: {
            color: 'rgba(203, 213, 225, 0.2)', // slate-300
            drawBorder: false
          },
          ticks: {
            color: 'rgb(100, 116, 139)', // slate-500
            font: {
              size: 11
            }
          }
        }
      }
    }

    return this.optionsValue || defaultOptions
  }

  formatLabel(label) {
    // Format timestamp labels
    if (label.match(/^\d{4}-\d{2}-\d{2}/)) {
      const date = new Date(label)
      const now = new Date()
      const diffDays = Math.floor((now - date) / (1000 * 60 * 60 * 24))
      
      if (diffDays === 0) {
        return date.toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit' })
      } else if (diffDays < 7) {
        return date.toLocaleDateString('es', { weekday: 'short', hour: '2-digit' })
      } else {
        return date.toLocaleDateString('es', { month: 'short', day: 'numeric' })
      }
    }
    
    return label
  }

  formatDuration(milliseconds) {
    if (milliseconds < 1000) {
      return `${Math.round(milliseconds)} ms`
    } else if (milliseconds < 60000) {
      return `${(milliseconds / 1000).toFixed(2)} s`
    } else {
      return `${(milliseconds / 60000).toFixed(2)} min`
    }
  }

  updateChart(newData) {
    if (!this.chart) return

    const chartData = this.prepareChartData(newData)
    this.chart.data = chartData
    this.chart.update('active')
  }
}