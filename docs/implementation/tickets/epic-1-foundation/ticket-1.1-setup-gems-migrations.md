# Ticket 1.1: Setup Multi-tenancy Gems and Initial Migrations

## Ticket Information
- **Epic**: Epic 1 - Foundation (Weeks 1-2)
- **Priority**: HIGH
- **Story Points**: 3
- **Risk Level**: LOW
- **Dependencies**: None - This is the starting point

## Description
Install and configure the acts_as_tenant gem along with any supporting gems needed for multi-tenancy implementation. Create the initial migration structure for the multi-tenant architecture without executing migrations yet.

## Technical Requirements
1. Add required gems to Gemfile
2. Configure acts_as_tenant initializer
3. Create migration files for new tables (without running them)
4. Set up middleware for tenant security
5. Configure development and test environments

## Acceptance Criteria
- [ ] acts_as_tenant gem (v1.0+) is added to Gemfile
- [ ] Bundle install completes successfully
- [ ] acts_as_tenant initializer is created at `config/initializers/acts_as_tenant.rb` with:
  - `require_tenant = true` setting
  - Custom error handling configured
  - Tenant not set exception handler defined
- [ ] TenantSecurity middleware class is created and registered in application.rb
- [ ] Migration files are created but NOT executed:
  - `001_create_accounts.rb`
  - `002_create_users.rb` (if not using Devise yet)
  - `003_create_account_memberships.rb`
  - `004_add_account_id_to_existing_tables.rb`
  - `005_create_account_invitations.rb`
  - `006_create_audit_logs.rb`
- [ ] All migration files include proper indexes for performance
- [ ] Test helper module `MultiTenantHelpers` is created in spec/support
- [ ] No breaking changes to existing functionality
- [ ] All existing tests still pass

## Implementation Details
```ruby
# Gemfile additions
gem 'acts_as_tenant', '~> 1.0'
gem 'devise', '~> 4.9' # If not already present

# config/initializers/acts_as_tenant.rb
ActsAsTenant.configure do |config|
  config.require_tenant = true
  config.tenant_not_set_exception = lambda do
    raise ActsAsTenant::Errors::NoTenantSet, "No account set for current request"
  end
end

# app/middleware/tenant_security.rb
class TenantSecurity
  def initialize(app)
    @app = app
  end
  
  def call(env)
    ActsAsTenant.current_tenant = nil
    status, headers, response = @app.call(env)
    ActsAsTenant.current_tenant = nil
    [status, headers, response]
  end
end
```

## Testing Requirements
- [ ] Create spec file: `spec/middleware/tenant_security_spec.rb`
- [ ] Test that middleware clears tenant before and after requests
- [ ] Test that initializer properly raises exceptions when tenant not set
- [ ] Verify all migration files are syntactically valid
- [ ] Ensure no regression in existing test suite

## Performance Considerations
- Migration files should include all necessary indexes from the start
- Consider compound indexes for common query patterns
- Plan for future partitioning if needed

## Security Considerations
- Middleware must clear tenant context to prevent leakage between requests
- Ensure proper exception handling for missing tenant scenarios
- Document security implications for other developers

## Definition of Done
- [ ] Code reviewed by senior developer
- [ ] All tests passing
- [ ] Migration files reviewed for proper indexes
- [ ] Security middleware tested in development
- [ ] Documentation updated in project README
- [ ] No performance regression in development environment