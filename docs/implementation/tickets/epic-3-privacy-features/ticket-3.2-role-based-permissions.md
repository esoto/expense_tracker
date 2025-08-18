# Ticket 3.2: Implement Role-Based Permissions System

## Ticket Information
- **Epic**: Epic 3 - Privacy Features (Weeks 5-6)
- **Priority**: HIGH
- **Story Points**: 5
- **Risk Level**: MEDIUM
- **Dependencies**: 
  - Ticket 3.1 (Expense Visibility System)

## Description
Implement a comprehensive role-based access control (RBAC) system for account members. Define permissions for each role (Owner, Admin, Member, Viewer) and enforce these permissions throughout the application. This includes UI elements, API endpoints, and background processes.

## Technical Requirements
1. Define permission matrix for all roles
2. Implement permission checking methods
3. Create authorization policies
4. Update UI to show/hide based on permissions
5. Add role management interface
6. Implement permission inheritance

## Acceptance Criteria
- [ ] Permission matrix fully defined:
  - Owner: Full access to everything
  - Admin: Manage expenses, categories, and settings
  - Member: Create and edit own expenses, view shared
  - Viewer: Read-only access to shared expenses
- [ ] AccountMembership model enhanced:
  - Permission checking methods (can?, cannot?)
  - Custom permission overrides via JSONB
  - Permission caching for performance
  - Audit trail for permission changes
- [ ] Authorization policies implemented:
  - ExpensePolicy for expense operations
  - CategoryPolicy for category management
  - AccountPolicy for account settings
  - MembershipPolicy for user management
- [ ] UI respects permissions:
  - Hide unauthorized actions
  - Disable buttons appropriately
  - Show permission-based messages
  - Role badges on member list
- [ ] Role management interface:
  - Change member roles (owner/admin only)
  - View permission details
  - Transfer ownership functionality
  - Audit log of role changes

