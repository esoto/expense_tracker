# Feature: Multi-User Accounts with Role-Based Access Control

## Executive Summary

This feature introduces multi-user account capabilities to the expense tracking application, allowing multiple users to access and manage the same financial data with differentiated permissions based on their assigned roles. This enhancement transforms the current single-user EmailAccount model into a collaborative financial management platform while maintaining backward compatibility and data security.

**Business Justification:**
- Enables household financial management where partners need shared expense visibility
- Supports small business scenarios with accountant/bookkeeper access
- Provides granular permission control to protect sensitive financial operations
- Maintains audit trail for compliance and accountability

## Objectives

### Primary Objectives
- Enable multiple users to access the same financial account data
- Implement role-based permission system for feature access control
- Maintain backward compatibility with existing single-user accounts
- Ensure data security and privacy through proper access controls

### Secondary Objectives
- Provide audit trail for multi-user actions
- Support flexible role assignment and management
- Enable account owner to maintain full control over user access
- Create foundation for future team/organization features

### Success Metrics
- Zero data loss during migration to multi-user structure
- 100% backward compatibility with existing single-user workflows
- Sub-100ms permission check performance
- Complete audit trail for all financial modifications
- User satisfaction score >4.5/5 for collaboration features

## Requirements

### Functional Requirements

#### FR1: Account Structure
1. The system SHALL support Account entities that can have multiple associated users
2. The system SHALL maintain backward compatibility with existing single-user EmailAccounts
3. The system SHALL allow a maximum of 5 users per account initially (configurable)
4. The system SHALL support account creation with a single owner user
5. The system SHALL prevent deletion of accounts with active users
6. The system MAY support account archival for inactive accounts

#### FR2: User Management
1. The system SHALL support User entities separate from EmailAccount
2. The system SHALL require email verification for new users
3. The system SHALL support secure password authentication
4. The system SHALL support user invitation via email
5. The system SHALL allow users to belong to multiple accounts
6. The system SHALL track user status (active, invited, suspended, removed)
7. The system SHOULD support OAuth authentication (Gmail, Outlook)

#### FR3: Role-Based Access Control
1. The system SHALL implement predefined roles: Owner, Admin, Member, Viewer
2. The system SHALL enforce role-based permissions at controller and service levels
3. The system SHALL allow only one Owner per account
4. The system SHALL support role changes by authorized users
5. The system SHALL log all permission changes
6. The system MAY support custom role creation in future phases

#### FR4: Permission System
1. The system SHALL check permissions before any data modification
2. The system SHALL cache permission checks for performance
3. The system SHALL provide clear error messages for permission denials
4. The system SHALL support resource-level permissions (specific expenses, categories)
5. The system SHALL implement time-based access restrictions (optional)

#### FR5: Data Access Control
1. The system SHALL filter data based on user permissions
2. The system SHALL mask sensitive data for restricted roles
3. The system SHALL track data access for audit purposes
4. The system SHALL support bulk permission updates
5. The system SHALL maintain data integrity during permission changes

### Non-Functional Requirements

#### NFR1: Performance
- Permission checks SHALL complete in <100ms
- User switching SHALL complete in <500ms
- Account data loading SHALL not degrade by >10% with multi-user access
- Concurrent user operations SHALL be supported up to 10 users per account

#### NFR2: Security
- All user passwords SHALL be encrypted using BCrypt (cost factor 12)
- Session tokens SHALL expire after 2 hours of inactivity
- Failed login attempts SHALL trigger account locking after 5 attempts
- All financial data modifications SHALL be logged with user attribution
- API tokens SHALL be scoped to specific user permissions

#### NFR3: Scalability
- System SHALL support up to 100,000 accounts
- System SHALL support up to 500,000 total users
- Database queries SHALL use appropriate indexes for multi-user filtering
- Permission caching SHALL reduce database load by >50%

#### NFR4: Usability
- Role assignment interface SHALL be intuitive and self-explanatory
- Permission denial messages SHALL suggest required role
- User invitation process SHALL complete in <3 clicks
- Account switching SHALL be available from any page

