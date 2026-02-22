import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["categorySelect", "expandIcon", "expenseList"]
  
  connect() {
    this.selectedExpenses = new Map()
    this.initializeSelections()
  }

  initializeSelections() {
    // Initialize selected expenses for each group
    document.querySelectorAll('[data-group-id]').forEach(group => {
      const groupId = group.dataset.groupId
      const expenseIds = JSON.parse(group.dataset.expenseIds || '[]')
      this.selectedExpenses.set(groupId, new Set(expenseIds))
    })
  }

  toggleExpenses(event) {
    const button = event.currentTarget
    const groupId = button.dataset.groupId
    const expenseList = document.getElementById(`expenses_${groupId}`)
    const icon = button.querySelector('svg')
    
    if (expenseList.classList.contains('hidden')) {
      expenseList.classList.remove('hidden')
      icon.classList.add('rotate-180')
    } else {
      expenseList.classList.add('hidden')
      icon.classList.remove('rotate-180')
    }
  }

  updateSelection(event) {
    const checkbox = event.target
    const expenseId = checkbox.dataset.expenseId
    const groupId = checkbox.dataset.groupId
    
    if (!this.selectedExpenses.has(groupId)) {
      this.selectedExpenses.set(groupId, new Set())
    }
    
    const groupExpenses = this.selectedExpenses.get(groupId)
    
    if (checkbox.checked) {
      groupExpenses.add(expenseId)
    } else {
      groupExpenses.delete(expenseId)
    }
    
    this.updateApplyButton(groupId)
  }

  updateApplyButton(groupId) {
    const button = document.querySelector(`button[data-action="click->bulk-categorization#applyCategory"][data-group-id="${groupId}"]`)
    const groupExpenses = this.selectedExpenses.get(groupId)
    
    if (button) {
      if (!groupExpenses || groupExpenses.size === 0) {
        button.disabled = true
        button.classList.add('opacity-50', 'cursor-not-allowed')
      } else {
        button.disabled = false
        button.classList.remove('opacity-50', 'cursor-not-allowed')
      }
    }
  }

  applyCategory(event) {
    const button = event.currentTarget
    const groupId = button.dataset.groupId
    const select = document.querySelector(`select[data-group-id="${groupId}"]`)
    const categoryId = select?.value
    
    if (!categoryId) {
      this.showNotification('Por favor selecciona una categoría', 'error')
      return
    }
    
    const expenseIds = Array.from(this.selectedExpenses.get(groupId) || [])
    
    if (expenseIds.length === 0) {
      this.showNotification('No hay gastos seleccionados', 'error')
      return
    }
    
    this.submitCategorization(expenseIds, categoryId, groupId)
  }

  applySuggestion(event) {
    const button = event.currentTarget
    const categoryId = button.dataset.categoryId
    const groupId = button.dataset.groupId
    
    const expenseIds = Array.from(this.selectedExpenses.get(groupId) || [])
    
    if (expenseIds.length === 0) {
      this.showNotification('No hay gastos seleccionados', 'error')
      return
    }
    
    this.submitCategorization(expenseIds, categoryId, groupId)
  }

  submitCategorization(expenseIds, categoryId, groupId) {
    // Show progress indicator
    this.showProgress(expenseIds.length)
    
    // Disable buttons during submission
    this.disableGroupButtons(groupId)
    
    // Submit via Turbo
    const formData = new FormData()
    formData.append('expense_ids', JSON.stringify(expenseIds))
    formData.append('category_id', categoryId)
    formData.append('group_id', groupId)
    
    fetch('/bulk_categorizations/categorize', {
      method: 'POST',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'text/vnd.turbo-stream.html'
      },
      body: formData
    })
    .then(response => {
      if (!response.ok) throw new Error('Network response was not ok')
      return response.text()
    })
    .then(html => {
      Turbo.renderStreamMessage(html)
      this.hideProgress()
    })
    .catch(error => {
      console.error('Error:', error)
      this.showNotification('Ocurrió un error. Por favor intenta de nuevo.', 'error')
      this.hideProgress()
      this.enableGroupButtons(groupId)
    })
  }

  preview(event) {
    const button = event.currentTarget
    const groupId = button.dataset.groupId
    const select = document.querySelector(`select[data-group-id="${groupId}"]`)
    const categoryId = select?.value
    
    if (!categoryId) {
      this.showNotification('Por favor selecciona una categoría para previsualizar', 'error')
      return
    }
    
    const expenseIds = Array.from(this.selectedExpenses.get(groupId) || [])
    
    if (expenseIds.length === 0) {
      this.showNotification('No hay gastos seleccionados', 'error')
      return
    }
    
    // Request preview via Turbo
    const formData = new FormData()
    formData.append('expense_ids', JSON.stringify(expenseIds))
    formData.append('category_id', categoryId)
    
    fetch('/bulk_categorizations/preview', {
      method: 'POST',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'text/vnd.turbo-stream.html'
      },
      body: formData
    })
    .then(response => response.text())
    .then(html => Turbo.renderStreamMessage(html))
    .catch(error => {
      console.error('Error:', error)
      this.showNotification('Error al cargar la previsualización', 'error')
    })
  }

  overrideCategory(event) {
    const select = event.target
    const expenseId = select.dataset.expenseId
    const categoryId = select.value
    
    if (categoryId) {
      // Mark this expense as having an override
      select.closest('.flex').classList.add('ring-2', 'ring-amber-400')
    } else {
      // Remove override marking
      select.closest('.flex').classList.remove('ring-2', 'ring-amber-400')
    }
  }

  autoCategorizehighConfidence(event) {
    if (!confirm('Esto categorizará automáticamente todos los gastos de alta confianza. ¿Continuar?')) {
      return
    }
    
    const formData = new FormData()
    formData.append('confidence_threshold', '0.8')
    
    fetch('/bulk_categorizations/auto_categorize', {
      method: 'POST',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'text/vnd.turbo-stream.html'
      },
      body: formData
    })
    .then(response => response.text())
    .then(html => Turbo.renderStreamMessage(html))
    .catch(error => {
      console.error('Error:', error)
      this.showNotification('La categorización automática falló', 'error')
    })
  }

  showProgress(total) {
    const progress = document.getElementById('categorization_progress')
    if (progress) {
      progress.classList.remove('hidden')
      progress.querySelector('[data-progress-target="total"]').textContent = total
      progress.querySelector('[data-progress-target="completed"]').textContent = '0'
      progress.querySelector('[data-progress-target="bar"]').style.width = '0%'
    }
  }

  hideProgress() {
    const progress = document.getElementById('categorization_progress')
    if (progress) {
      setTimeout(() => {
        progress.classList.add('hidden')
      }, 1000)
    }
  }

  updateProgress(completed, total) {
    const progress = document.getElementById('categorization_progress')
    if (progress) {
      const percentage = (completed / total) * 100
      progress.querySelector('[data-progress-target="completed"]').textContent = completed
      progress.querySelector('[data-progress-target="bar"]').style.width = `${percentage}%`
    }
  }

  disableGroupButtons(groupId) {
    document.querySelectorAll(`button[data-group-id="${groupId}"]`).forEach(button => {
      button.disabled = true
      button.classList.add('opacity-50', 'cursor-not-allowed')
    })
  }

  enableGroupButtons(groupId) {
    document.querySelectorAll(`button[data-group-id="${groupId}"]`).forEach(button => {
      button.disabled = false
      button.classList.remove('opacity-50', 'cursor-not-allowed')
    })
  }

  showNotification(message, type = 'info') {
    const notifications = document.getElementById('notifications')
    if (!notifications) return
    
    const notification = document.createElement('div')
    notification.className = `mb-4 p-4 rounded-lg flex items-start space-x-3 ${
      type === 'error' ? 'bg-rose-50 border border-rose-200' :
      type === 'success' ? 'bg-emerald-50 border border-emerald-200' :
      'bg-amber-50 border border-amber-200'
    }`
    
    const icon = type === 'error' ? 
      '<svg class="w-5 h-5 text-rose-600" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>' :
      type === 'success' ?
      '<svg class="w-5 h-5 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>' :
      '<svg class="w-5 h-5 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path></svg>'
    
    notification.innerHTML = `
      ${icon}
      <div class="flex-1">
        <p class="text-sm ${
          type === 'error' ? 'text-rose-700' :
          type === 'success' ? 'text-emerald-700' :
          'text-amber-700'
        }">${message}</p>
      </div>
      <button onclick="this.parentElement.remove()" class="text-slate-400 hover:text-slate-600">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
        </svg>
      </button>
    `
    
    notifications.appendChild(notification)
    
    // Auto-remove after 5 seconds
    setTimeout(() => {
      notification.remove()
    }, 5000)
  }
}