## Implementation Details
```ruby
# app/models/account_membership.rb (enhanced)
class AccountMembership < ApplicationRecord
  # Permission matrix
  PERMISSION_MATRIX = {
    owner: {
      expenses: [:create, :read, :update, :delete, :export, :bulk_update],
      categories: [:create, :read, :update, :delete, :merge],
      members: [:invite, :remove, :update_role, :view_all],
      settings: [:read, :update, :delete_account],
      email_accounts: [:create, :read, :update, :delete, :sync],
      reports: [:view_all, :export, :share],
      budgets: [:create, :read, :update, :delete]
    },
    admin: {
      expenses: [:create, :read, :update, :delete, :export, :bulk_update],
      categories: [:create, :read, :update, :merge],
      members: [:invite, :view_all],
      settings: [:read, :update],
      email_accounts: [:create, :read, :update, :sync],
      reports: [:view_all, :export],
      budgets: [:create, :read, :update]
    },
    member: {
      expenses: [:create, :read, :update_own, :delete_own, :export_own],
      categories: [:read],
      members: [:view_basic],
      settings: [:read],
      email_accounts: [:read],
      reports: [:view_own, :export_own],
      budgets: [:read]
    },
    viewer: {
      expenses: [:read],
      categories: [:read],
      members: [:view_basic],
      settings: [],
      email_accounts: [],
      reports: [:view_shared],
      budgets: [:read]
    }
  }.freeze
  
  # Cache permissions in memory
  def permissions
    @permissions ||= build_permissions
  end
  
  def can?(action, resource)
    return false unless permissions[resource]
    
    action = action.to_sym
    resource = resource.to_sym
    
    # Check base permissions
    return true if permissions[resource].include?(action)
    
    # Check ownership-based permissions
    if action.to_s.end_with?('_own')
      base_action = action.to_s.sub('_own', '').to_sym
      return permissions[resource].include?(base_action)
    end
    
    # Check custom permission overrides
    custom_permissions.dig(resource.to_s, action.to_s) == true
  end
  
  def cannot?(action, resource)
    !can?(action, resource)
  end
  
  def admin_or_owner?
    owner? || admin?
  end
  
  def update_role!(new_role, changed_by:)
    old_role = role
    
    ActiveRecord::Base.transaction do
      # Prevent removing last owner
      if owner? && new_role != 'owner'
        other_owners = account.account_memberships.owners.where.not(id: id)
        raise "Cannot remove last owner" if other_owners.empty?
      end
      
      update!(role: new_role)
      
      # Log the change
      AuditLog.create!(
        account: account,
        user: changed_by,
        action: 'role_changed',
        auditable: self,
        metadata: {
          old_role: old_role,
          new_role: new_role,
          changed_by_id: changed_by.id
        }
      )
    end
  end
  
  def add_custom_permission!(resource, action)
    self.custom_permissions ||= {}
    self.custom_permissions[resource.to_s] ||= []
    self.custom_permissions[resource.to_s] << action.to_s
    self.custom_permissions[resource.to_s].uniq!
    save!
    clear_permission_cache
  end
  
  def remove_custom_permission!(resource, action)
    return unless custom_permissions
    
    self.custom_permissions[resource.to_s]&.delete(action.to_s)
    save!
    clear_permission_cache
  end
  
  private
  
  def build_permissions
    base = PERMISSION_MATRIX[role.to_sym] || {}
    
    # Merge custom permissions
    if custom_permissions.present?
      custom_permissions.each do |resource, actions|
        base[resource.to_sym] ||= []
        base[resource.to_sym] += actions.map(&:to_sym)
        base[resource.to_sym].uniq!
      end
    end
    
    base
  end
  
  def clear_permission_cache
    @permissions = nil
  end
end

# app/policies/application_policy.rb
class ApplicationPolicy
  attr_reader :user, :record, :membership
  
  def initialize(user, record)
    @user = user
    @record = record
    @membership = user.account_memberships.find_by(
      account_id: record.try(:account_id)
    )
  end
  
  def index?
    membership.present?
  end
  
  def show?
    membership.present?
  end
  
  def create?
    membership&.can?(:create, resource_name)
  end
  
  def update?
    membership&.can?(:update, resource_name)
  end
  
  def destroy?
    membership&.can?(:delete, resource_name)
  end
  
  private
  
  def resource_name
    record.class.name.underscore.pluralize.to_sym
  end
end

# app/policies/expense_policy.rb
class ExpensePolicy < ApplicationPolicy
  def show?
    return false unless membership
    record.visible_to?(user)
  end
  
  def update?
    return false unless membership
    
    # Check visibility first
    return false unless record.visible_to?(user)
    
    # Owner can always edit their expenses
    return true if record.user_id == user.id
    
    # Check role-based permissions for shared expenses
    if record.shared?
      membership.can?(:update, :expenses)
    else
      false # Can't edit others' personal expenses
    end
  end
  
  def destroy?
    return false unless membership
    
    # Only creator or account owner can delete
    record.user_id == user.id || membership.owner?
  end
  
  def export?
    membership&.can?(:export, :expenses)
  end
  
  def bulk_update?
    membership&.can?(:bulk_update, :expenses)
  end
end

# app/controllers/application_controller.rb (updated)
class ApplicationController < ActionController::Base
  include Pundit::Authorization
  
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  
  private
  
  def user_not_authorized(exception)
    policy_name = exception.policy.class.to_s.underscore
    
    flash[:alert] = t "#{policy_name}.#{exception.query}", 
                      scope: "pundit", 
                      default: :default
    redirect_to(request.referrer || root_path)
  end
end

# app/controllers/members_controller.rb
class MembersController < ApplicationController
  before_action :require_account_access!
  before_action :set_member, only: [:show, :update_role, :remove]
  
  def index
    authorize AccountMembership
    
    @members = current_account.account_memberships
                             .includes(:user)
                             .order(:role, :joined_at)
    
    # Filter based on permissions
    unless current_membership.can?(:view_all, :members)
      @members = @members.where(active: true)
    end
  end
  
  def update_role
    authorize @member, :update?
    
    if @member.update_role!(params[:role], changed_by: current_user)
      redirect_to members_path, notice: "Role updated successfully"
    else
      redirect_to members_path, alert: "Could not update role"
    end
  end
  
  def remove
    authorize @member, :destroy?
    
    if @member.destroy
      redirect_to members_path, notice: "Member removed"
    else
      redirect_to members_path, alert: "Could not remove member"
    end
  end
  
  private
  
  def set_member
    @member = current_account.account_memberships.find(params[:id])
  end
end
```

