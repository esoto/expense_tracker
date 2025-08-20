# Ticket 4.2: UI Polish and Account Management Interface

## Ticket Information
- **Epic**: Epic 4 - Polish and Migration (Weeks 7-8)
- **Priority**: HIGH
- **Story Points**: 5
- **Risk Level**: LOW
- **Dependencies**: 
  - All core functionality implemented
  - Design system established

## Description
Polish the user interface for multi-tenant features, focusing on account management, member administration, and account switching. Create intuitive interfaces that follow the Financial Confidence color palette and provide a seamless experience for managing multiple accounts and users.

## Technical Requirements
1. Create account management dashboard
2. Build member invitation and management UI
3. Implement smooth account switching
4. Add onboarding flow for new users
5. Create account settings interface
6. Polish responsive design

## Acceptance Criteria
- [ ] Account Dashboard includes:
  - Account overview with key metrics
  - Member list with roles and status
  - Recent activity feed
  - Quick actions (invite, settings, export)
  - Account type and limits display
- [ ] Account Switcher provides:
  - Dropdown in navigation bar
  - Account avatars/icons
  - Current account indicator
  - Quick search for many accounts
  - "Create New Account" option
- [ ] Member Management interface:
  - Searchable member list
  - Role badges with colors
  - Bulk actions for admins
  - Invitation status tracking
  - Activity indicators
- [ ] Onboarding Flow:
  - Welcome screen for new users
  - Account creation wizard
  - Invitation acceptance flow
  - Initial setup guidance
  - Feature tour option
- [ ] Account Settings page:
  - Account details editing
  - Default preferences
  - Billing/subscription info
  - Danger zone (delete account)
  - Export options

