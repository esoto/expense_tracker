# Ticket 3.1: Implement Expense Visibility System

## Ticket Information
- **Epic**: Epic 3 - Privacy Features (Weeks 5-6)
- **Priority**: HIGH
- **Story Points**: 5
- **Risk Level**: MEDIUM
- **Dependencies**: 
  - Epic 2 completed (Multi-tenancy)

## Description
Implement the personal/shared expense visibility system that allows users within an account to mark expenses as personal (only visible to them) or shared (visible to all account members). This provides privacy within multi-user accounts while maintaining shared financial tracking.

## Technical Requirements
1. Add visibility enum to Expense model
2. Implement visibility scopes and filters
3. Update controllers to respect visibility
4. Create UI for toggling visibility
5. Add visibility indicators in expense lists
6. Update reporting to handle visibility

## Acceptance Criteria
- [ ] Expense model updated with:
  - visibility enum (shared: 0, personal: 1)
  - Default visibility based on account settings
  - User association to track expense creator
  - Visibility scopes (visible_to, shared_only, personal_only)
- [ ] Visibility filtering implemented:
  - Users see all shared expenses
  - Users see only their own personal expenses
  - Cannot see other users' personal expenses
  - Admins/owners can optionally see all (configurable)
- [ ] UI components for visibility:
  - Toggle switch on expense form
  - Visibility badge on expense cards
  - Filter dropdown in expense list
  - Bulk visibility update action
  - Clear visual distinction (icons/colors)
- [ ] Reports and calculations updated:
  - Total calculations respect visibility
  - Category breakdowns filter by visibility
  - Budget tracking includes visibility logic
  - Export functions respect visibility
- [ ] API endpoints respect visibility:
  - Index endpoint filters appropriately
  - Show endpoint returns 404 for hidden expenses
  - Update/delete respect ownership rules

## Implementation Details
```ruby
# db/migrate/add_visibility_to_expenses.rb
class AddVisibilityToExpenses < ActiveRecord::Migration[8.0]
  def change
    add_column :expenses, :visibility, :integer, default: 0, null: false
    add_reference :expenses, :user, foreign_key: true, null: true
    
    add_index :expenses, [:account_id, :visibility]
    add_index :expenses, [:account_id, :user_id, :visibility]
    add_index :expenses, [:user_id, :visibility, :transaction_date]
  end
end

# app/models/expense.rb (updated)
class Expense < ApplicationRecord
  include ActsAsAccountScoped
  
  # Enums
  enum visibility: {
    shared: 0,
    personal: 1
  }
  
  # Associations
  belongs_to :user, optional: true
  belongs_to :email_account
  belongs_to :category, optional: true
  
  # Validations
  validates :visibility, presence: true
  validate :user_required_for_personal_expenses
  
  # Scopes
  scope :visible_to, ->(user) {
    where(visibility: :shared)
      .or(where(visibility: :personal, user: user))
  }
  
  scope :shared_only, -> { where(visibility: :shared) }
  scope :personal_only, -> { where(visibility: :personal) }
  
  scope :for_user, ->(user) {
    where(user: user)
  }
  
  # Callbacks
  before_validation :set_default_visibility, on: :create
  
  # Instance methods
  def visible_to?(user)
    shared? || (personal? && self.user_id == user.id)
  end
  
  def can_edit?(user)
    return false unless visible_to?(user)
    
    # User can edit their own expenses
    return true if self.user_id == user.id
    
    # Admins can edit shared expenses
    membership = user.account_memberships.find_by(account: account)
    return true if shared? && membership&.admin_or_owner?
    
    false
  end
  
  def can_delete?(user)
    # Only expense creator or account owner can delete
    self.user_id == user.id || user.owner_of?(account)
  end
  
  private
  
  def user_required_for_personal_expenses
    if personal? && user_id.blank?
      errors.add(:user, "must be set for personal expenses")
    end
  end
  
  def set_default_visibility
    if account && user
      # Check account settings for default visibility
      self.visibility ||= account.settings.dig('default_visibility') || 'shared'
    else
      self.visibility ||= 'shared'
    end
  end
end

# app/controllers/expenses_controller.rb (updated)
class ExpensesController < ApplicationController
  before_action :set_expense, only: [:show, :edit, :update, :destroy]
  before_action :authorize_expense_access!, only: [:show, :edit]
  before_action :authorize_expense_edit!, only: [:update]
  before_action :authorize_expense_delete!, only: [:destroy]
  
  def index
    @expenses = current_account.expenses
                              .visible_to(current_user)
                              .includes(:category, :user, :email_account)
    
    # Visibility filter
    if params[:visibility].present?
      case params[:visibility]
      when 'shared'
        @expenses = @expenses.shared_only
      when 'personal'
        @expenses = @expenses.personal_only.for_user(current_user)
      when 'all' # Only for admins
        @expenses = current_account.expenses if current_membership.admin_or_owner?
      end
    end
    
    @expenses = @expenses.recent.page(params[:page])
    
    # Calculate totals respecting visibility
    @total_visible = @expenses.sum(:amount)
    @shared_total = current_account.expenses.shared_only.sum(:amount)
    @personal_total = current_account.expenses.personal_only
                                              .for_user(current_user)
                                              .sum(:amount)
  end
  
  def create
    @expense = current_account.expenses.build(expense_params)
    @expense.user = current_user
    
    if @expense.save
      redirect_to @expense, notice: "Expense created as #{@expense.visibility}"
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def bulk_update_visibility
    expense_ids = params[:expense_ids]
    new_visibility = params[:visibility]
    
    expenses = current_account.expenses
                             .visible_to(current_user)
                             .where(id: expense_ids)
    
    count = 0
    expenses.find_each do |expense|
      if expense.can_edit?(current_user)
        expense.update(visibility: new_visibility)
        count += 1
      end
    end
    
    redirect_to expenses_path, 
                notice: "Updated visibility for #{count} expenses"
  end
  
  private
  
  def authorize_expense_access!
    unless @expense.visible_to?(current_user)
      redirect_to expenses_path, alert: "You cannot view this expense"
    end
  end
  
  def authorize_expense_edit!
    unless @expense.can_edit?(current_user)
      redirect_to expenses_path, alert: "You cannot edit this expense"
    end
  end
  
  def authorize_expense_delete!
    unless @expense.can_delete?(current_user)
      redirect_to expenses_path, alert: "You cannot delete this expense"
    end
  end
  
  def expense_params
    params.require(:expense).permit(
      :amount, :description, :transaction_date,
      :merchant_name, :category_id, :visibility,
      :email_account_id, :currency, :status
    )
  end
end
```

