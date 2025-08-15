import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["slider", "value"]
  
  connect() {
    this.updateValue()
  }
  
  updateValue() {
    if (this.hasSliderTarget && this.hasValueTarget) {
      const value = parseFloat(this.sliderTarget.value).toFixed(1)
      this.valueTarget.textContent = value
      
      // Update slider color based on value
      const min = parseFloat(this.sliderTarget.min)
      const max = parseFloat(this.sliderTarget.max)
      const percentage = ((value - min) / (max - min)) * 100
      
      // Create gradient for the slider track
      this.sliderTarget.style.background = `linear-gradient(to right, #0F766E ${percentage}%, #E2E8F0 ${percentage}%)`
    }
  }
}