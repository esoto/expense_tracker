# Ticket 2.2: Update All Controllers for Tenant Context

## Ticket Information
- **Epic**: Epic 2 - Multi-tenancy (Weeks 3-4)
- **Priority**: HIGH
- **Story Points**: 8
- **Risk Level**: HIGH
- **Dependencies**: 
  - Ticket 2.1 (Tenant Scoping Models)

## Description
Update all existing controllers to properly set and use tenant context. This includes updating ApplicationController with tenant management, modifying all resource controllers to use tenant-scoped queries, and ensuring proper authorization checks based on account membership.

## Technical Requirements
1. Update ApplicationController with tenant management
2. Modify all resource controllers for tenant scoping
3. Add authorization helpers and checks
4. Update strong parameters to prevent account_id manipulation
5. Handle tenant context in API controllers
6. Add account switching functionality

## Acceptance Criteria
- [ ] ApplicationController updated with:
  - `set_current_tenant_through_filter` configured
  - `set_current_account` before_action
  - Helper methods for current_account and current_membership
  - Authorization helper methods (require_account_access!, require_account_admin!, require_account_owner!)
  - Proper redirect handling when no account available
- [ ] All resource controllers updated:
  - ExpensesController uses tenant-scoped queries
  - CategoriesController respects account boundaries  
  - EmailAccountsController scoped to current account
  - BudgetsController with tenant isolation
  - DashboardController shows only current account data
  - WebhooksController (API) maintains tenant context
- [ ] Account switching implemented:
  - AccountsController with switch action
  - Session stores current_account_id
  - Seamless switching without re-authentication
  - Clear tenant context on switch
- [ ] Strong parameters secured:
  - account_id removed from permitted params
  - user_id assignment controlled by controller
  - No tenant manipulation possible via params
- [ ] Error handling for:
  - Missing tenant context
  - Unauthorized account access
  - Invalid account switching
  - Expired sessions