## UI/UX Requirements
- [ ] Expense form includes:
  - Visibility toggle switch (shared/personal)
  - Help text explaining visibility
  - Default based on account settings
- [ ] Expense list shows:
  - Eye icon for shared expenses
  - Lock icon for personal expenses
  - User avatar for expense creator
  - Visibility filter dropdown
- [ ] Expense card displays:
  - Visibility badge (color-coded)
  - "Personal" label if applicable
  - Creator name for shared expenses
- [ ] Bulk actions menu:
  - "Make Personal" option
  - "Make Shared" option
  - Only for user's own expenses
- [ ] Dashboard widgets:
  - Separate totals for shared/personal
  - Combined view option
  - Privacy indicator

## Testing Requirements
- [ ] Model specs for visibility:
  - Scope testing (visible_to)
  - Validation testing
  - Permission methods
- [ ] Controller specs:
  - Visibility filtering
  - Authorization for each action
  - Bulk update functionality
- [ ] Feature specs:
  - Complete visibility workflows
  - Cannot see others' personal expenses
  - Can toggle own expense visibility
- [ ] API specs:
  - Proper filtering in JSON responses
  - 404 for unauthorized expenses

## Security Considerations
- [ ] Strict visibility enforcement at model level
- [ ] Double-check queries for data leakage
- [ ] Audit log visibility changes
- [ ] Prevent visibility manipulation via params
- [ ] Cache invalidation on visibility change

## Performance Considerations
- [ ] Optimize visibility queries with indexes
- [ ] Cache visibility calculations
- [ ] Batch visibility updates
- [ ] Monitor query performance

## UX Implementation

### 1. User Flow Specifications

#### Creating an Expense with Visibility Selection
1. **Dashboard** → Click "Add Expense" button
2. **Expense Form** opens with visibility toggle
3. Default visibility based on account preference
4. **Toggle Visibility**:
   - Click toggle switch
   - Immediate visual feedback
   - Help text updates to explain choice
5. Fill in expense details
6. Submit → Toast confirms visibility: "Personal expense created"

#### Viewing Mixed Visibility Expenses
1. **Expense List** shows all visible expenses
2. **Visual Indicators**:
   - Shared expenses: No special marking (default)
   - Personal expenses: Lock icon + "Personal" badge
   - Other's expenses: User avatar shown
3. **Filter by Visibility**:
   - Click filter dropdown
   - Select: All / Shared / Personal
   - List updates instantly
   - URL updates for bookmarking