#### NFR5: Compatibility
- Existing single-user accounts SHALL continue functioning without modification
- API endpoints SHALL maintain backward compatibility
- Database migrations SHALL be reversible
- Existing webhooks and integrations SHALL continue working

### Acceptance Criteria

#### AC1: Account Creation and Setup
```gherkin
Given I am a new user
When I create an account
Then I should be assigned as the Owner
And the account should be created with default settings
And I should have full permissions on all resources

Given I am an account Owner
When I invite a new user via email
Then the user should receive an invitation email
And the invitation should expire after 7 days
And the user should be able to join with the assigned role
```

#### AC2: Role-Based Access
```gherkin
Given I am a Viewer role user
When I attempt to create a new expense
Then I should receive a permission denied error
And the error should indicate I need Member role or higher

Given I am a Member role user
When I create a new expense
Then the expense should be created successfully
And the expense should be attributed to my user account
And other users in the account should see the expense
```

#### AC3: Permission Enforcement
```gherkin
Given I am an Admin role user
When I attempt to delete another user
Then the operation should succeed if the user is not the Owner
And an audit log entry should be created
And the deleted user should lose access immediately

Given I am a Member role user
When I attempt to modify account settings
Then I should receive a permission denied error
And the error should indicate I need Admin role or higher
```

## Feature Breakdown

### Epic 1: User and Account Model Restructuring

#### User Story 1.1: Create User Model
**As a** system architect  
**I want** to separate user identity from email accounts  
**So that** multiple users can access the same financial data

**Tasks:**
- [ ] Create User model with authentication fields (8 hours)
- [ ] Implement secure password handling with BCrypt (4 hours)
- [ ] Add email verification system (6 hours)
- [ ] Create user sessions management (4 hours)
- [ ] Implement "remember me" functionality (2 hours)
- [ ] Add two-factor authentication preparation (4 hours)

**Acceptance Criteria:**
- Given a new user registration
- When they provide email and password
- Then a User record is created with encrypted password
- And an email verification is sent
- And they cannot login until email is verified

#### User Story 1.2: Create Account Model
**As a** system architect  
**I want** to create an Account model that groups financial data  
**So that** multiple users can share access to the same financial information

**Tasks:**
- [ ] Create Account model with settings and metadata (4 hours)
- [ ] Establish relationships with existing models (6 hours)
- [ ] Migrate EmailAccount data to Account structure (8 hours)
- [ ] Create account settings management (4 hours)
- [ ] Implement account limits and quotas (3 hours)

**Acceptance Criteria:**
- Given an existing EmailAccount
- When the migration runs
- Then an Account is created with the EmailAccount data
- And all expenses remain accessible
- And no data is lost

#### User Story 1.3: Create AccountUser Join Model
**As a** system architect  
**I want** to link users to accounts with specific roles  
**So that** access permissions can be managed per user per account

**Tasks:**
- [ ] Create AccountUser join model (2 hours)
- [ ] Define role enum (Owner, Admin, Member, Viewer) (1 hour)
- [ ] Add status tracking (active, invited, suspended) (2 hours)
- [ ] Implement invitation token system (4 hours)
- [ ] Add joined_at and removed_at timestamps (1 hour)

**Acceptance Criteria:**
- Given a user and an account
- When they are linked via AccountUser
- Then the user can access the account based on their role
- And the relationship can be modified or removed

### Epic 2: Permission System Implementation

#### User Story 2.1: Implement Permission Service
**As a** developer  
**I want** a centralized permission checking service  
**So that** access control is consistent across the application

**Tasks:**
- [ ] Create PermissionService with role definitions (6 hours)
- [ ] Define permission matrix for all actions (4 hours)
- [ ] Implement caching layer for performance (4 hours)
- [ ] Add permission checking helpers (3 hours)
- [ ] Create RSpec tests for all permission scenarios (6 hours)

**Acceptance Criteria:**
- Given a user with a specific role
- When they attempt any action
- Then the PermissionService correctly allows or denies
- And the check completes in <100ms
- And the result is cached for subsequent checks

#### User Story 2.2: Add Controller Authorization
**As a** developer  
**I want** to enforce permissions at the controller level  
**So that** unauthorized requests are rejected immediately

