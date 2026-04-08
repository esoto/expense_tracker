import { Controller } from "@hotwired/stimulus"
import { t } from "services/i18n"

export default class extends Controller {
  static targets = ["valueField", "valueHelp", "testInput", "testResult"]
  
  connect() {
    // Initialize help text based on current pattern type
    if (this.element.querySelector('select[name*="pattern_type"]')) {
      this.updateValueHelp()
    }
  }
  
  updateValueHelp() {
    const patternTypeSelect = this.element.querySelector('select[name*="pattern_type"]')
    if (!patternTypeSelect) return
    const patternType = patternTypeSelect.value

    if (!this.hasValueHelpTarget) return
    
    const helpTexts = {
      'merchant': t('patterns.form.help.merchant'),
      'keyword': t('patterns.form.help.keyword'),
      'description': t('patterns.form.help.description'),
      'amount_range': t('patterns.form.help.amount_range'),
      'regex': t('patterns.form.help.regex'),
      'time': t('patterns.form.help.time'),
      '': t('patterns.form.help.default')
    }
    
    this.valueHelpTarget.innerHTML = helpTexts[patternType] || helpTexts['']
    
    // Update placeholder
    if (this.hasValueFieldTarget) {
      const placeholders = {
        'merchant': t('patterns.form.placeholders.merchant'),
        'keyword': t('patterns.form.placeholders.keyword'),
        'description': t('patterns.form.placeholders.description'),
        'amount_range': t('patterns.form.placeholders.amount_range'),
        'regex': t('patterns.form.placeholders.regex'),
        'time': t('patterns.form.placeholders.time')
      }

      this.valueFieldTarget.placeholder = placeholders[patternType] || t('patterns.form.placeholders.default')
    }
  }
  
  testPattern() {
    if (!this.hasTestInputTarget || !this.hasTestResultTarget) return
    if (!this.hasValueFieldTarget) return

    const testText = this.testInputTarget.value
    const patternType = this.element.querySelector('select[name*="pattern_type"]').value
    const patternValue = this.valueFieldTarget.value
    
    if (!testText || !patternType || !patternValue) {
      this.testResultTarget.innerHTML = `
        <div class="p-3 bg-amber-50 border border-amber-200 rounded-lg">
          <p class="text-sm text-amber-700">${t('patterns.form.validation.fill_required')}</p>
        </div>
      `
      return
    }
    
    // Perform client-side pattern matching
    const matches = this.performMatch(testText, patternType, patternValue)
    
    if (matches) {
      this.testResultTarget.innerHTML = `
        <div class="p-3 bg-emerald-50 border border-emerald-200 rounded-lg">
          <div class="flex items-center">
            <svg aria-hidden="true" class="w-5 h-5 text-emerald-600 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
            </svg>
            <span class="text-sm font-medium text-emerald-700">${t('patterns.form.test.match')}</span>
          </div>
        </div>
      `
    } else {
      this.testResultTarget.innerHTML = `
        <div class="p-3 bg-rose-50 border border-rose-200 rounded-lg">
          <div class="flex items-center">
            <svg aria-hidden="true" class="w-5 h-5 text-rose-600 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
            </svg>
            <span class="text-sm font-medium text-rose-700">${t('patterns.form.test.no_match')}</span>
          </div>
        </div>
      `
    }
  }
  
  performMatch(text, type, value) {
    const normalizedText = text.toLowerCase().trim()
    const normalizedValue = value.toLowerCase().trim()
    
    switch(type) {
      case 'merchant':
      case 'keyword':
      case 'description':
        return normalizedText.includes(normalizedValue)
      
      case 'regex':
        try {
          const regex = new RegExp(value, 'i')
          return regex.test(text)
        } catch (e) {
          return false
        }
      
      case 'amount_range':
        const amount = parseFloat(text)
        if (isNaN(amount)) return false
        
        const parts = value.split('-')
        if (parts.length !== 2) return false
        
        const min = parseFloat(parts[0])
        const max = parseFloat(parts[1])
        
        return amount >= min && amount <= max
      
      case 'time':
        // For time patterns, we'd need the actual datetime
        // This is a simplified check - supports Spanish keywords
        const timePatterns = ['mañana', 'tarde', 'atardecer', 'noche', 'fin de semana', 'entre semana']
        if (timePatterns.includes(value.toLowerCase())) {
          return true // Can't properly test without datetime
        }
        // Check for time range format (HH:MM-HH:MM)
        if (/^\d{2}:\d{2}-\d{2}:\d{2}$/.test(value)) {
          return true
        }
        return false
      
      default:
        return false
    }
  }
}