#### Bulk Visibility Update
1. Select multiple expenses (checkbox)
2. Bulk actions menu appears
3. Choose "Change Visibility"
4. Select new visibility option
5. Confirmation dialog with count
6. Success: "Updated visibility for X expenses"

#### Privacy Conflict Resolution
1. Attempt to share expense with private category
2. Warning modal appears
3. Options presented:
   - Keep personal
   - Make shared (category becomes visible)
   - Cancel

### 2. UI Component Specifications

#### Expense Form Visibility Toggle
```
┌─────────────────────────────────────────┐
│ New Expense                             │
│ ─────────────────────────────────────── │
│                                         │
│ Amount *                                │
│ ┌───────────────────────────────┐     │
│ │ $ 45.99                       │     │
│ └───────────────────────────────┘     │
│                                         │
│ Description                             │
│ ┌───────────────────────────────┐     │
│ │ Grocery shopping at Walmart   │     │
│ └───────────────────────────────┘     │
│                                         │
│ Visibility                              │
│ ┌─────────────────────────────────┐   │
│ │  Shared  [====○]  Personal     │   │
│ └─────────────────────────────────┘   │
│ ℹ Personal expenses are only visible   │
│   to you                                │
│                                         │
│ [Cancel]            [Create Expense]   │
└─────────────────────────────────────────┘
```

#### Expense Card with Visibility Indicators
```
┌──────────────────────────────────────────┐
│ Shared Expense                           │
│ ┌──────────────────────────────────┐    │
│ │ Walmart                          │    │
│ │ Grocery shopping                 │    │
│ │ $45.99 • Dec 15                  │    │
│ │ 🏷 Groceries                     │    │
│ │ Created by: Maria                │    │
│ └──────────────────────────────────┘    │
│                                          │
│ Personal Expense                         │
│ ┌──────────────────────────────────┐    │
│ │ 🔒 Amazon                        │    │
│ │ Birthday gift for spouse         │    │
│ │ $89.99 • Dec 14                  │    │
│ │ 🏷 Personal • [Personal badge]   │    │
│ └──────────────────────────────────┘    │
└──────────────────────────────────────────┘
```

#### Visibility Filter Dropdown
```
┌────────────────────────┐
│ Filter by Visibility   │
│ ──────────────────     │
│ ○ All Expenses (42)    │
│ ○ Shared Only (28)     │
│ ○ My Personal (14)     │
│ ──────────────────     │
│ Show expenses from:    │
│ ☑ Me                   │
│ ☑ Other Members        │
└────────────────────────┘
```

### 3. Turbo/Stimulus Integration

#### Visibility Toggle Controller
```javascript
// app/javascript/controllers/visibility_toggle_controller.js
- Toggle animation (slide)
- Update help text dynamically
- Store preference in localStorage
- Sync with account defaults
- Visual feedback on change
```

#### Expense List Controller
```javascript
// app/javascript/controllers/expense_list_controller.js
- Checkbox selection management
- Bulk actions menu show/hide
- Filter application via Turbo
- Real-time count updates
- Infinite scroll with visibility
```

#### Turbo Streams for Privacy
- Stream visibility changes to all users
- Update totals when visibility changes
- Remove/add expenses from others' views
- Update badge counts in real-time

### 4. Visual Design Details

#### Visibility Indicators
```css
/* Personal expense badge */
.badge-personal {
  @apply bg-amber-100 text-amber-800 text-xs px-2 py-1 rounded-full;
}

/* Lock icon for personal */
.icon-personal {
  @apply text-amber-600 w-4 h-4 inline-block mr-1;
}

/* Shared expense (default, subtle) */
.expense-shared {
  @apply border-slate-200;
}

/* Personal expense card */
.expense-personal {
  @apply border-amber-200 bg-amber-50/50;
}
```

#### Toggle Switch Design
```css
/* Toggle track */
.toggle-track {
  @apply relative inline-flex h-6 w-11 items-center rounded-full;
  @apply bg-slate-200 transition-colors;
}

.toggle-track.personal {
  @apply bg-amber-600;
}

/* Toggle thumb */
.toggle-thumb {
  @apply inline-block h-5 w-5 rounded-full bg-white shadow-lg;
  @apply transform transition-transform;
}
```

### 5. Accessibility Requirements

#### Visibility Toggle ARIA
```html
<div role="group" aria-labelledby="visibility-label">
  <span id="visibility-label">Expense Visibility</span>
  <button role="switch"
          aria-checked="false"
          aria-label="Toggle between shared and personal">
    <span class="sr-only">Currently: Shared</span>
  </button>
</div>
```