## UI/UX Requirements
- [ ] Member list displays:
  - User name and email
  - Role badge with color coding
  - Join date
  - Last active indicator
  - Action buttons based on permissions
- [ ] Role management interface:
  - Dropdown to change roles
  - Confirmation dialog for changes
  - Permission preview on hover
  - Disabled for last owner
- [ ] Permission indicators:
  - Lock icons for restricted features
  - Tooltips explaining permissions
  - "Upgrade role" prompts
  - Clear permission denied messages
- [ ] Navigation adjusts to role:
  - Hide unauthorized menu items
  - Show role-appropriate dashboard
  - Conditional action buttons

## Testing Requirements
- [ ] Model specs for permissions:
  - Permission matrix validation
  - can?/cannot? methods
  - Custom permission overrides
  - Role change validations
- [ ] Policy specs:
  - Each policy fully tested
  - Edge cases covered
  - Ownership-based rules
- [ ] Controller specs:
  - Authorization for all actions
  - Proper redirects for unauthorized
  - Role change functionality
- [ ] Feature specs:
  - Complete permission workflows
  - UI respects permissions
  - Role switching scenarios

## Security Considerations
- [ ] Permissions checked at multiple levels
- [ ] No permission elevation vulnerabilities
- [ ] Audit all permission changes
- [ ] Prevent last owner removal
- [ ] Session invalidation on role change

## Performance Considerations
- [ ] Cache permissions per request
- [ ] Optimize permission queries
- [ ] Batch permission checks
- [ ] Index role lookups

## UX Implementation

### 1. User Flow Specifications

#### Role Change Flow (Owner/Admin)
1. **Members Page** → Click member's role badge
2. **Role Selector Dropdown** appears
3. Hover over roles → See permission preview
4. Select new role → Confirmation dialog
5. Confirm → Processing spinner
6. **Success Path**:
   - Role badge updates
   - Toast: "Role updated to [Role]"
   - Activity logged
7. **Error Path**:
   - Last owner protection
   - Error message with explanation

#### Permission-Based Navigation
1. **User logs in** → Role determined
2. **Navigation adapts**:
   - Owners: Full menu visible
   - Admins: Settings (no delete)
   - Members: Basic features only
   - Viewers: Read-only indicators
3. **Attempting restricted action**:
   - Gentle explanation modal
   - Suggest contacting admin
   - Option to request permission

#### Transfer Ownership Flow
1. **Account Settings** → "Transfer Ownership"
2. **Warning Modal** with implications
3. Select new owner from member list
4. Enter account password for confirmation
5. Final confirmation with countdown
6. Transfer complete → Role swap animation

### 2. UI Component Specifications

