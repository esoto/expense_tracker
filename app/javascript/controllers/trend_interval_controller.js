import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("Trend interval controller connected")
  }

  setInterval(event) {
    const button = event.currentTarget
    const interval = button.dataset.interval
    
    // Update button styles
    this.element.querySelectorAll('button').forEach(btn => {
      btn.classList.remove('bg-teal-700', 'text-white')
      btn.classList.add('bg-slate-200', 'text-slate-700', 'hover:bg-slate-300')
    })
    
    button.classList.remove('bg-slate-200', 'text-slate-700', 'hover:bg-slate-300')
    button.classList.add('bg-teal-700', 'text-white')
    
    // Dispatch event to update chart
    const chartController = document.querySelector('[data-controller="pattern-trend-chart"]')
    if (chartController) {
      const controller = this.application.getControllerForElementAndIdentifier(
        chartController, 
        'pattern-trend-chart'
      )
      if (controller) {
        controller.loadChartData(interval)
      }
    }
  }
}