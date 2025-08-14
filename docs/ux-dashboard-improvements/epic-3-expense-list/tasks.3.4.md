## Task 3.4: Batch Selection System & Operations

**Task ID:** EXP-3.4  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 12  
**Dependencies:** Task 3.1 (requires optimized queries)  
**Blocks:** Task 3.5 (bulk categorization modal)

### Description
Implement a robust checkbox-based selection system with batch operations for multiple expenses. Includes transaction safety, optimistic locking, and comprehensive error handling.

### Acceptance Criteria
- [ ] Checkbox for each expense row with visual feedback
- [ ] Select all with smart pagination handling
- [ ] Shift-click for range selection
- [ ] Ctrl/Cmd-click for individual multi-select
- [ ] Real-time selected count display
- [ ] Floating action bar with batch operations
- [ ] Selection persistence across page navigation
- [ ] Atomic batch operations with rollback
- [ ] Rate limiting (max 10 operations/minute)
- [ ] Audit logging for all batch operations

### Technical Implementation

#### 1. Backend Service

```ruby
# app/services/batch_operation_service.rb
class BatchOperationService
  MAX_BATCH_SIZE = 500
  LOCK_TIMEOUT = 5.seconds
  
  def initialize(expense_ids:, user:, options: {})
    @expense_ids = Array(expense_ids).uniq.first(MAX_BATCH_SIZE)
    @user = user
    @options = options
    @result = Result.new
  end
  
  def categorize(category_id)
    execute_in_transaction do
      expenses = load_and_lock_expenses
      store_rollback_data(expenses, :category_id)
      
      expenses.find_in_batches(batch_size: 100) do |batch|
        batch.each do |expense|
          next if @options[:skip_categorized] && expense.category_id.present?
          
          expense.with_lock do
            expense.update!(
              category_id: category_id,
              categorized_at: Time.current,
              categorized_by_id: @user.id,
              lock_version: expense.lock_version + 1
            )
          end
          
          @result.success_ids << expense.id
        rescue => e
          @result.failed_ids << expense.id
          @result.errors[expense.id] = e.message
        end
      end
      
      log_operation(:categorize, category_id: category_id)
    end
    
    @result.finalize!
  end
  
  private
  
  def execute_in_transaction(&block)
    ActiveRecord::Base.transaction(isolation: :read_committed) do
      ActiveRecord::Base.connection.execute("SET lock_timeout = '5s'")
      yield
    end
  rescue ActiveRecord::LockWaitTimeout => e
    handle_lock_timeout(e)
  end
  
  def load_and_lock_expenses
    Expense
      .where(id: @expense_ids)
      .where(email_account_id: @user.accessible_account_ids)
      .lock("FOR UPDATE SKIP LOCKED")
  end
end
```

#### 2. Frontend Stimulus Controller