**Tasks:**
- [ ] Create authorization concern for controllers (4 hours)
- [ ] Add before_action callbacks to all controllers (6 hours)
- [ ] Implement role-specific action filters (4 hours)
- [ ] Add permission error handling and messages (3 hours)
- [ ] Update controller tests for authorization (8 hours)

**Acceptance Criteria:**
- Given an unauthorized user
- When they attempt a restricted action
- Then they receive a 403 Forbidden response
- And an appropriate error message is displayed
- And the action is logged for security audit

#### User Story 2.3: Implement Data Scoping
**As a** developer  
**I want** to automatically scope data queries by user permissions  
**So that** users only see data they're authorized to access

**Tasks:**
- [ ] Create scoping concern for models (4 hours)
- [ ] Implement account-based query filters (3 hours)
- [ ] Add role-based data masking (4 hours)
- [ ] Update all existing queries to use scoping (8 hours)
- [ ] Performance optimize scoped queries (4 hours)

**Acceptance Criteria:**
- Given a user with limited permissions
- When they query expenses
- Then they only see authorized data
- And sensitive fields are masked if needed
- And query performance remains acceptable

### Epic 3: User Interface Updates

#### User Story 3.1: Create User Management Interface
**As an** account owner  
**I want** to manage users in my account  
**So that** I can control who has access to my financial data

**Tasks:**
- [ ] Create users index page with role display (4 hours)
- [ ] Implement user invitation form (3 hours)
- [ ] Add role management interface (4 hours)
- [ ] Create user removal confirmation (2 hours)
- [ ] Add activity log display (3 hours)
- [ ] Implement Stimulus controllers for interactions (4 hours)

**Acceptance Criteria:**
- Given I am an account owner
- When I access user management
- Then I can see all users and their roles
- And I can invite new users via email
- And I can change roles (except my own)
- And I can remove users from the account

#### User Story 3.2: Add Account Switching
**As a** user with multiple accounts  
**I want** to switch between accounts easily  
**So that** I can manage different financial contexts

**Tasks:**
- [ ] Create account switcher component (3 hours)
- [ ] Implement session-based current account (2 hours)
- [ ] Add account switcher to navigation (2 hours)
- [ ] Create account dashboard view (4 hours)
- [ ] Update Turbo frames for account context (3 hours)

**Acceptance Criteria:**
- Given I have access to multiple accounts
- When I click the account switcher
- Then I see all my available accounts
- And I can switch accounts without logging out
- And the UI updates to show the new account context

#### User Story 3.3: Update Permission-Based UI
**As a** user with specific role  
**I want** to see only the features I can use  
**So that** the interface is clear and not confusing

**Tasks:**
- [ ] Create permission-based view helpers (3 hours)
- [ ] Hide/show UI elements based on role (6 hours)
- [ ] Add permission tooltips for disabled features (2 hours)
- [ ] Update navigation based on permissions (2 hours)
- [ ] Implement role badges in UI (2 hours)

**Acceptance Criteria:**
- Given I am a viewer role user
- When I access the application
- Then I don't see "Create Expense" buttons
- And disabled features show informative tooltips
- And my role is clearly displayed

### Epic 4: Migration and Backward Compatibility

#### User Story 4.1: Create Data Migration
**As a** system administrator  
**I want** to migrate existing EmailAccounts to the new structure  
**So that** current users don't lose any data

**Tasks:**
- [ ] Create migration to add new tables (2 hours)
- [ ] Write data transformation script (6 hours)
- [ ] Implement rollback capability (3 hours)
- [ ] Add migration verification checks (2 hours)
- [ ] Create migration documentation (2 hours)

**Acceptance Criteria:**
- Given existing EmailAccount records
- When the migration runs
- Then each EmailAccount becomes an Account with one Owner user
- And all relationships are preserved
- And the migration can be rolled back if needed

#### User Story 4.2: Maintain API Compatibility
**As a** developer  
**I want** existing API endpoints to continue working  
**So that** external integrations don't break

**Tasks:**
- [ ] Create compatibility layer for API (4 hours)
- [ ] Map old endpoints to new structure (3 hours)
- [ ] Update API token scoping (3 hours)
- [ ] Add deprecation warnings (2 hours)
- [ ] Update API documentation (3 hours)

