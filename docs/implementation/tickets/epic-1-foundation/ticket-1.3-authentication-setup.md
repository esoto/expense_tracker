# Ticket 1.3: Configure Authentication and Session Management

## Ticket Information
- **Epic**: Epic 1 - Foundation (Weeks 1-2)
- **Priority**: HIGH
- **Story Points**: 5
- **Risk Level**: HIGH
- **Dependencies**: Ticket 1.2 (Account and User Models)

## Description
Set up complete authentication system with Devise, including custom controllers, views, and session management for multi-tenant context. Implement account switching mechanism and ensure proper tenant isolation during authentication flows.

## Technical Requirements
1. Generate and customize Devise controllers
2. Create custom Devise views with Tailwind CSS styling
3. Implement session management for current account
4. Add account switching functionality
5. Configure authentication redirects
6. Set up email configuration for Devise mailers

## Acceptance Criteria
- [ ] Devise controllers are generated and customized:
  - RegistrationsController with account creation
  - SessionsController with tenant context
  - PasswordsController for recovery
  - ConfirmationsController for email verification
- [ ] Custom Devise views created with Financial Confidence color palette:
  - Sign in page with "Remember me" option
  - Sign up page with account type selection
  - Password reset flow
  - Email confirmation pages
  - Account locked page
- [ ] Session management implemented:
  - Current account stored in session
  - Account switching preserves user session
  - Automatic account selection on login
  - Session timeout configuration
- [ ] Email configuration working:
  - Confirmation emails sent
  - Password reset emails sent
  - Account invitation emails configured
  - Welcome email after registration
- [ ] Authentication redirects properly configured:
  - After sign in → Dashboard or last visited page
  - After sign up → Email confirmation notice
  - After sign out → Landing page
  - Unauthorized access → Sign in page
- [ ] Multi-tenant context properly set during auth flow

## Implementation Details
```ruby
# app/controllers/users/registrations_controller.rb
class Users::RegistrationsController < Devise::RegistrationsController
  def create
    super do |user|
      if user.persisted?
        # Personal account created automatically via callback
        session[:current_account_id] = user.accounts.first.id
      end
    end
  end
end

# app/controllers/users/sessions_controller.rb
class Users::SessionsController < Devise::SessionsController
  def create
    super do |user|
      # Set default account in session
      default_account = user.active_accounts.first
      session[:current_account_id] = default_account&.id
    end
  end
  
  def destroy
    session[:current_account_id] = nil
    super
  end
end

# app/controllers/application_controller.rb updates
class ApplicationController < ActionController::Base
  set_current_tenant_through_filter
  before_action :authenticate_user!
  before_action :set_current_account
  before_action :configure_permitted_parameters, if: :devise_controller?
  
  private
  
  def set_current_account
    return unless user_signed_in?
    
    account_id = session[:current_account_id]
    @current_account = current_user.active_accounts.find_by(id: account_id)
    @current_account ||= current_user.active_accounts.first
    
    if @current_account
      set_current_tenant(@current_account)
      session[:current_account_id] = @current_account.id
    else
      redirect_to new_account_path unless devise_controller?
    end
  end
  
  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
    devise_parameter_sanitizer.permit(:account_update, keys: [:name])
  end
end
```

## UI/UX Requirements
- [ ] Sign in page includes:
  - Email and password fields
  - "Remember me" checkbox
  - "Forgot password?" link
  - "Sign up" link
  - Proper error messaging
  - Teal-700 primary button
- [ ] Sign up page includes:
  - Name, email, password fields
  - Password confirmation
  - Account type selection (default: personal)
  - Terms acceptance checkbox
  - Clear validation messages
- [ ] Account switcher component in navbar:
  - Dropdown with account list
  - Current account highlighted
  - "Create new account" option
  - Account type badges
- [ ] Responsive design for all auth pages
- [ ] Loading states for form submissions

## Testing Requirements
- [ ] Controller specs for all Devise controllers
- [ ] Feature specs for authentication flows:
  - User registration with email confirmation
  - User login/logout
  - Password reset flow
  - Account switching
  - Session timeout
