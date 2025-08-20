# Ticket 1.4: Implement Account Invitation System

## Ticket Information
- **Epic**: Epic 1 - Foundation (Weeks 1-2)
- **Priority**: HIGH
- **Story Points**: 5
- **Risk Level**: MEDIUM
- **Dependencies**: 
  - Ticket 1.2 (Account and User Models)
  - Ticket 1.3 (Authentication Setup)

## Description
Build the invitation system that allows account owners and admins to invite other users to join their account. This includes the AccountInvitation model, invitation mailers, acceptance flow, and proper role assignment. The system must handle both existing and new users.

## Technical Requirements
1. Create AccountInvitation model and migration
2. Implement invitation controller and actions
3. Build invitation mailer with templates
4. Create invitation acceptance flow
5. Handle new vs existing user scenarios
6. Implement invitation expiry and validation

## Acceptance Criteria
- [ ] AccountInvitation model created with:
  - Token generation (unique, URL-safe)
  - Email validation
  - Role assignment (default: member)
  - Expiry mechanism (7 days default)
  - Tracking of who invited and who accepted
  - Soft delete for accepted/expired invitations
- [ ] Invitation creation flow:
  - Only owners and admins can send invitations
  - Check account user limit before sending
  - Prevent duplicate active invitations to same email
  - Generate secure unique token
  - Send invitation email immediately
- [ ] Invitation email includes:
  - Inviter's name and account name
  - Role being offered
  - Expiration date/time
  - Clear call-to-action button
  - Instructions for new vs existing users
- [ ] Acceptance flow handles:
  - Existing users: Add to account directly
  - New users: Redirect to sign up with pre-filled email
  - Expired invitations show appropriate message
  - Already accepted invitations prevented
  - Automatic account switching after acceptance
- [ ] Management interface includes:
  - List of pending invitations
  - Ability to resend invitations
  - Ability to cancel invitations
  - Invitation history/audit trail

## Implementation Details
```ruby
# app/models/account_invitation.rb
class AccountInvitation < ApplicationRecord
  belongs_to :account
  belongs_to :invited_by, class_name: 'User'
  belongs_to :accepted_by, class_name: 'User', optional: true
  
  enum role: {
    admin: 1,
    member: 2,
    viewer: 3
  }
  
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validate :account_not_at_limit
  validate :no_duplicate_pending_invitation
  
  scope :pending, -> { where(accepted_at: nil).where('expires_at > ?', Time.current) }
  scope :expired, -> { where(accepted_at: nil).where('expires_at <= ?', Time.current) }
  scope :accepted, -> { where.not(accepted_at: nil) }
  
  before_validation :generate_token, on: :create
  before_validation :set_expiry, on: :create
  
  def expired?
    expires_at <= Time.current
  end
  
  def accepted?
    accepted_at.present?
  end
  
  def accept!(user)
    return false if expired? || accepted?
    
    transaction do
      account.add_user(user, role: role)
      update!(
        accepted_at: Time.current,
        accepted_by: user
      )
    end
  end
  
  private
  
  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end
  
  def set_expiry
    self.expires_at ||= 7.days.from_now
  end
end

# app/controllers/account_invitations_controller.rb
class AccountInvitationsController < ApplicationController
  before_action :require_account_admin!, except: [:show, :accept]
  skip_before_action :authenticate_user!, only: [:show]
  skip_before_action :set_current_account, only: [:show, :accept]
  
  def index
    @pending_invitations = current_account.account_invitations.pending
    @invitation_history = current_account.account_invitations
                                         .includes(:invited_by, :accepted_by)
                                         .order(created_at: :desc)
                                         .page(params[:page])
  end
  
  def new
    @invitation = current_account.account_invitations.build
  end
  
  def create
    @invitation = current_account.account_invitations.build(invitation_params)
    @invitation.invited_by = current_user
    
    if @invitation.save
      AccountInvitationMailer.invite(@invitation).deliver_later
      redirect_to account_invitations_path, 
                  notice: "Invitation sent to #{@invitation.email}"
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def show
    @invitation = AccountInvitation.find_by!(token: params[:token])
    
    if @invitation.expired?
      render :expired
    elsif @invitation.accepted?
      redirect_to root_path, alert: "This invitation has already been accepted"
    elsif !user_signed_in?
      session[:pending_invitation_token] = @invitation.token
      redirect_to new_user_registration_path(email: @invitation.email)
    end
  end
end
```

