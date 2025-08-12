import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from 'chart.js'

Chart.register(...registerables)

export default class extends Controller {
  static values = { url: String }
  
  chart = null

  connect() {
    this.loadHeatmapData()
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }

  async loadHeatmapData() {
    try {
      const params = new URLSearchParams(window.location.search)
      const response = await fetch(`${this.urlValue}?${params.toString()}`, {
        headers: {
          'Accept': 'application/json'
        }
      })
      
      if (!response.ok) throw new Error('Failed to load heatmap data')
      
      const data = await response.json()
      this.renderHeatmap(data)
    } catch (error) {
      console.error('Error loading heatmap data:', error)
      this.showError()
    }
  }

  renderHeatmap(data) {
    // Create a matrix for the heatmap
    const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
    const hours = Array.from({length: 24}, (_, i) => `${i}:00`)
    
    // Find max count for color scaling
    const maxCount = Math.max(...data.map(d => d.count))
    
    // Create the heatmap visualization using a custom implementation
    const container = this.element
    container.innerHTML = ''
    
    const table = document.createElement('div')
    table.className = 'relative'
    
    // Create grid
    const grid = document.createElement('div')
    grid.className = 'grid grid-cols-25 gap-0.5 text-xs'
    
    // Add empty cell for top-left corner
    grid.innerHTML = '<div class="w-8 h-6"></div>'
    
    // Add hour labels
    hours.forEach(hour => {
      const label = document.createElement('div')
      label.className = 'w-8 h-6 flex items-center justify-center text-slate-500'
      label.textContent = hour.split(':')[0]
      grid.appendChild(label)
    })
    
    // Add rows for each day
    days.forEach((day, dayIndex) => {
      // Add day label
      const dayLabel = document.createElement('div')
      dayLabel.className = 'w-16 h-6 flex items-center text-slate-600 font-medium pr-2'
      dayLabel.textContent = day.slice(0, 3)
      grid.appendChild(dayLabel)
      
      // Add cells for each hour
      hours.forEach((hour, hourIndex) => {
        const cellData = data.find(d => d.day === dayIndex && d.hour === hourIndex)
        const count = cellData ? cellData.count : 0
        
        const cell = document.createElement('div')
        cell.className = 'w-8 h-6 rounded cursor-pointer transition-all hover:ring-2 hover:ring-teal-500'
        
        // Calculate color intensity
        const intensity = maxCount > 0 ? count / maxCount : 0
        if (intensity === 0) {
          cell.style.backgroundColor = '#f1f5f9' // slate-100
        } else if (intensity < 0.25) {
          cell.style.backgroundColor = '#99f6e4' // teal-200
        } else if (intensity < 0.5) {
          cell.style.backgroundColor = '#5eead4' // teal-300
        } else if (intensity < 0.75) {
          cell.style.backgroundColor = '#14b8a6' // teal-500
        } else {
          cell.style.backgroundColor = '#0f766e' // teal-700
        }
        
        // Add tooltip
        cell.title = `${day} ${hour}: ${count} patterns used`
        
        grid.appendChild(cell)
      })
    })
    
    container.appendChild(grid)
    
    // Add legend
    const legend = document.createElement('div')
    legend.className = 'flex items-center gap-4 mt-4 text-xs text-slate-600'
    legend.innerHTML = `
      <span>Less</span>
      <div class="flex gap-1">
        <div class="w-4 h-4 rounded" style="background-color: #f1f5f9"></div>
        <div class="w-4 h-4 rounded" style="background-color: #99f6e4"></div>
        <div class="w-4 h-4 rounded" style="background-color: #5eead4"></div>
        <div class="w-4 h-4 rounded" style="background-color: #14b8a6"></div>
        <div class="w-4 h-4 rounded" style="background-color: #0f766e"></div>
      </div>
      <span>More</span>
    `
    container.appendChild(legend)
  }

  showError() {
    this.element.innerHTML = `
      <div class="flex items-center justify-center h-full">
        <div class="text-center">
          <p class="text-slate-500">Unable to load heatmap data</p>
          <button class="mt-2 px-4 py-2 bg-teal-700 text-white rounded-lg text-sm"
                  data-action="click->pattern-heatmap#retry">
            Retry
          </button>
        </div>
      </div>
    `
  }

  retry() {
    this.element.innerHTML = ''
    this.loadHeatmapData()
  }
}