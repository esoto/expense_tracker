# Ticket 4.3: Comprehensive Testing Suite

## Ticket Information
- **Epic**: Epic 4 - Polish and Migration (Weeks 7-8)
- **Priority**: HIGH
- **Story Points**: 8
- **Risk Level**: MEDIUM
- **Dependencies**: 
  - All features implemented
  - Test infrastructure in place

## Description
Create a comprehensive testing suite for the multi-tenant system, including unit tests, integration tests, system tests, and performance tests. Ensure all critical paths are covered, edge cases are handled, and the system maintains data integrity under various scenarios.

## Technical Requirements
1. Complete test coverage for all new models
2. Controller and request specs for all endpoints
3. Service layer testing with tenant isolation
4. System tests for critical user journeys
5. Performance and load testing
6. Security testing for tenant isolation

## Acceptance Criteria
- [ ] Model test coverage:
  - Account model with all validations and callbacks
  - User model with Devise integration
  - AccountMembership with role permissions
  - Expense visibility scoping
  - All associations and scopes tested
- [ ] Controller test coverage:
  - Authentication and authorization
  - Tenant context management
  - Account switching
  - Member management
  - Invitation flow
- [ ] Service test coverage:
  - Email processing with tenant context
  - Categorization services
  - Migration services
  - Background job processing
- [ ] System test coverage:
  - Complete user registration flow
  - Account creation and setup
  - Member invitation and acceptance
  - Expense management with visibility
  - Account switching scenarios
- [ ] Performance tests:
  - Page load times < 200ms
  - Database query optimization
  - N+1 query detection
  - Concurrent user simulation
- [ ] Security tests:
  - Tenant isolation verification
  - Permission boundary testing
  - SQL injection prevention
  - XSS protection