## UI/UX Requirements
- [ ] Invitation form includes:
  - Email input with validation
  - Role selector (admin/member/viewer)
  - Optional personal message field
  - Account user limit indicator
  - Clear submit button (teal-700)
- [ ] Invitation list page shows:
  - Tabs for Pending/Accepted/Expired
  - Email, role, invited by, date sent
  - Status badges with appropriate colors
  - Resend button for pending invitations
  - Cancel button for pending invitations
- [ ] Invitation email template:
  - Professional design matching app branding
  - Clear subject line: "[Account Name] has invited you to collaborate"
  - Personalized greeting
  - Large CTA button (teal-700)
  - Expiration warning
  - Footer with app information
- [ ] Acceptance landing page:
  - Welcome message with account name
  - Role explanation
  - Accept/Decline buttons
  - Sign up form for new users
  - Sign in prompt for existing users

## Testing Requirements
- [ ] Model specs for AccountInvitation:
  - Token uniqueness and generation
  - Expiry validation
  - Email format validation
  - Account limit validation
  - Duplicate invitation prevention
- [ ] Controller specs:
  - Admin-only invitation creation
  - Proper email delivery
  - Token-based access
  - New vs existing user flows
- [ ] Feature specs:
  - Complete invitation flow
  - Expiry handling
  - Resend functionality
  - Cancellation
  - Multi-role scenarios
- [ ] Mailer specs:
  - Email content verification
  - Proper recipient and sender
  - Token included in URL

## Security Considerations
- [ ] Secure random token generation (32+ bytes)
- [ ] Token not guessable or enumerable
- [ ] Rate limiting on invitation endpoints
- [ ] Prevent invitation spam
- [ ] SQL injection prevention in token lookup
- [ ] XSS protection in email templates
- [ ] Authorization checks on all actions

## Performance Considerations
- [ ] Index on invitation token for fast lookup
- [ ] Index on account_id and email for duplicate checking
- [ ] Batch invitation sending for multiple recipients
- [ ] Background job for email delivery
- [ ] Cleanup job for expired invitations

## UX Implementation

### 1. User Flow Specifications

#### Invitation Sending Flow (Admin/Owner)
1. **Dashboard** → Click "Team" or "Members" in nav
2. **Members Page** → Click "Invite Member" button (teal-700)
3. **Invitation Modal** opens with form
4. Enter email address → Real-time validation
5. Select role from dropdown (default: Member)
6. Optional: Add personal message
7. Click "Send Invitation"
8. **Success Path**:
   - Modal closes
   - Toast: "Invitation sent to [email]"
   - New invitation appears in pending list
9. **Error Path**:
   - Duplicate invitation → Inline error with "Resend" option
   - Account limit reached → Error with upgrade prompt

#### Invitation Acceptance Flow (New User)
1. **Email Received** → Click "Accept Invitation" button
2. **Landing Page** shows invitation details:
   - "[Inviter] invited you to join [Account Name]"
   - Role being offered
   - Account type and member count
3. Click "Accept and Sign Up"
4. **Registration Form** (pre-filled email):
   - Name field
   - Password creation
   - Terms acceptance
5. Submit → Email confirmation sent
6. Confirm email → Auto-login and account joined
7. **Welcome Screen**:
   - "Welcome to [Account Name]!"
   - Quick tour of shared features
   - Role explanation

#### Invitation Acceptance Flow (Existing User)
1. **Email Received** → Click "Accept Invitation"
2. **Sign In Required** (if not logged in):
   - Redirect to sign in
   - Post-login redirect back to invitation
3. **Acceptance Page**:
   - Invitation details displayed
   - Current accounts shown
   - "Accept" and "Decline" buttons
4. Click "Accept":
   - Account added to user's list
   - Auto-switch to new account
   - Welcome toast notification
5. Click "Decline":
   - Confirmation dialog
   - Invitation marked as declined
   - Optional decline reason