## Implementation Details
```erb
<!-- app/views/accounts/show.html.erb -->
<div class="container mx-auto px-4 py-8">
  <!-- Account Header -->
  <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 mb-6">
    <div class="flex items-center justify-between">
      <div class="flex items-center space-x-4">
        <div class="h-16 w-16 bg-teal-100 rounded-lg flex items-center justify-center">
          <svg class="h-8 w-8 text-teal-700"><!-- Account icon --></svg>
        </div>
        <div>
          <h1 class="text-2xl font-bold text-slate-900"><%= @account.name %></h1>
          <div class="flex items-center space-x-4 mt-1">
            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-teal-100 text-teal-800">
              <%= @account.account_type.humanize %>
            </span>
            <span class="text-sm text-slate-600">
              <%= @account.active_users.count %> / <%= @account.max_users %> members
            </span>
          </div>
        </div>
      </div>
      
      <% if current_membership.admin_or_owner? %>
        <div class="flex space-x-2">
          <%= link_to "Invite Member", new_account_invitation_path(@account),
                      class: "px-4 py-2 bg-teal-700 text-white rounded-lg hover:bg-teal-800 transition-colors" %>
          <%= link_to "Settings", edit_account_path(@account),
                      class: "px-4 py-2 bg-slate-200 text-slate-700 rounded-lg hover:bg-slate-300 transition-colors" %>
        </div>
      <% end %>
    </div>
  </div>
  
  <!-- Stats Grid -->
  <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
    <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-4">
      <div class="flex items-center justify-between">
        <div>
          <p class="text-sm text-slate-600">This Month</p>
          <p class="text-2xl font-bold text-slate-900">
            <%= number_to_currency(@current_month_total) %>
          </p>
        </div>
        <div class="h-12 w-12 bg-emerald-100 rounded-lg flex items-center justify-center">
          <svg class="h-6 w-6 text-emerald-600"><!-- Chart icon --></svg>
        </div>
      </div>
    </div>
    
    <!-- More stat cards... -->
  </div>
  
  <!-- Members Section -->
  <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 mb-6">
    <div class="flex items-center justify-between mb-4">
      <h2 class="text-lg font-semibold text-slate-900">Team Members</h2>
      <% if @pending_invitations.any? %>
        <span class="text-sm text-amber-600">
          <%= @pending_invitations.count %> pending invitations
        </span>
      <% end %>
    </div>
    
    <div class="space-y-3">
      <% @members.each do |membership| %>
        <div class="flex items-center justify-between p-3 hover:bg-slate-50 rounded-lg transition-colors">
          <div class="flex items-center space-x-3">
            <div class="h-10 w-10 bg-slate-200 rounded-full flex items-center justify-center">
              <span class="text-sm font-medium text-slate-700">
                <%= membership.user.name.first.upcase %>
              </span>
            </div>
            <div>
              <div class="flex items-center space-x-2">
                <p class="font-medium text-slate-900"><%= membership.user.name %></p>
                <%= render 'shared/role_badge', role: membership.role %>
              </div>
              <p class="text-sm text-slate-600"><%= membership.user.email %></p>
            </div>
          </div>
          
          <div class="flex items-center space-x-4">
            <div class="text-right">
              <p class="text-sm text-slate-600">Joined</p>
              <p class="text-sm font-medium text-slate-900">
                <%= membership.joined_at.strftime("%b %d, %Y") %>
              </p>
            </div>
            
            <% if current_membership.owner? && membership.user != current_user %>
              <div class="relative" data-controller="dropdown">
                <button class="p-2 hover:bg-slate-100 rounded-lg">
                  <svg class="h-5 w-5 text-slate-600"><!-- More icon --></svg>
                </button>
                <!-- Dropdown menu -->
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
  </div>
</div>

<!-- app/views/shared/_account_switcher.html.erb -->
<div class="relative" data-controller="account-switcher">
  <button data-action="click->account-switcher#toggle"
          class="flex items-center space-x-2 px-3 py-2 rounded-lg hover:bg-slate-100 transition-colors">
    <div class="h-8 w-8 bg-teal-100 rounded flex items-center justify-center">
      <span class="text-xs font-medium text-teal-700">
        <%= current_account.name.first.upcase %>
      </span>
    </div>
    <span class="text-sm font-medium text-slate-900">
      <%= current_account.name %>
    </span>
    <svg class="h-4 w-4 text-slate-600"><!-- Chevron down --></svg>
  </button>
  
  <div data-account-switcher-target="dropdown"
       class="hidden absolute right-0 mt-2 w-64 bg-white rounded-lg shadow-lg border border-slate-200 py-2 z-50">
    <div class="px-3 py-2 border-b border-slate-200">
      <p class="text-xs text-slate-600 uppercase tracking-wider">Switch Account</p>
    </div>
    
    <div class="max-h-64 overflow-y-auto">
      <% current_user.active_accounts.each do |account| %>
        <%= link_to switch_account_path(account), method: :post,
                    class: "flex items-center px-3 py-2 hover:bg-slate-50 transition-colors" do %>
          <div class="h-8 w-8 bg-slate-100 rounded flex items-center justify-center mr-3">
            <span class="text-xs font-medium text-slate-700">
              <%= account.name.first.upcase %>
            </span>
          </div>
          <div class="flex-1">
            <p class="text-sm font-medium text-slate-900"><%= account.name %></p>
            <p class="text-xs text-slate-600"><%= account.account_type.humanize %></p>
          </div>
          <% if account == current_account %>
            <svg class="h-4 w-4 text-teal-600"><!-- Check icon --></svg>
          <% end %>
        <% end %>
      <% end %>
    </div>
    
    <div class="border-t border-slate-200 px-3 py-2">
      <%= link_to new_account_path,
                  class: "flex items-center space-x-2 text-sm text-teal-700 hover:text-teal-800" do %>
        <svg class="h-4 w-4"><!-- Plus icon --></svg>
        <span>Create New Account</span>
      <% end %>
    </div>
  </div>
</div>
```

```javascript
// app/javascript/controllers/account_switcher_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown"]
  
  connect() {
    this.closeOnOutsideClick = this.closeOnOutsideClick.bind(this)
  }
  
  toggle(event) {
    event.preventDefault()
    
    if (this.dropdownTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }
  
  open() {
    this.dropdownTarget.classList.remove("hidden")
    document.addEventListener("click", this.closeOnOutsideClick)
  }
  
  close() {
    this.dropdownTarget.classList.add("hidden")
    document.removeEventListener("click", this.closeOnOutsideClick)
  }
  
  closeOnOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }
  
  disconnect() {
    document.removeEventListener("click", this.closeOnOutsideClick)
  }
}
```

## UI Components Required
- [ ] Account avatar component
- [ ] Role badge component
- [ ] Member card component
- [ ] Invitation status indicator
- [ ] Account type selector
- [ ] Permission matrix display
- [ ] Activity timeline
- [ ] Quick stats cards
- [ ] Empty states
- [ ] Loading states

## Responsive Design Requirements
- [ ] Mobile-optimized account switcher
- [ ] Touch-friendly member actions
- [ ] Responsive stat grid
- [ ] Collapsible navigation
- [ ] Mobile-first forms
- [ ] Tablet layout optimization