#### Member List with Role Management
```
┌──────────────────────────────────────────┐
│ Team Members (4)                         │
│ ────────────────────────────────────────│
│                                          │
│ ┌────────────────────────────────────┐  │
│ │ [Avatar] John Smith                │  │
│ │ john@example.com                   │  │
│ │ [Owner badge] • Joined Jan 2024    │  │
│ │                    [⋮ Actions]     │  │
│ └────────────────────────────────────┘  │
│                                          │
│ ┌────────────────────────────────────┐  │
│ │ [Avatar] Maria Garcia              │  │
│ │ maria@example.com                  │  │
│ │ [Admin badge] • Joined Feb 2024    │  │
│ │                    [⋮ Actions]     │  │
│ └────────────────────────────────────┘  │
│                                          │
│ ┌────────────────────────────────────┐  │
│ │ [Avatar] David Chen                │  │
│ │ david@example.com                  │  │
│ │ [Member badge] • Joined Mar 2024   │  │
│ │                    [⋮ Actions]     │  │
│ └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

#### Role Selector with Permissions Preview
```
┌─────────────────────────────────────────┐
│ Change Role for Maria Garcia           │
│ ───────────────────────────────────────│
│                                         │
│ Current Role: Member                    │
│                                         │
│ Select New Role:                        │
│                                         │
│ ┌───────────────────────────────────┐  │
│ │ ○ Owner                           │  │
│ │   Full control of account         │  │
│ │   • Manage all settings           │  │
│ │   • Delete account                │  │
│ │   • Transfer ownership            │  │
│ └───────────────────────────────────┘  │
│                                         │
│ ┌───────────────────────────────────┐  │
│ │ ● Admin                           │  │
│ │   Manage expenses & members       │  │
│ │   • Create/edit all expenses      │  │
│ │   • Invite new members            │  │
│ │   • Cannot delete account         │  │
│ └───────────────────────────────────┘  │
│                                         │
│ ┌───────────────────────────────────┐  │
│ │ ○ Member                          │  │
│ │   Basic expense management        │  │
│ │   • Create own expenses           │  │
│ │   • View shared expenses          │  │
│ │   • Cannot invite members         │  │
│ └───────────────────────────────────┘  │
│                                         │
│ ┌───────────────────────────────────┐  │
│ │ ○ Viewer                          │  │
│ │   Read-only access                │  │
│ │   • View shared expenses only     │  │
│ │   • Cannot create or edit         │  │
│ │   • Cannot export data            │  │
│ └───────────────────────────────────┘  │
│                                         │
│ [Cancel]            [Update Role]      │
└─────────────────────────────────────────┘
```

#### Permission Denied Modal
```
┌──────────────────────────────────────┐
│ 🔒 Permission Required               │
│ ────────────────────────────────     │
│                                      │
│ This action requires Admin          │
│ permissions                          │
│                                      │
│ You need admin access to:           │
│ • Invite new members                │
│                                      │
│ Your current role: Member            │
│                                      │
│ Would you like to:                  │
│ • Contact an admin                  │
│ • Request permission upgrade        │
│                                      │
│ [Got it]     [Request Access]       │
└──────────────────────────────────────┘
```

### 3. Visual Permission Indicators

#### Role Badges Design
```css
/* Owner badge - Purple for highest privilege */
.badge-owner {
  @apply bg-purple-100 text-purple-800 font-semibold;
  @apply px-2 py-1 rounded-full text-xs;
}

/* Admin badge - Teal for management */
.badge-admin {
  @apply bg-teal-100 text-teal-800 font-medium;
}

/* Member badge - Slate for standard */
.badge-member {
  @apply bg-slate-100 text-slate-700;
}

/* Viewer badge - Amber for limited */
.badge-viewer {
  @apply bg-amber-100 text-amber-700;
}
```

#### Disabled State Styling
```css
/* Disabled buttons for insufficient permissions */
.btn-disabled-permission {
  @apply opacity-50 cursor-not-allowed;
  @apply hover:bg-current; /* No hover effect */
}

/* Lock icon overlay */
.permission-locked::after {
  content: "🔒";
  @apply absolute top-0 right-0 text-xs;
}
```

### 4. Turbo/Stimulus Integration

#### Role Manager Controller
```javascript
// app/javascript/controllers/role_manager_controller.js
- Role selection with preview
- Confirmation before change
- Optimistic UI update
- Rollback on error
- Activity stream update
```

#### Permission Check Controller
```javascript
// app/javascript/controllers/permission_check_controller.js
- Check permissions on load
- Show/hide elements based on role
- Display tooltips for locked features
- Track permission denial events
```

### 5. Navigation Adaptation

#### Dynamic Menu Based on Role
```erb
<!-- Owner sees all -->
<% if current_membership.owner? %>
  <%= link_to "Settings", account_settings_path %>
  <%= link_to "Billing", billing_path %>
  <%= link_to "Delete Account", delete_account_path %>
<% end %>

<!-- Admin sees most -->
<% if current_membership.admin_or_owner? %>
  <%= link_to "Invite Members", new_invitation_path %>
  <%= link_to "Categories", categories_path %>
<% end %>

<!-- Member sees basics -->
<% if current_membership.can?(:create, :expenses) %>
  <%= link_to "Add Expense", new_expense_path %>
<% end %>

<!-- Viewer sees minimal -->
<% if current_membership.viewer? %>
  <span class="text-amber-600">Read-only Mode</span>
<% end %>
```

### 6. Accessibility Requirements

#### ARIA for Role Changes
```html
<div role="radiogroup" aria-label="Select user role">
  <div role="radio" 
       aria-checked="false"
       aria-describedby="owner-desc">
    <span id="owner-desc">Full account control</span>
  </div>