### 2. UI Component Specifications

#### Invitation Form Modal
```
┌──────────────────────────────────────────┐
│ ✕          Invite Team Member            │
│ ────────────────────────────────────────  │
│                                           │
│ Email Address *                          │
│ ┌───────────────────────────────────┐   │
│ │ colleague@example.com             │   │
│ └───────────────────────────────────┘   │
│ ✓ Valid email address                    │
│                                           │
│ Role                                     │
│ ┌───────────────────────────────────┐   │
│ │ Member                         ▼  │   │
│ └───────────────────────────────────┘   │
│                                           │
│ Personal Message (optional)              │
│ ┌───────────────────────────────────┐   │
│ │ Hi! I'd like you to join our     │   │
│ │ family expense tracking...        │   │
│ └───────────────────────────────────┘   │
│                                           │
│ ℹ 3 of 5 member slots used              │
│                                           │
│ [Cancel]          [Send Invitation]      │
└──────────────────────────────────────────┘
```

#### Pending Invitations List
```
┌─────────────────────────────────────────────┐
│ Pending Invitations (2)                    │
│ ───────────────────────────────────────────│
│                                             │
│ ┌─────────────────────────────────────┐   │
│ │ 📧 john@example.com                  │   │
│ │    Role: Member                      │   │
│ │    Sent: 2 hours ago                 │   │
│ │    Expires: in 7 days                │   │
│ │    [Resend] [Copy Link] [Cancel]     │   │
│ └─────────────────────────────────────┘   │
│                                             │
│ ┌─────────────────────────────────────┐   │
│ │ 📧 sarah@example.com                 │   │
│ │    Role: Admin                       │   │
│ │    Sent: Yesterday                   │   │
│ │    Expires: in 6 days                │   │
│ │    [Resend] [Copy Link] [Cancel]     │   │
│ └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

#### Invitation Acceptance Page
```
┌──────────────────────────────────────────┐
│            [App Logo]                    │
│                                          │
│    You're invited!                      │
│                                          │
│  ┌────────────────────────────────┐    │
│  │     [Account Avatar]            │    │
│  │     Garcia Family Account       │    │
│  │     Family expense tracking     │    │
│  └────────────────────────────────┘    │
│                                          │
│  Maria Garcia has invited you to        │
│  join as a Member                       │
│                                          │
│  As a member you can:                   │
│  • Add and manage your expenses         │
│  • View shared family expenses          │
│  • Access budget reports                │
│                                          │
│  This invitation expires in 6 days      │
│                                          │
│  ┌────────────────────────────────┐    │
│  │    Accept Invitation           │    │
│  └────────────────────────────────┘    │
│                                          │
│  Already have an account? Sign in       │
└──────────────────────────────────────────┘
```

### 3. Turbo/Stimulus Integration

#### Invitation Form Controller
```javascript
// app/javascript/controllers/invitation_form_controller.js
- Email validation with debounce
- Role selector with permission preview
- Character count for message
- Submit button state management
- Success/error handling with Turbo
```

#### Invitation List Controller
```javascript
// app/javascript/controllers/invitation_list_controller.js
- Resend action with rate limiting
- Copy link to clipboard
- Cancel with confirmation
- Auto-refresh pending count
- Expiry countdown updates
```

#### Turbo Streams Usage
- Stream new invitation to pending list
- Update member count in real-time
- Remove invitation on acceptance
- Update invitation status badges

### 4. Visual Design Details

#### Color Coding
- **Pending Invitations**: `bg-amber-50 border-amber-200`
- **Accepted**: `bg-emerald-50 border-emerald-200`
- **Expired**: `bg-slate-50 border-slate-200 text-slate-500`
- **Send Button**: `bg-teal-700 hover:bg-teal-800`
- **Cancel Button**: `bg-slate-200 hover:bg-slate-300`

#### Role Badges
```css
.role-owner { @apply bg-purple-100 text-purple-800; }
.role-admin { @apply bg-teal-100 text-teal-800; }
.role-member { @apply bg-slate-100 text-slate-800; }
.role-viewer { @apply bg-amber-100 text-amber-800; }
```

#### Email Template Styling
- Header: Brand logo on `bg-teal-700`
- Body: Clean white with ample padding
- CTA Button: Large, centered, `bg-teal-700`
- Footer: Light gray with unsubscribe link

### 5. Accessibility Requirements

#### Form Accessibility
```html
<form aria-label="Invite member form">
  <label for="email" class="sr-only">Email address</label>
  <input id="email" 
         type="email"
         aria-required="true"
         aria-describedby="email-hint email-error">
  
  <select aria-label="Select member role"
          aria-describedby="role-description">
    <option>Member</option>
  </select>