## Accessibility Requirements
- [ ] ARIA labels for all interactive elements
- [ ] Keyboard navigation support
- [ ] Screen reader friendly
- [ ] Color contrast compliance
- [ ] Focus indicators
- [ ] Error message association

## Testing Requirements
- [ ] Component specs:
  - Account switcher functionality
  - Member management actions
  - Form validations
- [ ] System specs:
  - Complete account management flow
  - Member invitation journey
  - Account switching scenarios
- [ ] Visual regression tests:
  - All account views
  - Responsive breakpoints
  - Dark mode (if applicable)
- [ ] Accessibility tests:
  - Keyboard navigation
  - Screen reader compatibility

## Performance Considerations
- [ ] Lazy load member avatars
- [ ] Cache account data
- [ ] Optimize dropdown queries
- [ ] Debounce search inputs
- [ ] Virtual scrolling for long lists

## UX Implementation

### 1. User Flow Specifications

#### First-Time Account Setup
1. **Registration Complete** → Welcome screen
2. **Account Type Selection**:
   - Personal (single user)
   - Family (2-5 users)
   - Group (6+ users)
3. **Initial Configuration**:
   - Account name
   - Currency preference
   - Privacy defaults
4. **Quick Tour** (optional):
   - Interactive tooltips
   - Feature highlights
   - Skip option always visible
5. **First Action Prompt**:
   - Add first expense
   - Invite family member
   - Connect bank account

#### Account Switching Experience
1. **Current Account Display** in navbar
2. **Click/Tap** account name
3. **Smooth Dropdown Animation** (150ms)
4. **Account List** with:
   - Visual hierarchy (owned first)
   - Member count badges
   - Activity indicators
5. **Selection** → Brief loading state
6. **Context Switch**:
   - Update all UI elements
   - Maintain scroll position
   - Show confirmation toast

#### Member Onboarding Flow
1. **Accept Invitation** → Landing page
2. **Join Account** confirmation
3. **Role Explanation** with visuals
4. **Personalization**:
   - Profile photo upload
   - Notification preferences
   - Privacy settings
5. **First Steps Guide**:
   - View shared expenses
   - Add first expense
   - Explore features

### 2. Comprehensive Dashboard Layout

```
┌────────────────────────────────────────────┐
│ [Logo] Garcia Family Account    [▼]  [👤]  │
├────────────────────────────────────────────┤
│                                            │
│ Welcome back, Maria!                      │
│ ──────────────────────────────────         │
│                                            │
│ ┌──────────┐ ┌──────────┐ ┌──────────┐   │
│ │ $3,847   │ │ 156      │ │ 4        │   │
│ │ This     │ │ Total    │ │ Active   │   │
│ │ Month    │ │ Expenses │ │ Members  │   │
│ └──────────┘ └──────────┘ └──────────┘   │
│                                            │
│ Quick Actions                              │
│ ┌────────────────────────────────────┐    │
│ │ [+] Add Expense                    │    │
│ │ [👥] Invite Member                 │    │
│ │ [📊] View Reports                  │    │
│ │ [⚙] Account Settings               │    │
│ └────────────────────────────────────┘    │
│                                            │
│ Recent Activity                            │
│ ┌────────────────────────────────────┐    │
│ │ • John added $45.99 expense       │    │
│ │ • Sarah joined the account        │    │
│ │ • Monthly report available        │    │
│ └────────────────────────────────────┘    │
│                                            │
│ Team Overview                              │
│ ┌────────────────────────────────────┐    │
│ │ [Avatar] John - Owner             │    │
│ │ [Avatar] Maria - Admin            │    │
│ │ [Avatar] Sarah - Member           │    │
│ │ [Avatar] David - Viewer           │    │
│ │                                    │    │
│ │ [+ Invite New Member]             │    │
│ └────────────────────────────────────┘    │
└────────────────────────────────────────────┘
```

### 3. Enhanced Account Switcher

#### Desktop Account Switcher
```
┌─────────────────────────────────┐
│ Current Account                 │
│ ┌─────────────────────────────┐ │
│ │ 🏠 Garcia Family           │ │
│ │    4 members • Owner       │ │
│ └─────────────────────────────┘ │
│                                 │
│ Your Accounts                   │
│ ────────────────               │
│ ┌─────────────────────────────┐ │
│ │ 👤 Personal Account        │ │
│ │    Just you • Owner        │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 💼 Work Expenses           │ │
│ │    12 members • Member     │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ + Create New Account       │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ ⚙ Manage All Accounts      │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

#### Mobile Account Switcher (Bottom Sheet)
```
┌─────────────────────────────────┐
│ ═══════════════                │  <- Drag handle
│                                 │
│ Switch Account                  │
│ ──────────────                  │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ ✓ Garcia Family            │ │
│ │   Current account          │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │   Personal Account         │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │   Work Expenses            │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ + Create New               │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