- [ ] Test multi-tenant context during auth
- [ ] Test email delivery in test environment
- [ ] Test account auto-selection logic
- [ ] Test unauthorized access redirects
- [ ] Test remember me functionality

## Security Considerations
- [ ] CSRF protection enabled
- [ ] Secure session configuration
- [ ] Rate limiting on authentication endpoints
- [ ] Strong password requirements enforced
- [ ] Account lockout after 5 failed attempts
- [ ] Session fixation protection
- [ ] Secure cookie settings in production

## Performance Considerations
- [ ] Minimize database queries during auth
- [ ] Cache current account in request cycle
- [ ] Optimize account switching queries
- [ ] Ensure session storage is efficient

## UX Implementation

### 1. User Flow Specifications

#### Sign In Flow
1. **Landing Page** → Click "Sign In" (top-right nav)
2. **Sign In Page** displays with email/password fields
3. User enters credentials
4. **Loading State**: Button shows spinner, form disabled
5. **Success Path**:
   - First-time login → Account selection modal if multiple accounts
   - Return user → Dashboard with last selected account
   - Redirect to originally requested page if applicable
6. **Error Path**:
   - Invalid credentials → Inline error below fields
   - Account locked → Redirect to unlock instructions page
   - Email unconfirmed → Redirect to confirmation page

#### Sign Up Flow  
1. **Landing Page** → Click "Get Started" or "Sign Up"
2. **Registration Page** with progressive disclosure:
   - Step 1: Name and email
   - Step 2: Password creation with strength indicator
   - Step 3: Account type selection (Personal/Family/Business)
3. **Email Verification**:
   - Success message with email sent notification
   - Resend option after 60 seconds
   - Check email animation/illustration
4. **Post-Confirmation**:
   - Welcome modal with quick tour option
   - Account setup wizard for initial categories

#### Account Switching Flow
1. Click account name/avatar in navbar
2. Dropdown slides down with smooth animation
3. Shows all accounts with current highlighted
4. Click different account → Brief loading spinner
5. Page refreshes with new account context
6. Toast notification: "Switched to [Account Name]"

### 2. UI Component Specifications

#### Sign In Form Layout
```
┌─────────────────────────────────────┐
│         [App Logo]                  │
│    Welcome back                     │
│    Sign in to your account          │
│                                     │
│  Email                              │
│  ┌─────────────────────────────┐  │
│  │ user@example.com            │  │
│  └─────────────────────────────┘  │
│                                     │
│  Password                           │
│  ┌─────────────────────────────┐  │
│  │ ••••••••••••          [👁]  │  │
│  └─────────────────────────────┘  │
│                                     │
│  ☐ Remember me for 30 days         │
│                                     │
│  ┌─────────────────────────────┐  │
│  │      Sign In                │  │
│  └─────────────────────────────┘  │
│                                     │
│  Forgot password? • New? Sign up   │
└─────────────────────────────────────┘
```

#### Account Switcher Component
```
┌──────────────────────┐
│ 🏠 Personal Account ▼│  <- Current account
└──────────────────────┘
        │ (on click)
        ▼
┌──────────────────────────┐
│ SWITCH ACCOUNT           │
│ ─────────────────        │
│ ✓ 🏠 Personal Account    │
│   👥 Family Account      │
│   💼 Business Account    │
│ ─────────────────        │
│ + Create New Account     │
│ ⚙ Account Settings       │
└──────────────────────────┘
```

### 3. Turbo/Stimulus Integration

#### Sign In Form Controller
```javascript
// app/javascript/controllers/sign_in_controller.js
- Password visibility toggle (Stimulus)
- Form validation before submit
- Loading state management
- Remember me preference storage
- Auto-focus email field on load
```

#### Account Switcher Controller
```javascript
// app/javascript/controllers/account_switcher_controller.js
- Dropdown toggle with outside click detection
- Account selection via Turbo
- Loading state during switch
- Keyboard navigation (arrow keys)
- Search/filter for 5+ accounts
```

#### Turbo Frames Usage
- `turbo-frame id="auth-form"` for form replacements
- `turbo-frame id="account-context"` for navbar updates
- Stream updates for real-time account changes