**Acceptance Criteria:**
- Given an existing API integration
- When it makes requests with existing tokens
- Then the requests continue to work
- And deprecation warnings are logged
- And new endpoints are available for migration

## Implementation Variants

### Variant 1: Minimal Implementation (Recommended for MVP)

**Approach:** Simple role-based system with fixed roles and basic permissions

**Architecture:**
```ruby
# Models
User (new)
  - email, password_digest, verified_at
  
Account (new)
  - name, settings
  
AccountUser (new)
  - user_id, account_id, role, status
  
EmailAccount (modified)
  - belongs_to :account
```

**Pros:**
- Fastest to implement (2-3 weeks)
- Minimal database changes
- Easy to understand and maintain
- Lower testing complexity

**Cons:**
- Limited flexibility in permissions
- No custom roles
- Basic audit trail only

**Implementation Steps:**
1. Create new models and migrations
2. Add basic permission checks
3. Update controllers with authorization
4. Create simple UI for user management
5. Migrate existing data

### Variant 2: Advanced RBAC with Granular Permissions

**Approach:** Flexible permission system with customizable roles and resource-level permissions

**Architecture:**
```ruby
# Models
User (new)
Role (new)
  - name, account_id, permissions (JSON)
  
Permission (new)
  - resource, action, conditions
  
AccountUser (modified)
  - custom_permissions (JSON) override
  
ResourcePermission (new)
  - user_id, resource_type, resource_id, permission_level
```

**Pros:**
- Maximum flexibility
- Granular control per resource
- Custom roles per account
- Enterprise-ready

**Cons:**
- Complex implementation (6-8 weeks)
- Performance overhead
- Steeper learning curve
- More testing required

**Implementation Steps:**
1. Design permission framework
2. Create permission models and services
3. Implement permission inheritance
4. Build permission management UI
5. Add caching layer
6. Comprehensive testing

### Variant 3: Hybrid Approach with Progressive Enhancement

**Approach:** Start with fixed roles but architecture for future flexibility

**Architecture:**
```ruby
# Models
User (new)
Account (new)
AccountUser (new)
  - role (enum)
  - custom_permissions (JSON, nullable)
  
PermissionTemplate (new)
  - role, permissions (for future custom roles)
```

**Pros:**
- Balanced complexity (3-4 weeks)
- Future-proof architecture
- Can evolve based on needs
- Good performance

**Cons:**
- Some unused structure initially
- Requires careful planning

**Implementation Steps:**
1. Implement basic role system
2. Add permission service with extension points
3. Create user management UI
4. Plan for future enhancements
5. Document extension patterns

## Dependencies & Risks

### Dependencies
- **Database Migration**: Requires maintenance window for data migration
- **Email Service**: User invitations depend on email delivery
- **Redis Cache**: Permission caching requires Redis availability
- **Session Management**: May need to invalidate existing sessions
- **Frontend Framework**: Turbo/Stimulus updates for multi-account context

### Risks

#### Risk 1: Data Migration Failure
- **Impact**: High - Could result in data loss or corruption
- **Probability**: Low
- **Mitigation**: 
  - Implement comprehensive migration tests
  - Create full database backup before migration
  - Design reversible migrations
  - Run migration on staging environment first
  - Implement gradual rollout with feature flags

#### Risk 2: Performance Degradation
- **Impact**: Medium - Could slow down application
- **Probability**: Medium
- **Mitigation**:
  - Implement aggressive permission caching
  - Add database indexes for new relationships
  - Monitor query performance
  - Load test with multiple concurrent users

#### Risk 3: Security Vulnerabilities
- **Impact**: High - Could expose financial data
- **Probability**: Low
- **Mitigation**:
  - Comprehensive security testing
  - Regular permission audits
  - Implement rate limiting
  - Add intrusion detection
  - Security code review

#### Risk 4: User Adoption Issues
- **Impact**: Medium - Users may struggle with new system
- **Probability**: Medium
- **Mitigation**:
  - Provide clear documentation
  - Add in-app guidance
  - Gradual feature rollout
  - Collect user feedback early
  - Maintain backward compatibility