### 4. Member Management Interface

#### Enhanced Member Cards
```
┌──────────────────────────────────────┐
│ Team Members                         │
│ ────────────────────────────────     │
│                                      │
│ ┌──────────────────────────────────┐│
│ │ [Photo]  John Smith              ││
│ │          john@email.com          ││
│ │                                   ││
│ │ [Owner] [Online now]             ││
│ │                                   ││
│ │ Stats this month:                ││
│ │ • 42 expenses added              ││
│ │ • $1,234 total                   ││
│ │                                   ││
│ │ Joined: Jan 15, 2024             ││
│ │                                   ││
│ │ [Message] [Change Role] [Remove] ││
│ └──────────────────────────────────┘│
└──────────────────────────────────────┘
```

### 5. Onboarding Components

#### Welcome Tour Overlay
```javascript
// Progressive disclosure tour
const tourSteps = [
  {
    target: '.add-expense-btn',
    title: 'Track Your Expenses',
    content: 'Click here to add your first expense',
    position: 'bottom'
  },
  {
    target: '.account-switcher',
    title: 'Multiple Accounts',
    content: 'Switch between your accounts here',
    position: 'left'
  },
  {
    target: '.invite-button',
    title: 'Collaborate',
    content: 'Invite family members to share expenses',
    position: 'top'
  }
]
```

#### Empty State Designs
```
┌─────────────────────────────────────┐
│                                     │
│        [Illustration]               │
│                                     │
│    No expenses yet!                │
│                                     │
│    Start tracking your spending     │
│    to see insights and trends       │
│                                     │
│    ┌─────────────────────┐         │
│    │   Add First Expense │         │
│    └─────────────────────┘         │
│                                     │
│    or                               │
│                                     │
│    [Import from Bank]               │
└─────────────────────────────────────┘
```

### 6. Settings Interface

#### Account Settings Organization
```
┌──────────────────────────────────────┐
│ Account Settings                     │
│ ────────────────────────────────     │
│                                      │
│ ┌──────────────────────────────────┐│
│ │ General                          ││
│ │ • Account name                   ││
│ │ • Account type                   ││
│ │ • Currency                       ││
│ │ • Time zone                      ││
│ └──────────────────────────────────┘│
│                                      │
│ ┌──────────────────────────────────┐│
│ │ Privacy & Sharing                ││
│ │ • Default expense visibility     ││
│ │ • Member permissions             ││
│ │ • Data sharing preferences       ││
│ └──────────────────────────────────┘│
│                                      │
│ ┌──────────────────────────────────┐│
│ │ Notifications                    ││
│ │ • Email notifications            ││
│ │ • In-app notifications           ││
│ │ • Weekly summaries               ││
│ └──────────────────────────────────┘│
│                                      │
│ ┌──────────────────────────────────┐│
│ │ Billing & Subscription           ││
│ │ • Current plan: Family           ││
│ │ • Members: 4/5                   ││
│ │ • [Upgrade Plan]                 ││
│ └──────────────────────────────────┘│
│                                      │
│ ┌──────────────────────────────────┐│
│ │ ⚠ Danger Zone                    ││
│ │ • Export all data                ││
│ │ • Transfer ownership             ││
│ │ • Delete account                 ││
│ └──────────────────────────────────┘│
└──────────────────────────────────────┘
```

### 7. Responsive Design Patterns

#### Breakpoint Behaviors
```css
/* Mobile: 0-640px */
- Single column layout
- Bottom navigation
- Full-width cards
- Collapsed sidebars

/* Tablet: 641-1024px */
- Two column layout
- Side navigation
- Card grid (2 columns)
- Expandable sidebars

/* Desktop: 1025px+ */
- Three column layout
- Persistent navigation
- Card grid (3-4 columns)
- Fixed sidebars
```

### 8. Micro-interactions

#### Account Switch Animation
```javascript
// Smooth transition between accounts
async function switchAccount(accountId) {
  // 1. Fade out current content (100ms)
  await fadeOut('.account-content')
  
  // 2. Show loading spinner (instant)
  showSpinner()
  
  // 3. Load new account data
  const data = await loadAccount(accountId)
  
  // 4. Update DOM
  updateContent(data)
  
  // 5. Fade in new content (150ms)
  await fadeIn('.account-content')
  
  // 6. Show success toast
  showToast(`Switched to ${data.name}`)
}
```