</div>
```

#### Screen Reader Announcements
- "Role changed to Admin"
- "You don't have permission for this action"
- "Member role: Can create and edit own expenses"
- "Warning: Changing to Viewer will limit access"

### 7. Mobile Considerations

#### Mobile Role Selector
```css
/* Full-screen modal on mobile */
@media (max-width: 640px) {
  .role-selector {
    @apply fixed inset-0 z-50;
    @apply bg-white p-4;
  }
  
  .role-option {
    @apply p-4 border-b;
    @apply min-h-[60px]; /* Large touch target */
  }
}
```

#### Responsive Permission Messages
- Short messages on mobile
- Full explanations on desktop
- Icon-first approach
- Swipe actions for role changes

### 8. Permission-Based UI States

#### Expense Actions by Role
```html
<!-- Owner/Admin: Full actions -->
<div class="expense-actions">
  <button>Edit</button>
  <button>Delete</button>
  <button>Duplicate</button>
</div>

<!-- Member: Own expense -->
<div class="expense-actions">
  <button>Edit</button>
  <button>Delete</button>
</div>

<!-- Member: Others' expense -->
<div class="expense-actions">
  <button disabled title="Not your expense">Edit</button>
</div>

<!-- Viewer: All expenses -->
<div class="expense-actions">
  <span class="text-slate-500">View only</span>
</div>
```

### 9. Activity Feed Integration

#### Role Change Activity
```
┌────────────────────────────────────┐
│ Recent Activity                    │
│ ──────────────────────────────     │
│                                    │
│ 🔄 John changed Maria's role      │
│    from Member to Admin           │
│    2 minutes ago                  │
│                                    │
│ 👤 Sarah joined as Member         │
│    Invited by John                │
│    1 hour ago                     │
│                                    │
│ 🔐 David's permissions updated    │
│    Can now export reports         │
│    Yesterday                      │
└────────────────────────────────────┘
```

### 10. Custom Permissions Interface

#### Advanced Permissions (Owner Only)
```
┌──────────────────────────────────────┐
│ Custom Permissions for Maria        │
│ ────────────────────────────────    │
│                                     │
│ Base Role: Member                   │
│                                     │
│ Additional Permissions:             │
│ ☑ Export reports                   │
│ ☑ Manage categories                │
│ ☐ Delete shared expenses           │
│ ☐ Manage email accounts            │
│                                     │
│ These override base role           │
│                                     │
│ [Reset to Default]  [Save]         │
└──────────────────────────────────────┘
```

### 11. Onboarding by Role

#### Role-Specific Welcome
```javascript
// Owner welcome
"Welcome! As the account owner, you have full control.
 Start by inviting your family members."

// Admin welcome  
"Welcome! As an admin, you can manage expenses and 
 help maintain the account."

// Member welcome
"Welcome! You can now track your expenses and view
 shared family spending."

// Viewer welcome
"Welcome! You have view access to shared expenses.
 Contact an admin to start adding expenses."
```

### 12. Permission Request System

#### Request Permission Flow
```
┌──────────────────────────────────────┐
│ Request Additional Permissions      │
│ ────────────────────────────────    │
│                                     │
│ What would you like to do?         │
│                                     │
│ ☑ Create expense categories        │
│ ☑ Export expense reports           │
│ ☐ Invite new members               │
│                                     │
│ Message (optional):                 │
│ ┌──────────────────────────────┐   │
│ │ I need to export our Q4      │   │
│ │ expenses for taxes...         │   │
│ └──────────────────────────────┘   │
│                                     │
│ Request will be sent to:           │
│ John Smith (Owner)                 │
│                                     │
│ [Cancel]         [Send Request]    │
└──────────────────────────────────────┘
```

## Definition of Done
- [ ] Permission matrix fully implemented
- [ ] All policies created and tested
- [ ] UI respects permissions throughout
- [ ] Role management interface complete
- [ ] Audit logging in place
- [ ] All tests passing
- [ ] Security review completed
- [ ] Performance optimized
- [ ] Documentation updated
- [ ] Code reviewed and approved