## Implementation Phases

### Phase 1 (MVP - Weeks 1-2): Core Multi-User Support
**Goal**: Basic multi-user functionality with fixed roles

**Deliverables**:
- User model and authentication
- Account model with user associations
- Basic role system (Owner, Admin, Member, Viewer)
- Simple permission checks
- Data migration for existing accounts

**Success Criteria**:
- All existing accounts migrated successfully
- Users can be invited and join accounts
- Basic role-based access control working
- No data loss or corruption

### Phase 2 (Weeks 3-4): Enhanced Permissions and UI
**Goal**: Complete permission system and user management interface

**Deliverables**:
- Comprehensive permission service
- Controller authorization layer
- User management interface
- Account switching functionality
- Permission-based UI updates

**Success Criteria**:
- All actions properly authorized
- User management fully functional
- Clean, intuitive UI for multi-user features
- Performance meets requirements

### Phase 3 (Future): Advanced Features
**Goal**: Enterprise-ready features based on user feedback

**Potential Features**:
- Custom roles per account
- Resource-level permissions
- Approval workflows
- Advanced audit trail
- Team/Organization support
- SSO integration

## Open Questions

### Technical Questions
1. Should we use Devise for user authentication or continue with custom implementation?
2. What caching strategy for permissions (Redis, in-memory, database)?
3. Should account switching maintain separate sessions or share one?
4. How to handle API token permissions for multi-user accounts?
5. Should we implement soft-delete for users and accounts?

### Business Questions
1. What is the maximum number of users per account we should support?
2. Should we charge differently for multi-user accounts?
3. Do we need approval workflows for expense creation by non-owners?
4. Should viewers see actual amounts or just expense counts?
5. How long should user invitations remain valid?
6. Should removed users retain any historical data access?

### UX Questions
1. How prominent should role indicators be in the UI?
2. Should we show who created/modified each expense?
3. What happens to a user's created data when they're removed?
4. How to handle conflicts when multiple users edit simultaneously?
5. Should we add real-time collaboration features (presence indicators)?

## Testing Requirements

### Unit Tests
- User model validation and authentication
- Account model associations and scopes
- Permission service role checks
- AccountUser status transitions
- Migration data transformations

### Integration Tests
- User registration and verification flow
- Account creation with owner assignment
- User invitation and acceptance
- Role changes and permission updates
- Account switching functionality

### System Tests
- End-to-end multi-user workflows
- Permission enforcement across all features
- Concurrent user operations
- Session management and timeout
- Account and user deletion cascades

### Performance Tests
- Permission check response times
- Concurrent user load testing
- Database query optimization
- Cache effectiveness measurement
- UI responsiveness with multiple users

### Security Tests
- Password encryption verification
- Session hijacking prevention
- SQL injection in scoped queries
- Cross-account data leak testing
- API token permission enforcement

## Documentation Requirements

### Developer Documentation
- Model relationship diagrams
- Permission matrix reference
- API endpoint changes
- Migration guide for existing code
- Extension points for custom features

### User Documentation
- Getting started with multi-user accounts
- Role explanations and capabilities
- How to invite and manage users
- Security best practices
- Troubleshooting guide

### Administrator Documentation
- Migration procedures
- Backup and recovery processes
- Performance monitoring setup
- Security audit procedures
- Database maintenance guidelines

## Success Metrics

### Technical Metrics
- Zero data loss during migration
- <100ms permission check latency (p95)
- <500ms account switching time
- 100% backward compatibility maintained
- >95% test coverage for new code

### Business Metrics
- >30% of accounts add second user within 3 months
- <5% support tickets related to multi-user features
- User satisfaction score >4.5/5
- <2% user churn after implementation
- 20% increase in user engagement

### Security Metrics
- Zero security breaches
- <0.1% failed permission checks (indicating bugs)
- 100% of actions logged with user attribution
- <1% of sessions compromised
- Regular security audit pass rate >95%

## Appendix: Database Schema Changes

### New Tables