## Implementation Details
```ruby
# spec/models/account_spec.rb
require 'rails_helper'

RSpec.describe Account, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:slug) }
    it { should validate_numericality_of(:max_users).is_greater_than(0) }
    
    it 'generates slug from name' do
      account = create(:account, name: 'Test Account')
      expect(account.slug).to eq('test-account')
    end
    
    it 'ensures unique slug on collision' do
      create(:account, name: 'Test Account')
      account2 = create(:account, name: 'Test Account')
      expect(account2.slug).to match(/test-account-\d+/)
    end
  end
  
  describe 'associations' do
    it { should have_many(:account_memberships).dependent(:destroy) }
    it { should have_many(:users).through(:account_memberships) }
    it { should have_many(:expenses).dependent(:destroy) }
    it { should have_many(:categories).dependent(:destroy) }
  end
  
  describe 'callbacks' do
    it 'creates default categories after creation' do
      account = create(:account)
      expect(account.categories.count).to eq(6)
      expect(account.categories.pluck(:name)).to include('Sin Categoría')
    end
  end
  
  describe '#add_user' do
    let(:account) { create(:account) }
    let(:user) { create(:user) }
    
    it 'adds user with specified role' do
      membership = account.add_user(user, role: :admin)
      expect(membership).to be_persisted
      expect(membership.role).to eq('admin')
    end
    
    it 'prevents duplicate memberships' do
      account.add_user(user, role: :member)
      expect {
        account.add_user(user, role: :admin)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
    
    it 'respects user limit' do
      account.update(max_users: 2)
      account.add_user(create(:user), role: :owner)
      account.add_user(create(:user), role: :member)
      
      expect {
        account.add_user(create(:user), role: :member)
      }.to raise_error(/user limit/)
    end
  end
end

# spec/models/expense_visibility_spec.rb
require 'rails_helper'

RSpec.describe 'Expense Visibility', type: :model do
  let(:account) { create(:account) }
  let(:owner) { create(:user) }
  let(:member) { create(:user) }
  let(:other_user) { create(:user) }
  
  before do
    account.add_user(owner, role: :owner)
    account.add_user(member, role: :member)
  end
  
  describe 'visibility scoping' do
    let!(:shared_expense) { create(:expense, account: account, visibility: :shared) }
    let!(:owner_personal) { create(:expense, account: account, user: owner, visibility: :personal) }
    let!(:member_personal) { create(:expense, account: account, user: member, visibility: :personal) }
    
    context 'for expense owner' do
      it 'sees shared and own personal expenses' do
        visible = Expense.visible_to(owner)
        expect(visible).to include(shared_expense)
        expect(visible).to include(owner_personal)
        expect(visible).not_to include(member_personal)
      end
    end
    
    context 'for other member' do
      it 'sees shared and own personal expenses only' do
        visible = Expense.visible_to(member)
        expect(visible).to include(shared_expense)
        expect(visible).not_to include(owner_personal)
        expect(visible).to include(member_personal)
      end
    end
    
    context 'for non-member' do
      it 'sees no expenses' do
        ActsAsTenant.with_tenant(account) do
          visible = Expense.visible_to(other_user)
          expect(visible).to be_empty
        end
      end
    end
  end
end

# spec/requests/tenant_isolation_spec.rb
require 'rails_helper'

RSpec.describe 'Tenant Isolation', type: :request do
  let(:account1) { create(:account) }
  let(:account2) { create(:account) }
  let(:user1) { create(:user) }
  let(:user2) { create(:user) }
  
  before do
    account1.add_user(user1, role: :owner)
    account2.add_user(user2, role: :owner)
  end
  
  describe 'data isolation' do
    let!(:expense1) { create(:expense, account: account1) }
    let!(:expense2) { create(:expense, account: account2) }
    
    it 'prevents cross-tenant data access' do
      sign_in user1
      
      get expense_path(expense1)
      expect(response).to have_http_status(:success)
      
      get expense_path(expense2)
      expect(response).to have_http_status(:not_found)
    end
    
    it 'scopes index queries to current tenant' do
      sign_in user1
      
      get expenses_path
      expect(response.body).to include(expense1.description)
      expect(response.body).not_to include(expense2.description)
    end
  end
  
  describe 'account switching' do
    before do
      account2.add_user(user1, role: :member)
      sign_in user1
    end
    
    it 'switches tenant context' do
      post switch_account_path(account2)
      expect(session[:current_account_id]).to eq(account2.id)
      
      get expenses_path
      expect(assigns(:expenses).to_sql).to include("account_id = #{account2.id}")
    end
    
    it 'updates last accessed timestamp' do
      membership = user1.account_memberships.find_by(account: account2)
      
      expect {
        post switch_account_path(account2)
      }.to change { membership.reload.last_accessed_at }
    end
  end
end

# spec/system/multi_tenant_journey_spec.rb
require 'rails_helper'

RSpec.describe 'Multi-tenant User Journey', type: :system do
  scenario 'New user signs up and creates account' do
    visit root_path
    click_link 'Sign Up'
    
    fill_in 'Name', with: 'John Doe'
    fill_in 'Email', with: 'john@example.com'
    fill_in 'Password', with: 'password123'
    fill_in 'Password confirmation', with: 'password123'
    
    click_button 'Sign Up'
    
    # Auto-created personal account
    expect(page).to have_content('Personal - John')
    expect(page).to have_content('personal')
    
    # Can create additional account
    click_link 'Create New Account'
    fill_in 'Account name', with: 'Family Budget'
    select 'Family', from: 'Account type'
    click_button 'Create Account'
    
    expect(page).to have_content('Family Budget')
    expect(page).to have_content('You are the owner')
  end
  
  scenario 'Account owner invites and manages members' do
    owner = create(:user)
    account = create(:account, name: 'Shared Account')
    account.add_user(owner, role: :owner)
    
    sign_in owner
    visit account_path(account)
    
    # Send invitation
    click_link 'Invite Member'
    fill_in 'Email', with: 'newmember@example.com'
    select 'Member', from: 'Role'
    click_button 'Send Invitation'
    
    expect(page).to have_content('Invitation sent')
    expect(page).to have_content('1 pending invitation')
    
    # New user accepts invitation
    invitation = AccountInvitation.last
    
    using_session :new_user do
      visit account_invitation_path(token: invitation.token)
      expect(page).to have_content('You've been invited to join Shared Account')
      
      click_link 'Sign up to accept'
      fill_in 'Name', with: 'New Member'
      fill_in 'Password', with: 'password123'
      fill_in 'Password confirmation', with: 'password123'
      click_button 'Sign Up'
      
      expect(page).to have_content('Shared Account')
      expect(page).to have_content('member')
    end
  end
  
  scenario 'Members manage expenses with visibility controls' do
    account = create(:account)
    user1 = create(:user, name: 'User One')
    user2 = create(:user, name: 'User Two')
    
    account.add_user(user1, role: :member)
    account.add_user(user2, role: :member)
    
    # User 1 creates expenses
    sign_in user1
    visit new_expense_path
    
    fill_in 'Amount', with: '100.00'
    fill_in 'Description', with: 'Shared groceries'
    select 'Shared', from: 'Visibility'
    click_button 'Create Expense'
    
    visit new_expense_path
    fill_in 'Amount', with: '50.00'
    fill_in 'Description', with: 'Personal purchase'
    select 'Personal', from: 'Visibility'
    click_button 'Create Expense'
    
    # User 2 sees only shared expenses
    sign_out user1
    sign_in user2
    
    visit expenses_path
    expect(page).to have_content('Shared groceries')
    expect(page).not_to have_content('Personal purchase')
    
    # Filter by visibility
    select 'My Personal', from: 'Visibility filter'
    expect(page).not_to have_content('Shared groceries')
  end
end

# spec/performance/tenant_performance_spec.rb
require 'rails_helper'
require 'benchmark'

RSpec.describe 'Tenant Performance', type: :performance do
  describe 'query performance' do
    let!(:accounts) { create_list(:account, 10) }
    
    before do
      accounts.each do |account|
        create_list(:expense, 100, account: account)
        create_list(:category, 20, account: account)
      end
    end
    
    it 'maintains sub-200ms response time' do
      account = accounts.first
      user = create(:user)
      account.add_user(user, role: :member)
      
      time = Benchmark.realtime do
        ActsAsTenant.with_tenant(account) do
          Expense.includes(:category).recent.limit(50).to_a
        end
      end
      
      expect(time).to be < 0.2 # 200ms
    end
    
    it 'prevents N+1 queries' do
      account = accounts.first
      
      ActsAsTenant.with_tenant(account) do
        expect {
          Expense.includes(:category, :user).each do |expense|
            expense.category&.name
            expense.user&.name
          end
        }.to perform_constant_number_of_queries
      end
    end
  end
end
```