#### Screen Reader Announcements
- "Expense visibility changed to personal"
- "Showing 14 personal expenses"
- "This expense is only visible to you"
- "Created by Maria, visible to everyone"

#### Keyboard Navigation
- Space/Enter toggles visibility switch
- Tab through filter options
- Arrow keys in dropdown menus
- Escape closes filter dropdown

### 6. Mobile-First Considerations

#### Mobile Visibility Toggle
```css
/* Large touch target */
.visibility-toggle-mobile {
  @apply min-h-[44px] w-full flex justify-between items-center;
  @apply px-4 py-3 bg-slate-50 rounded-lg;
}

/* Clear labeling */
.visibility-label-mobile {
  @apply text-base font-medium;
}
```

#### Responsive Expense Cards
```css
/* Mobile: Vertical layout */
@media (max-width: 640px) {
  .expense-card {
    @apply flex flex-col space-y-2;
  }
  
  .visibility-badge {
    @apply self-start;
  }
}

/* Desktop: Horizontal with right-aligned badge */
@media (min-width: 641px) {
  .expense-card {
    @apply flex justify-between items-center;
  }
  
  .visibility-badge {
    @apply ml-auto;
  }
}
```

### 7. Privacy Controls Interface

#### Account Default Settings
```
┌──────────────────────────────────────┐
│ Privacy Settings                     │
│ ────────────────────────────────     │
│                                      │
│ Default Expense Visibility           │
│ ○ Shared - Visible to all members   │
│ ● Personal - Only visible to me     │
│                                      │
│ Allow Others to See My:              │
│ ☑ Shared expense totals             │
│ ☑ Category breakdowns               │
│ ☐ Personal expense count            │
│                                      │
│ [Save Settings]                      │
└──────────────────────────────────────┘
```

#### Visibility Conflict Modal
```
┌──────────────────────────────────────┐
│ ⚠ Privacy Notice                    │
│ ────────────────────────────────     │
│                                      │
│ This expense uses a personal        │
│ category. Making it shared will:    │
│                                      │
│ • Make the expense visible to all   │
│ • Reveal the category name          │
│ • Include in shared reports         │
│                                      │
│ How would you like to proceed?      │
│                                      │
│ [Keep Personal]  [Make Shared]      │
└──────────────────────────────────────┘
```

### 8. Dashboard Privacy Widgets

#### Split Totals Widget
```
┌─────────────────────────────────────┐
│ This Month's Expenses               │
│ ───────────────────────────────     │
│                                     │
│ Total: $2,847.93                   │
│                                     │
│ 👥 Shared:    $2,134.50  (75%)    │
│ 🔒 Personal:  $  713.43  (25%)    │
│                                     │
│ [View Details →]                    │
└─────────────────────────────────────┘
```

#### Privacy Quick Stats
```
┌─────────────────────────────────────┐
│ Your Privacy Summary                │
│ ───────────────────────────────     │
│                                     │
│ • 28 shared expenses                │
│ • 14 personal expenses              │
│ • 3 private categories              │
│                                     │
│ Visibility Trend:                   │
│ [====||||────] 60% Shared          │
└─────────────────────────────────────┘
```

### 9. Bulk Operations Interface

#### Bulk Visibility Change
```javascript
// Selection feedback
"3 expenses selected"

// Confirmation dialog
confirmBulkVisibilityChange(count, newVisibility) {
  return `Change ${count} expenses to ${newVisibility}?
          This action cannot be undone for other users.`
}

// Success feedback
showToast(`✓ ${count} expenses updated to ${newVisibility}`)
```

#### Smart Defaults
- Remember last visibility choice per category
- Suggest visibility based on merchant
- Auto-personal for certain categories
- Quick toggle for last 5 expenses

### 10. Performance Optimizations

#### Visibility Caching
```javascript
// Cache visibility calculations
const visibilityCache = new Map()

function getVisibleExpenses(userId) {
  const cacheKey = `${userId}-${accountId}`
  if (visibilityCache.has(cacheKey)) {
    return visibilityCache.get(cacheKey)
  }
  // Calculate and cache
}
```

#### Lazy Loading
- Load personal expenses on demand
- Defer other users' expense details
- Progressive enhancement for filters
- Virtual scrolling for long lists

## Definition of Done
- [ ] Visibility system fully implemented
- [ ] All expenses properly filtered
- [ ] UI clearly indicates visibility
- [ ] Bulk operations working
- [ ] Authorization properly enforced
- [ ] All tests passing
- [ ] Performance benchmarks met
- [ ] Security audit completed
- [ ] Documentation updated
- [ ] Code reviewed and approved