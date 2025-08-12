import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    merchant: String,
    description: String,
    amount: String
  }
  
  fillForm(event) {
    event.preventDefault()
    
    // Find the form fields
    const form = this.element.closest('.bg-white').querySelector('form')
    if (!form) return
    
    const merchantField = form.querySelector('input[name="merchant_name"]')
    const descriptionField = form.querySelector('textarea[name="description"]')
    const amountField = form.querySelector('input[name="amount"]')
    
    // Fill the fields with example data
    if (merchantField && this.hasMerchantValue) {
      merchantField.value = this.merchantValue
    }
    
    if (descriptionField && this.hasDescriptionValue) {
      descriptionField.value = this.descriptionValue
    }
    
    if (amountField && this.hasAmountValue) {
      amountField.value = this.amountValue
    }
    
    // Add a visual feedback
    this.element.classList.add('ring-2', 'ring-teal-500')
    setTimeout(() => {
      this.element.classList.remove('ring-2', 'ring-teal-500')
    }, 500)
  }
}