## Test Data Factories
```ruby
# spec/factories/accounts.rb
FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Account #{n}" }
    account_type { :personal }
    max_users { 5 }
    active { true }
    
    trait :couple do
      account_type { :couple }
      max_users { 2 }
    end
    
    trait :family do
      account_type { :family }
      max_users { 10 }
    end
    
    trait :with_members do
      transient do
        members_count { 3 }
      end
      
      after(:create) do |account, evaluator|
        create_list(:account_membership, evaluator.members_count, account: account)
      end
    end
  end
end
```

## Test Coverage Requirements
- [ ] Line coverage > 95%
- [ ] Branch coverage > 90%
- [ ] All critical paths covered
- [ ] Edge cases identified and tested
- [ ] Error conditions handled
- [ ] Security scenarios tested

## Performance Benchmarks
- [ ] Page load time < 200ms (p95)
- [ ] API response time < 100ms (p95)
- [ ] Database queries < 10 per request
- [ ] No N+1 queries
- [ ] Memory usage stable under load

## Security Test Scenarios
- [ ] Cannot access other tenant's data
- [ ] Cannot elevate own permissions
- [ ] Cannot bypass visibility controls
- [ ] Cannot manipulate account_id
- [ ] Session hijacking prevention
- [ ] CSRF protection working

## Definition of Done
- [ ] All test files created
- [ ] Test coverage > 95%
- [ ] All tests passing
- [ ] Performance benchmarks met
- [ ] Security tests passing
- [ ] No flaky tests
- [ ] CI/CD pipeline green
- [ ] Test documentation updated
- [ ] Code reviewed
- [ ] Load testing completed