```javascript
// app/javascript/controllers/batch_selection_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "selectAll", "counter", "actionBar"]
  static values = { 
    selected: Array,
    maxSize: Number,
    csrfToken: String
  }
  
  connect() {
    this.selectedValue = this.loadPersistedSelection()
    this.maxSizeValue = 500
    this.lastCheckedIndex = null
    this.updateUI()
  }
  
  // Select individual item
  toggle(event) {
    const checkbox = event.currentTarget
    const id = parseInt(checkbox.dataset.expenseId)
    
    if (event.shiftKey && this.lastCheckedIndex !== null) {
      this.selectRange(this.lastCheckedIndex, checkbox)
    } else {
      if (checkbox.checked) {
        this.select(id)
      } else {
        this.deselect(id)
      }
      this.lastCheckedIndex = checkbox
    }
    
    this.updateUI()
  }
  
  // Select all visible
  toggleAll(event) {
    const checked = event.currentTarget.checked
    
    this.checkboxTargets.forEach(checkbox => {
      const id = parseInt(checkbox.dataset.expenseId)
      checkbox.checked = checked
      
      if (checked) {
        this.select(id)
      } else {
        this.deselect(id)
      }
    })
    
    this.updateUI()
  }
  
  // Range selection with Shift key
  selectRange(startCheckbox, endCheckbox) {
    const checkboxes = this.checkboxTargets
    const startIndex = checkboxes.indexOf(startCheckbox)
    const endIndex = checkboxes.indexOf(endCheckbox)
    
    const [from, to] = startIndex < endIndex 
      ? [startIndex, endIndex] 
      : [endIndex, startIndex]
    
    for (let i = from; i <= to; i++) {
      const checkbox = checkboxes[i]
      const id = parseInt(checkbox.dataset.expenseId)
      checkbox.checked = true
      this.select(id)
    }
  }
  
  // Batch categorize
  async categorize(event) {
    const categoryId = event.currentTarget.dataset.categoryId
    
    if (!this.validateSelection()) return
    
    try {
      const response = await fetch('/expenses/batch_categorize', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfTokenValue
        },
        body: JSON.stringify({
          expense_ids: this.selectedValue,
          category_id: categoryId,
          skip_categorized: true
        })
      })
      
      const result = await response.json()
      
      if (response.ok) {
        this.showSuccess(`Categorized ${result.data.succeeded} expenses`)
        this.clearSelection()
        this.refreshList()
      } else {
        this.showError(result.error)
      }
    } catch (error) {
      this.showError('Network error. Please try again.')
    }
  }
  
  // Persist selection in sessionStorage
  persistSelection() {
    sessionStorage.setItem('expense_selection', JSON.stringify(this.selectedValue))
  }
  
  loadPersistedSelection() {
    const stored = sessionStorage.getItem('expense_selection')
    return stored ? JSON.parse(stored) : []
  }
  
  // Update UI elements
  updateUI() {
    const count = this.selectedValue.length
    
    // Update counter
    this.counterTarget.textContent = `${count} selected`
    
    // Show/hide action bar
    this.actionBarTarget.classList.toggle('hidden', count === 0)
    
    // Update select all checkbox
    const allChecked = this.checkboxTargets.every(cb => cb.checked)
    const someChecked = this.checkboxTargets.some(cb => cb.checked)
    this.selectAllTarget.checked = allChecked
    this.selectAllTarget.indeterminate = someChecked && !allChecked
    
    // Persist for navigation
    this.persistSelection()
  }
  
  validateSelection() {
    if (this.selectedValue.length === 0) {
      this.showError('No expenses selected')
      return false
    }
    
    if (this.selectedValue.length > this.maxSizeValue) {
      this.showError(`Maximum ${this.maxSizeValue} items allowed`)
      return false
    }
    
    return true
  }
}
```

#### 3. Controller Security

```ruby
# app/controllers/concerns/batch_operation_security.rb
module BatchOperationSecurity
  extend ActiveSupport::Concern
  
  included do
    before_action :validate_batch_size, only: [:batch_categorize, :batch_delete]
    before_action :validate_ownership, only: [:batch_categorize, :batch_delete]
    before_action :rate_limit_batch_operations
  end
  
  private
  
  def validate_batch_size
    if params[:expense_ids]&.size.to_i > 500
      render json: { error: "Maximum 500 items per batch" }, status: 422
    end
  end
  
  def validate_ownership
    unauthorized = Expense.where(id: params[:expense_ids])
                          .where.not(email_account_id: current_user_account_ids)
                          .exists?
    
    if unauthorized
      render json: { error: "Unauthorized access" }, status: 403
    end
  end
  
  def rate_limit_batch_operations
    key = "batch_ops:#{current_user.id}"
    count = Rails.cache.increment(key, 1, expires_in: 1.minute)
    
    if count > 10
      render json: { error: "Rate limit exceeded. Max 10 operations per minute." }, status: 429
    end
  end
end
```

#### 4. Audit Logging