</form>
```

#### Keyboard Support
- Tab navigation through all form fields
- Enter submits form
- Escape closes modal
- Space toggles dropdowns

#### Screen Reader Announcements
- "Invitation sent successfully"
- "Error: Email already invited"
- "Invitation expires in X days"
- Role permission descriptions

### 6. Mobile-First Considerations

#### Responsive Modal
```css
/* Mobile */
.invitation-modal {
  @apply fixed inset-x-4 bottom-0 rounded-t-xl;
}

/* Tablet+ */
@media (min-width: 768px) {
  .invitation-modal {
    @apply relative max-w-lg mx-auto rounded-xl;
  }
}
```

#### Touch Optimizations
- Large tap targets (min 44x44px)
- Bottom sheet pattern on mobile
- Swipe down to dismiss modal
- Native email keyboard

#### Mobile Email Template
- Single column layout
- Large CTA button (full width)
- Readable font sizes (min 16px)
- Adequate line height

### 7. Form Design and Validation

#### Email Validation States
```javascript
// Real-time validation
onEmailInput() {
  if (!email) {
    showNeutral("Enter an email address")
  } else if (!isValidEmail(email)) {
    showError("Please enter a valid email")
  } else if (isDuplicate(email)) {
    showWarning("Already invited - Resend?")
  } else {
    showSuccess("Ready to send")
  }
}
```

#### Role Selector with Descriptions
```html
<select id="role" class="form-select">
  <option value="admin">
    Admin - Manage expenses and settings
  </option>
  <option value="member" selected>
    Member - Add and view expenses
  </option>
  <option value="viewer">
    Viewer - View expenses only
  </option>
</select>
```

#### Error Recovery
- Duplicate email: Show "Resend" button
- Network error: Retry with exponential backoff
- Account limit: Link to upgrade page
- Invalid token: Request new invitation

### 8. Invitation Management Features

#### Bulk Invitations
```
┌────────────────────────────────────┐
│ Invite Multiple Members            │
│ ──────────────────────────────     │
│ Add up to 10 email addresses      │
│                                    │
│ ┌────────────────────────────┐    │
│ │ email1@example.com         │    │
│ │ email2@example.com         │    │
│ │ + Add another              │    │
│ └────────────────────────────┘    │
│                                    │
│ All will be invited as: Member     │
│                                    │
│ [Cancel]    [Send 2 Invitations]  │
└────────────────────────────────────┘
```

#### Invitation Analytics
- Sent count and acceptance rate
- Average time to accept
- Pending invitation reminders
- Expiry warnings (24 hours before)

#### Copy Invitation Link
```javascript
// Click "Copy Link" button
navigator.clipboard.writeText(invitationUrl)
showToast("Invitation link copied!")
// Button text changes to "Copied!" for 2 seconds
```

### 9. Security UX Considerations

#### Secure Token Display
- Never show full token in UI
- Masked display: `****-****-****-ABC1`
- One-time view option for sharing

#### Expiry Communication
- Clear expiry date/time in user's timezone
- Warning badge when <24 hours remain
- Auto-cleanup of expired invitations
- Option to extend expiration (admin only)

## Definition of Done
- [ ] AccountInvitation model fully implemented and tested
- [ ] Controller actions working end-to-end
- [ ] Email templates professional and responsive
- [ ] Both new and existing user flows tested
- [ ] Expiry and validation logic working
- [ ] UI matches Financial Confidence design
- [ ] Security review completed
- [ ] Performance indexes in place
- [ ] Documentation includes invitation flow diagram
- [ ] Code reviewed and approved
- [ ] Test coverage >95%