### 4. Visual Design Details

#### Color Usage
- **Primary Actions**: Sign In button uses `bg-teal-700 hover:bg-teal-800`
- **Secondary Links**: "Forgot password?" uses `text-teal-600 hover:text-teal-700`
- **Error States**: `border-rose-400 bg-rose-50` for invalid fields
- **Success States**: `bg-emerald-50 text-emerald-700` for confirmations
- **Focus States**: `focus:ring-2 focus:ring-teal-500 focus:border-teal-500`

#### Typography
- **Headers**: `text-2xl font-bold text-slate-900`
- **Body Text**: `text-base text-slate-600`
- **Form Labels**: `text-sm font-medium text-slate-700`
- **Error Messages**: `text-sm text-rose-600`
- **Links**: `text-sm text-teal-600 hover:underline`

#### Spacing
- Form fields: `mb-4` between groups
- Padding: `p-8` for form containers
- Max width: `max-w-md mx-auto` for auth forms

### 5. Accessibility Requirements

#### ARIA Labels
```html
<form role="form" aria-label="Sign in form">
  <input aria-label="Email address" 
         aria-required="true"
         aria-invalid="false"
         aria-describedby="email-error">
  <button aria-label="Sign in to your account"
          aria-busy="false">
</form>
```

#### Keyboard Navigation
- Tab order: Email → Password → Remember → Sign In → Links
- Enter key submits form from any field
- Escape key closes dropdowns
- Arrow keys navigate account list

#### Screen Reader Support
- Form validation announces errors immediately
- Loading states announced with `aria-live="polite"`
- Success messages use `role="alert"`
- Account switch announced with context change

### 6. Mobile-First Considerations

#### Responsive Breakpoints
```css
/* Mobile (default) */
.auth-form { padding: 1rem; }

/* Tablet (md: 768px+) */
@media (min-width: 768px) {
  .auth-form { padding: 2rem; max-width: 28rem; }
}

/* Desktop (lg: 1024px+) */
@media (min-width: 1024px) {
  .auth-form { padding: 3rem; }
}
```

#### Touch Interactions
- Minimum touch target: 44x44px for all buttons
- Password visibility toggle: Large touch area
- Account dropdown: Full-width on mobile
- Form fields: `min-height: 3rem` for easy tapping

#### Mobile-Specific Patterns
- Email field: `type="email"` for keyboard
- Password field: Biometric authentication option
- Single-column layout throughout
- Bottom-sheet style for account switcher

### 7. Form Design and Validation

#### Real-time Validation
```javascript
// Email validation
- Check format on blur
- Show green check for valid
- Debounce API check for existing email

// Password validation
- Strength meter updates on keyup
- Requirements checklist:
  ✓ At least 8 characters
  ✓ One uppercase letter
  ✓ One number
  ✗ One special character
```

#### Error Display Pattern
```html
<div class="form-group">
  <input class="border-rose-400" />
  <p class="mt-1 text-sm text-rose-600">
    <svg class="inline w-4 h-4">!</svg>
    Email address is invalid
  </p>
</div>
```

#### Success Confirmation
- Green border on validated fields
- Check icon appears in field
- Success toast for account switch
- Welcome message personalized with name

### 8. Loading and Transition States

#### Button Loading States
```html
<!-- Default -->
<button class="bg-teal-700">Sign In</button>

<!-- Loading -->
<button class="bg-teal-600 cursor-wait" disabled>
  <svg class="animate-spin">...</svg>
  Signing in...
</button>
```

#### Page Transitions
- Fade in/out: 200ms ease-in-out
- Slide down dropdowns: 150ms ease-out
- Form errors: Shake animation 300ms
- Success redirects: Brief success state before redirect

## Definition of Done
- [ ] All Devise controllers customized and tested
- [ ] Authentication flows working end-to-end
- [ ] Email delivery confirmed in development
- [ ] UI matches Financial Confidence design system
- [ ] Account switching seamless and fast
- [ ] Session management secure and reliable
- [ ] All tests passing with >95% coverage
- [ ] Security review completed
- [ ] Documentation updated with auth flow diagrams
- [ ] Code reviewed and approved