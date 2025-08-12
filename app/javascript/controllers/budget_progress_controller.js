import { Controller } from "@hotwired/stimulus"

// Budget Progress Controller
// Handles budget visualization and quick budget setting interactions
export default class extends Controller {
  static targets = ["bar", "percentage", "remaining"]
  
  connect() {
    // Animate the progress bar on connect
    this.animateProgress()
  }
  
  animateProgress() {
    if (!this.hasBarTarget) return
    
    // Get the current width and animate from 0
    const targetWidth = this.barTarget.style.width
    this.barTarget.style.width = "0%"
    
    // Use requestAnimationFrame for smooth animation
    requestAnimationFrame(() => {
      this.barTarget.style.width = targetWidth
    })
  }
  
  openQuickSet(event) {
    event.preventDefault()
    const period = event.currentTarget.dataset.period || 'monthly'
    
    // Open modal or slide panel for quick budget setting
    // This would typically trigger a Turbo Frame or modal
    this.dispatchEvent("openBudgetModal", { period })
  }
  
  updateProgress(event) {
    const { percentage, remaining, status } = event.detail
    
    if (this.hasBarTarget) {
      this.barTarget.style.width = `${Math.min(percentage, 100)}%`
      this.updateBarColor(status)
    }
    
    if (this.hasPercentageTarget) {
      this.percentageTarget.textContent = `${percentage}%`
    }
    
    if (this.hasRemainingTarget) {
      this.remainingTarget.textContent = remaining
    }
  }
  
  updateBarColor(status) {
    if (!this.hasBarTarget) return
    
    // Remove all color classes
    const colorClasses = ['bg-emerald-600', 'bg-amber-600', 'bg-rose-500', 'bg-rose-600']
    colorClasses.forEach(cls => this.barTarget.classList.remove(cls))
    
    // Add appropriate color based on status
    switch(status) {
      case 'exceeded':
        this.barTarget.classList.add('bg-rose-600')
        break
      case 'critical':
        this.barTarget.classList.add('bg-rose-500')
        break
      case 'warning':
        this.barTarget.classList.add('bg-amber-600')
        break
      default:
        this.barTarget.classList.add('bg-emerald-600')
    }
  }
  
  dispatchEvent(name, detail = {}) {
    this.dispatch(name, { detail, bubbles: true, cancelable: true })
  }
}