#### Button States and Feedback
```css
/* Default state */
.btn-primary {
  @apply bg-teal-700 text-white;
  transition: all 150ms ease;
}

/* Hover state */
.btn-primary:hover {
  @apply bg-teal-800;
  transform: translateY(-1px);
  box-shadow: 0 4px 6px rgba(0,0,0,0.1);
}

/* Active state */
.btn-primary:active {
  transform: translateY(0);
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

/* Loading state */
.btn-primary.loading {
  @apply bg-teal-600 cursor-wait;
  position: relative;
  color: transparent;
}

.btn-primary.loading::after {
  content: "";
  @apply absolute inset-0 m-auto;
  @apply w-4 h-4 border-2 border-white;
  @apply border-t-transparent rounded-full;
  animation: spin 0.6s linear infinite;
}
```

### 9. Activity Feed Design

#### Real-time Activity Stream
```
┌────────────────────────────────────┐
│ Activity Feed                      │
│ ──────────────                     │
│                                    │
│ Today                              │
│ ┌──────────────────────────────┐  │
│ │ 10:32 AM                     │  │
│ │ 🧾 John added expense        │  │
│ │ Walmart - $67.89             │  │
│ └──────────────────────────────┘  │
│                                    │
│ ┌──────────────────────────────┐  │
│ │ 9:15 AM                      │  │
│ │ 👤 Sarah joined as Member    │  │
│ │ Invited by Maria             │  │
│ └──────────────────────────────┘  │
│                                    │
│ Yesterday                          │
│ ┌──────────────────────────────┐  │
│ │ 3:24 PM                      │  │
│ │ 📊 Monthly report ready      │  │
│ │ December 2024                │  │
│ │ [View Report]                │  │
│ └──────────────────────────────┘  │
│                                    │
│ [Load More...]                     │
└────────────────────────────────────┘
```

### 10. Error States and Recovery

#### Connection Error
```
┌──────────────────────────────────┐
│ ⚠ Connection Issue              │
│ ──────────────────────────────   │
│                                  │
│ Unable to sync with server       │
│                                  │
│ Your changes are saved locally   │
│ and will sync when connected     │
│                                  │
│ [Retry Now]  [Work Offline]     │
└──────────────────────────────────┘
```

#### Permission Error
```
┌──────────────────────────────────┐
│ 🔒 Access Restricted            │
│ ──────────────────────────────   │
│                                  │
│ You need admin permissions to    │
│ access account settings          │
│                                  │
│ [Request Access]  [Go Back]      │
└──────────────────────────────────┘
```

### 11. Performance Optimizations

#### Lazy Loading Strategy
```javascript
// Progressive image loading
const imageObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        const img = entry.target
        img.src = img.dataset.src
        img.classList.add('loaded')
        imageObserver.unobserve(img)
      }
    })
  },
  { rootMargin: '50px' }
)

// Virtual scrolling for member lists
const virtualScroll = new VirtualScroll({
  itemHeight: 80,
  buffer: 5,
  container: '.member-list'
})
```

### 12. Accessibility Enhancements

#### Focus Management
```javascript
// Trap focus in modals
function trapFocus(element) {
  const focusableElements = element.querySelectorAll(
    'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
  )
  const firstElement = focusableElements[0]
  const lastElement = focusableElements[focusableElements.length - 1]
  
  element.addEventListener('keydown', (e) => {
    if (e.key === 'Tab') {
      if (e.shiftKey && document.activeElement === firstElement) {
        lastElement.focus()
        e.preventDefault()
      } else if (!e.shiftKey && document.activeElement === lastElement) {
        firstElement.focus()
        e.preventDefault()
      }
    }
  })
}
```

#### Screen Reader Announcements
```html
<!-- Live region for dynamic updates -->
<div aria-live="polite" aria-atomic="true" class="sr-only">
  <span id="status-message"></span>
</div>

<!-- Account switch announcement -->
<script>
function announceAccountSwitch(accountName) {
  document.getElementById('status-message').textContent = 
    `Switched to ${accountName} account`
}
</script>
```

## Definition of Done
- [ ] All UI components implemented
- [ ] Responsive design working
- [ ] Accessibility standards met
- [ ] Smooth animations/transitions
- [ ] Empty states handled
- [ ] Loading states implemented
- [ ] Error states designed
- [ ] All tests passing
- [ ] Design review completed
- [ ] Code reviewed and approved
- [ ] Documentation updated