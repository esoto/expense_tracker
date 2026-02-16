import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from 'chart.js'

Chart.register(...registerables)

export default class extends Controller {
  static values = { url: String }
  
  chart = null
  currentInterval = 'daily'

  connect() {
    this.loadChartData()
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }

  async loadChartData(interval = 'daily') {
    this.currentInterval = interval
    
    try {
      const params = new URLSearchParams(window.location.search)
      params.append('interval', interval)
      
      const response = await fetch(`${this.urlValue}?${params.toString()}`, {
        headers: {
          'Accept': 'application/json'
        }
      })
      
      if (!response.ok) throw new Error('Failed to load trend data')
      
      const data = await response.json()
      this.renderChart(data)
    } catch (error) {
      console.error('Error loading trend data:', error)
      this.showError()
    }
  }

  renderChart(data) {
    const ctx = this.element.getContext('2d')
    
    if (this.chart) {
      this.chart.destroy()
    }

    const labels = data.map(d => d.date)
    
    this.chart = new Chart(ctx, {
      type: 'line',
      data: {
        labels: labels,
        datasets: [
          {
            label: 'Precisión %',
            data: data.map(d => d.accuracy),
            borderColor: '#0F766E',
            backgroundColor: 'rgba(15, 118, 110, 0.1)',
            tension: 0.3,
            yAxisID: 'y'
          },
          {
            label: 'Uso Total',
            data: data.map(d => d.total),
            borderColor: '#D97706',
            backgroundColor: 'rgba(217, 119, 6, 0.1)',
            tension: 0.3,
            yAxisID: 'y1'
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: {
          mode: 'index',
          intersect: false
        },
        plugins: {
          legend: {
            position: 'top'
          },
          tooltip: {
            callbacks: {
              afterLabel: function(context) {
                if (context.dataset.label === 'Accuracy %') {
                  const dataIndex = context.dataIndex
                  const item = data[dataIndex]
                  return `Accepted: ${item.accepted}\nRejected: ${item.rejected}\nCorrected: ${item.corrected}`
                }
                return ''
              }
            }
          }
        },
        scales: {
          x: {
            grid: {
              display: false
            }
          },
          y: {
            type: 'linear',
            display: true,
            position: 'left',
            title: {
              display: true,
              text: 'Precisión %'
            },
            min: 0,
            max: 100
          },
          y1: {
            type: 'linear',
            display: true,
            position: 'right',
            title: {
              display: true,
              text: 'Uso Total'
            },
            grid: {
              drawOnChartArea: false
            }
          }
        }
      }
    })
  }

  showError() {
    this.element.innerHTML = `
      <div class="flex items-center justify-center h-full">
        <div class="text-center">
          <p class="text-slate-500">Unable to load trend data</p>
          <button class="mt-2 px-4 py-2 bg-teal-700 text-white rounded-lg text-sm"
                  data-action="click->pattern-trend-chart#retry">
            Retry
          </button>
        </div>
      </div>
    `
  }

  retry() {
    this.element.innerHTML = ''
    this.loadChartData(this.currentInterval)
  }
}