```ruby
# app/models/batch_operation_log.rb
class BatchOperationLog < ApplicationRecord
  belongs_to :user
  
  scope :recent, -> { order(created_at: :desc) }
  scope :by_operation, ->(op) { where(operation_type: op) }
  
  def can_undo?
    !undone? && created_at > 24.hours.ago
  end
  
  def undo!
    return false unless can_undo?
    
    ActiveRecord::Base.transaction do
      # Restore original values
      details['original_values'].each do |expense_id, values|
        Expense.find(expense_id).update!(values)
      end
      
      update!(undone: true, undone_at: Time.current)
    end
  end
end
```

### UI Design

```erb
<!-- app/views/expenses/_batch_action_bar.html.erb -->
<div data-batch-selection-target="actionBar" 
     class="fixed bottom-4 left-1/2 transform -translate-x-1/2 
            bg-white rounded-lg shadow-lg border border-slate-200 
            px-6 py-3 hidden z-50">
  <div class="flex items-center gap-4">
    <span data-batch-selection-target="counter" 
          class="text-slate-600 font-medium">
      0 selected
    </span>
    
    <div class="border-l border-slate-200 h-6"></div>
    
    <button data-action="click->batch-selection#categorize"
            class="px-4 py-2 bg-teal-700 text-white rounded-lg 
                   hover:bg-teal-800 transition-colors">
      <i class="fas fa-tag mr-2"></i>
      Categorize
    </button>
    
    <button data-action="click->batch-selection#delete"
            class="px-4 py-2 bg-rose-600 text-white rounded-lg 
                   hover:bg-rose-700 transition-colors">
      <i class="fas fa-trash mr-2"></i>
      Delete
    </button>
    
    <button data-action="click->batch-selection#export"
            class="px-4 py-2 bg-slate-200 text-slate-700 rounded-lg 
                   hover:bg-slate-300 transition-colors">
      <i class="fas fa-download mr-2"></i>
      Export
    </button>
    
    <button data-action="click->batch-selection#clearSelection"
            class="text-slate-500 hover:text-slate-700">
      Clear
    </button>
  </div>
</div>
```

### Performance Considerations

- Use database transactions with `READ COMMITTED` isolation
- Implement `SKIP LOCKED` to avoid deadlocks
- Process in chunks of 100 to manage memory
- Add progress indicator for operations > 50 items
- Cache selection in sessionStorage (5MB limit)

### Error Scenarios

| Scenario | Handling | User Feedback |
|----------|----------|---------------|
| Concurrent modification | Retry with exponential backoff | "Some items were updated. Refreshing..." |
| Lock timeout | Skip locked items | "X items skipped (in use)" |
| Partial failure | Complete successful, log failed | "X of Y completed. View details." |
| Rate limit exceeded | Block operation | "Too many operations. Wait 1 minute." |
| Network failure | Retry with idempotency key | "Connection lost. Retrying..." |

### Testing Requirements

```ruby
# spec/system/batch_selection_spec.rb
RSpec.describe "Batch Selection", type: :system, js: true do
  it "handles shift-click range selection" do
    visit expenses_path
    
    # Click first checkbox
    first('.expense-checkbox').click
    
    # Shift-click fifth checkbox
    all('.expense-checkbox')[4].click(:shift)
    
    expect(page).to have_text('5 selected')
    expect(page).to have_css('.batch-action-bar')
  end
  
  it "handles concurrent modifications gracefully" do
    # Simulate another user updating
    expense.update_column(:lock_version, expense.lock_version + 1)
    
    select_expenses([expense])
    click_button 'Categorize'
    
    expect(page).to have_text('1 item skipped')
  end
end
```

### Definition of Done

- [ ] Selection works across pagination
- [ ] Shift-click and Ctrl-click functional
- [ ] Batch operations atomic with rollback
- [ ] Rate limiting prevents abuse
- [ ] Audit logs capture all operations
- [ ] Performance: <2s for 100 items
- [ ] Accessibility: Full keyboard navigation
- [ ] Mobile: Touch-friendly selection