```sql
-- Users table
CREATE TABLE users (
  id BIGSERIAL PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_digest VARCHAR(255) NOT NULL,
  first_name VARCHAR(100),
  last_name VARCHAR(100),
  verified_at TIMESTAMP,
  verification_token VARCHAR(255),
  verification_sent_at TIMESTAMP,
  reset_password_token VARCHAR(255),
  reset_password_sent_at TIMESTAMP,
  failed_login_attempts INTEGER DEFAULT 0,
  locked_at TIMESTAMP,
  last_login_at TIMESTAMP,
  session_token VARCHAR(255),
  session_expires_at TIMESTAMP,
  preferences JSONB DEFAULT '{}',
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Accounts table
CREATE TABLE accounts (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  settings JSONB DEFAULT '{}',
  subscription_level VARCHAR(50) DEFAULT 'free',
  user_limit INTEGER DEFAULT 5,
  storage_used BIGINT DEFAULT 0,
  storage_limit BIGINT DEFAULT 1073741824, -- 1GB
  active BOOLEAN DEFAULT true,
  suspended_at TIMESTAMP,
  suspension_reason TEXT,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Account Users join table
CREATE TABLE account_users (
  id BIGSERIAL PRIMARY KEY,
  account_id BIGINT NOT NULL REFERENCES accounts(id),
  user_id BIGINT NOT NULL REFERENCES users(id),
  role INTEGER NOT NULL DEFAULT 2, -- Member
  status INTEGER NOT NULL DEFAULT 0, -- Invited
  invitation_token VARCHAR(255),
  invitation_sent_at TIMESTAMP,
  invitation_accepted_at TIMESTAMP,
  invited_by_id BIGINT REFERENCES users(id),
  joined_at TIMESTAMP,
  last_accessed_at TIMESTAMP,
  removed_at TIMESTAMP,
  removed_by_id BIGINT REFERENCES users(id),
  removal_reason TEXT,
  custom_permissions JSONB,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  UNIQUE(account_id, user_id)
);

-- Audit Log table
CREATE TABLE audit_logs (
  id BIGSERIAL PRIMARY KEY,
  account_id BIGINT NOT NULL REFERENCES accounts(id),
  user_id BIGINT NOT NULL REFERENCES users(id),
  action VARCHAR(100) NOT NULL,
  resource_type VARCHAR(100),
  resource_id BIGINT,
  changes JSONB,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP NOT NULL
);
```

### Modified Tables

```sql
-- Add account_id to email_accounts
ALTER TABLE email_accounts 
  ADD COLUMN account_id BIGINT REFERENCES accounts(id),
  ADD COLUMN created_by_id BIGINT REFERENCES users(id);

-- Add user tracking to expenses
ALTER TABLE expenses
  ADD COLUMN created_by_id BIGINT REFERENCES users(id),
  ADD COLUMN updated_by_id BIGINT REFERENCES users(id);

-- Add user tracking to categories
ALTER TABLE categories
  ADD COLUMN account_id BIGINT REFERENCES accounts(id),
  ADD COLUMN created_by_id BIGINT REFERENCES users(id);

-- Update API tokens for user scoping
ALTER TABLE api_tokens
  ADD COLUMN user_id BIGINT REFERENCES users(id),
  ADD COLUMN account_id BIGINT REFERENCES accounts(id),
  ADD COLUMN scopes JSONB DEFAULT '[]';
```

### Indexes

```sql
-- User indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_verification_token ON users(verification_token);
CREATE INDEX idx_users_session_token ON users(session_token);

-- Account indexes  
CREATE INDEX idx_accounts_active ON accounts(active);

-- AccountUser indexes
CREATE INDEX idx_account_users_account_id ON account_users(account_id);
CREATE INDEX idx_account_users_user_id ON account_users(user_id);
CREATE INDEX idx_account_users_status ON account_users(status);
CREATE INDEX idx_account_users_role ON account_users(role);
CREATE INDEX idx_account_users_invitation_token ON account_users(invitation_token);

-- Audit log indexes
CREATE INDEX idx_audit_logs_account_id ON audit_logs(account_id);
CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_resource ON audit_logs(resource_type, resource_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at);
```

---

*This document serves as the comprehensive requirements specification for implementing multi-user accounts with role-based access control in the expense tracking application. It should be reviewed and approved by all stakeholders before implementation begins.*