## Implementation Details
```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  # Tenant management
  set_current_tenant_through_filter
  
  # Callbacks
  before_action :authenticate_user!, unless: :devise_controller?
  before_action :set_current_account, if: :user_signed_in?
  
  # Error handling
  rescue_from ActsAsTenant::Errors::NoTenantSet, with: :handle_no_tenant
  rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
  
  private
  
  def set_current_account
    return if devise_controller?
    
    # Try to get account from session
    if session[:current_account_id].present?
      @current_account = current_user.active_accounts
                                    .find_by(id: session[:current_account_id])
    end
    
    # Fallback to first available account
    @current_account ||= current_user.active_accounts.first
    
    if @current_account
      set_current_tenant(@current_account)
      session[:current_account_id] = @current_account.id
      @current_membership = current_user.account_memberships
                                       .find_by(account: @current_account)
    else
      redirect_to new_account_path, 
                  alert: "Please create or join an account to continue"
    end
  end
  
  def current_account
    @current_account
  end
  helper_method :current_account
  
  def current_membership
    @current_membership
  end
  helper_method :current_membership
  
  # Authorization helpers
  def require_account_access!
    unless current_user.can_access_account?(current_account)
      redirect_to accounts_path, alert: "You don't have access to this account"
    end
  end
  
  def require_account_admin!
    unless current_membership&.admin? || current_membership&.owner?
      redirect_to root_path, alert: "Admin access required"
    end
  end
  
  def require_account_owner!
    unless current_membership&.owner?
      redirect_to root_path, alert: "Only account owners can perform this action"
    end
  end
  
  def handle_no_tenant
    redirect_to accounts_path, alert: "Please select an account"
  end
  
  def handle_not_found
    redirect_to root_path, alert: "Resource not found"
  end
end

# app/controllers/expenses_controller.rb (updated)
class ExpensesController < ApplicationController
  before_action :require_account_access!
  before_action :set_expense, only: [:show, :edit, :update, :destroy]
  
  def index
    # acts_as_tenant automatically scopes to current_account
    @expenses = Expense.includes(:category, :user, :email_account)
                      .recent
                      .page(params[:page])
    
    # Additional filtering
    @expenses = @expenses.where(category_id: params[:category_id]) if params[:category_id]
    @expenses = @expenses.where(email_account_id: params[:email_account_id]) if params[:email_account_id]
  end
  
  def new
    @expense = current_account.expenses.build(user: current_user)
    load_form_data
  end
  
  def create
    @expense = current_account.expenses.build(expense_params)
    @expense.user = current_user
    
    if @expense.save
      redirect_to @expense, notice: 'Expense created successfully'
    else
      load_form_data
      render :new, status: :unprocessable_entity
    end
  end
  
  private
  
  def set_expense
    # acts_as_tenant ensures this only finds within current_account
    @expense = Expense.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to expenses_path, alert: 'Expense not found'
  end
  
  def expense_params
    # Never permit account_id or user_id from params
    params.require(:expense).permit(
      :amount, :description, :transaction_date,
      :merchant_name, :category_id, :email_account_id,
      :currency, :status, :visibility
    )
  end
  
  def load_form_data
    @categories = current_account.categories.active.order(:name)
    @email_accounts = current_account.email_accounts.active
  end
end

# app/controllers/accounts_controller.rb
class AccountsController < ApplicationController
  skip_before_action :set_current_account, only: [:index, :new, :create, :switch]
  
  def index
    @accounts = current_user.active_accounts.includes(:users)
    @current_account_id = session[:current_account_id]
  end
  
  def switch
    @account = current_user.active_accounts.find(params[:id])
    
    # Clear current tenant
    ActsAsTenant.current_tenant = nil
    
    # Update session
    session[:current_account_id] = @account.id
    
    # Update last accessed
    membership = current_user.account_memberships.find_by(account: @account)
    membership.touch(:last_accessed_at)
    
    redirect_to root_path, notice: "Switched to #{@account.name}"
  rescue ActiveRecord::RecordNotFound
    redirect_to accounts_path, alert: "Account not found"
  end
end
```

## Testing Requirements
- [ ] Controller specs for ApplicationController:
  - Tenant setting on each request
  - Account switching logic
  - Authorization helpers
  - Error handling
- [ ] Controller specs for each resource controller:
  - Proper tenant scoping
  - Cannot access other tenant's resources
  - Strong parameters filtering
  - Authorization checks
- [ ] Request specs:
  - Full request cycle with tenant context
  - Account switching flow
  - API requests maintain tenant context
  - Error responses for invalid tenant
- [ ] Integration tests:
  - Multi-step workflows respect tenant
  - Session persistence across requests
  - Concurrent requests don't interfere

## Security Considerations
- [ ] Prevent account_id injection via params
- [ ] Verify tenant context on every request
- [ ] Clear tenant context after request
- [ ] Audit logging for account switches
- [ ] Rate limiting on account switching
- [ ] CSRF protection on all actions
- [ ] Secure session cookie settings

## Performance Considerations
- [ ] Minimize database queries for tenant setup
- [ ] Cache current account in request cycle
- [ ] Optimize membership lookups
- [ ] Avoid N+1 queries with includes
- [ ] Index session lookups if using database sessions

## UI/UX Considerations
- [ ] Account switcher in navigation
- [ ] Current account indicator
- [ ] Clear error messages for access denied
- [ ] Smooth account switching experience
- [ ] Maintain page context after switch when possible

## Definition of Done
- [ ] All controllers updated with tenant context
- [ ] Account switching working smoothly
- [ ] Authorization checks in place
- [ ] Strong parameters secured
- [ ] All controller tests passing
- [ ] Request/integration tests passing
- [ ] Security review completed
- [ ] Performance impact measured (<10ms overhead)
- [ ] Documentation updated with controller patterns
- [ ] Code reviewed and approved