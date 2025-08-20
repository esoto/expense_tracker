# Ticket 1.2: Create Account and User Models with Devise

## Ticket Information
- **Epic**: Epic 1 - Foundation (Weeks 1-2)
- **Priority**: HIGH
- **Story Points**: 5
- **Risk Level**: MEDIUM
- **Dependencies**: Ticket 1.1 (Setup Gems and Migrations)

## Description
Implement the core Account and User models with full Devise authentication integration. These models form the foundation of the multi-tenant architecture. The Account model represents a tenant (couple/family unit), while the User model handles authentication and can belong to multiple accounts.

## Technical Requirements
1. Run migrations created in Ticket 1.1
2. Implement Account model with validations and associations
3. Configure User model with Devise modules
4. Create AccountMembership join model with roles
5. Implement model callbacks and business logic
6. Add model concerns for shared functionality

## Acceptance Criteria
- [ ] All migrations from Ticket 1.1 execute successfully
- [ ] Account model is created with:
  - Enum for account_type (personal/couple/family/business)
  - JSONB settings field with default values
  - Slug generation for URL-friendly identifiers
  - Soft-delete capability (suspended_at)
  - User limit enforcement (max_users)
- [ ] User model is configured with:
  - Full Devise authentication (database_authenticatable, registerable, recoverable, rememberable, validatable, confirmable, lockable, trackable)
  - JSONB preferences field
  - Automatic personal account creation on user creation
  - Display name logic
- [ ] AccountMembership model includes:
  - Role enum (owner/admin/member/viewer)
  - Permission system with JSONB field
  - Joined/last accessed tracking
  - Invitation token support
  - Validation for at least one owner per account
- [ ] All model associations are properly configured and tested
- [ ] Database indexes are verified to be in place
- [ ] Model validations prevent invalid data
- [ ] Callbacks execute in correct order
- [ ] Devise routes are configured

## Implementation Details
```ruby
# app/models/account.rb
class Account < ApplicationRecord
  enum account_type: {
    personal: 0,
    couple: 1,
    family: 2,
    business: 3
  }
  
  # Associations
  has_many :account_memberships, dependent: :destroy
  has_many :users, through: :account_memberships
  has_many :active_memberships, -> { where(active: true) }, 
           class_name: 'AccountMembership'
  has_many :active_users, through: :active_memberships, source: :user
  
  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :slug, presence: true, uniqueness: true
  validates :max_users, numericality: { greater_than: 0, less_than_or_equal_to: 10 }
  
  # Callbacks
  before_validation :generate_slug, on: :create
  after_create :create_default_categories
end

# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :lockable, :trackable
  
  has_many :account_memberships, dependent: :destroy
  has_many :accounts, through: :account_memberships
  
  after_create :create_personal_account
end

# app/models/account_membership.rb
class AccountMembership < ApplicationRecord
  enum role: {
    owner: 0,
    admin: 1,
    member: 2,
    viewer: 3
  }
  
  belongs_to :account
  belongs_to :user
  
  validates :account_id, uniqueness: { scope: :user_id }
  validate :at_least_one_owner
end
```

## Testing Requirements
- [ ] Model specs for Account:
  - Test account type enum
  - Test slug generation
  - Test user limit enforcement
  - Test suspension/reactivation
  - Test default category creation
- [ ] Model specs for User:
  - Test Devise authentication features
  - Test personal account auto-creation
  - Test multi-account associations
  - Test role checking methods
- [ ] Model specs for AccountMembership:
  - Test role permissions
  - Test owner validation
  - Test unique user per account
  - Test cascading deletes
- [ ] Integration tests for user registration flow
- [ ] Test account switching functionality

## Database Considerations
- [ ] Verify all foreign key constraints are in place
- [ ] Check index performance with sample data
- [ ] Ensure JSONB fields have GIN indexes
- [ ] Validate cascade delete behavior

## Security Considerations
- [ ] Devise security settings configured properly
- [ ] Password complexity requirements set
- [ ] Account lockout after failed attempts configured
- [ ] Email confirmation required for new users
- [ ] Secure token generation for invitations

## Technical Implementation

### Database Considerations

#### Comprehensive Model Schema Design
```ruby
# db/migrate/create_accounts_users_and_memberships.rb
class CreateAccountsUsersAndMemberships < ActiveRecord::Migration[8.0]
  def up
    # Enable required PostgreSQL extensions
    enable_extension 'uuid-ossp'
    enable_extension 'pgcrypto'
    enable_extension 'btree_gin' # For composite GIN indexes
    
    # Create accounts table with optimized structure
    create_table :accounts do |t|
      t.string :name, null: false, limit: 100
      t.string :slug, null: false, limit: 100
      t.integer :account_type, default: 0, null: false
      t.jsonb :settings, default: {}, null: false
      t.integer :max_users, default: 5, null: false
      t.datetime :suspended_at
      t.string :suspension_reason
      t.uuid :public_id, default: -> { 'gen_random_uuid()' }, null: false
      
      # Billing and subscription fields
      t.string :stripe_customer_id
      t.string :subscription_status
      t.datetime :trial_ends_at
      t.datetime :subscription_ends_at
      
      # Analytics and tracking
      t.integer :expenses_count, default: 0, null: false
      t.integer :categories_count, default: 0, null: false
      t.decimal :total_spent_cents, precision: 15, scale: 2, default: 0
      t.datetime :last_activity_at
      
      t.timestamps
      
      t.index :slug, unique: true
      t.index :public_id, unique: true
      t.index :account_type
      t.index :suspended_at
      t.index :settings, using: :gin
      t.index :created_at
      t.index [:account_type, :suspended_at], name: 'idx_accounts_type_status'
    end
    
    # Add check constraints for data integrity
    execute <<-SQL
      ALTER TABLE accounts
      ADD CONSTRAINT check_max_users_positive
      CHECK (max_users > 0 AND max_users <= 100);
      
      ALTER TABLE accounts
      ADD CONSTRAINT check_name_length
      CHECK (char_length(name) >= 2);
      
      ALTER TABLE accounts
      ADD CONSTRAINT check_valid_account_type
      CHECK (account_type IN (0, 1, 2, 3));
    SQL
    
    # Create users table with Devise requirements
    create_table :users do |t|
      # Devise core fields
      t.string :email, null: false, limit: 255
      t.string :encrypted_password, null: false
      
      # Devise recoverable
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      
      # Devise rememberable
      t.datetime :remember_created_at
      
      # Devise trackable
      t.integer :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.inet :current_sign_in_ip
      t.inet :last_sign_in_ip
      
      # Devise confirmable
      t.string :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string :unconfirmed_email
      
      # Devise lockable
      t.integer :failed_attempts, default: 0, null: false
      t.string :unlock_token
      t.datetime :locked_at
      
      # User profile fields
      t.string :name, limit: 100
      t.string :phone, limit: 20
      t.string :timezone, default: 'UTC', null: false
      t.string :locale, default: 'en', null: false
      t.jsonb :preferences, default: {}, null: false
      t.uuid :public_id, default: -> { 'gen_random_uuid()' }, null: false
      
      # Current context
      t.bigint :current_account_id
      t.datetime :last_seen_at
      
      # Soft delete
      t.datetime :deleted_at
      
      t.timestamps
      
      t.index :email, unique: true
      t.index :reset_password_token, unique: true
      t.index :confirmation_token, unique: true
      t.index :unlock_token, unique: true
      t.index :public_id, unique: true
      t.index :preferences, using: :gin
      t.index :deleted_at
      t.index [:email, :deleted_at], unique: true, where: 'deleted_at IS NULL'
    end
    
    # Create account_memberships join table
    create_table :account_memberships do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :role, default: 2, null: false # member by default
      t.jsonb :permissions, default: {}, null: false
      t.boolean :active, default: true, null: false
      
      # Invitation tracking
      t.string :invitation_token
      t.datetime :invitation_sent_at
      t.datetime :invitation_accepted_at
      t.bigint :invited_by_id
      
      # Activity tracking
      t.datetime :joined_at, null: false
      t.datetime :last_accessed_at
      t.integer :access_count, default: 0, null: false
      
      t.timestamps
      
      t.index [:account_id, :user_id], unique: true
      t.index [:user_id, :account_id], name: 'idx_memberships_user_account'
      t.index :role
      t.index :active
      t.index :invitation_token, unique: true, where: 'invitation_token IS NOT NULL'
      t.index :permissions, using: :gin
      t.index [:account_id, :role, :active], name: 'idx_memberships_account_role_active'
    end
    
    # Add foreign key for invited_by
    add_foreign_key :account_memberships, :users, column: :invited_by_id
    
    # Add foreign key for current_account
    add_foreign_key :users, :accounts, column: :current_account_id
    
    # Create trigger to maintain at least one owner
    execute <<-SQL
      CREATE OR REPLACE FUNCTION ensure_account_has_owner()
      RETURNS TRIGGER AS $$
      BEGIN
        IF (OLD.role = 0 AND NEW.role != 0) OR 
           (OLD.active = true AND NEW.active = false AND OLD.role = 0) THEN
          -- Check if this is the last active owner
          IF NOT EXISTS (
            SELECT 1 FROM account_memberships
            WHERE account_id = NEW.account_id
            AND user_id != NEW.user_id
            AND role = 0
            AND active = true
          ) THEN
            RAISE EXCEPTION 'Account must have at least one active owner';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      
      CREATE TRIGGER ensure_owner_exists
      BEFORE UPDATE ON account_memberships
      FOR EACH ROW
      EXECUTE FUNCTION ensure_account_has_owner();
    SQL
  end
  
  def down
    drop_trigger :account_memberships, :ensure_owner_exists
    drop_function :ensure_account_has_owner
    drop_table :account_memberships
    drop_table :users
    drop_table :accounts
  end
end
```

#### Performance Indexes and Optimization
```ruby
# db/migrate/add_performance_indexes.rb
class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  
  def up
    # Composite indexes for common queries
    add_index :accounts, [:suspended_at, :created_at], 
              algorithm: :concurrently,
              name: 'idx_accounts_active_recent'
    
    add_index :users, [:confirmed_at, :locked_at, :deleted_at],
              algorithm: :concurrently,
              name: 'idx_users_status',
              where: 'deleted_at IS NULL'
    
    # Partial indexes for active records
    add_index :account_memberships, [:account_id, :user_id, :role],
              algorithm: :concurrently,
              name: 'idx_active_memberships',
              where: 'active = true'
    
    # Full-text search indexes
    execute <<-SQL
      CREATE INDEX CONCURRENTLY idx_accounts_name_search
      ON accounts USING gin(to_tsvector('english', name));
      
      CREATE INDEX CONCURRENTLY idx_users_name_email_search
      ON users USING gin(
        to_tsvector('english', coalesce(name, '') || ' ' || email)
      );
    SQL
    
    # Update statistics for query planner
    execute <<-SQL
      ALTER TABLE accounts ALTER COLUMN account_type SET STATISTICS 500;
      ALTER TABLE account_memberships ALTER COLUMN role SET STATISTICS 500;
      ANALYZE accounts, users, account_memberships;
    SQL
  end
end
```

### Code Architecture

#### Enhanced Account Model
```ruby
# app/models/account.rb
class Account < ApplicationRecord
  include Sluggable
  include SoftDeletable
  include Billable
  
  # Constants
  MAX_USERS_BY_TYPE = {
    personal: 1,
    couple: 2,
    family: 5,
    business: 10
  }.freeze
  
  DEFAULT_SETTINGS = {
    currency: 'USD',
    fiscal_year_start: 1, # January
    week_start: 1, # Monday
    date_format: 'MM/DD/YYYY',
    notifications: {
      daily_summary: false,
      weekly_report: true,
      budget_alerts: true,
      new_expense: false
    },
    privacy: {
      share_expenses: true,
      require_approval: false
    },
    features: {
      auto_categorization: true,
      receipt_scanning: false,
      multi_currency: false
    }
  }.freeze
  
  # Enums
  enum account_type: {
    personal: 0,
    couple: 1,
    family: 2,
    business: 3
  }
  
  enum subscription_status: {
    trialing: 0,
    active: 1,
    past_due: 2,
    canceled: 3,
    unpaid: 4
  }, _prefix: true
  
  # Associations
  has_many :account_memberships, dependent: :destroy
  has_many :users, through: :account_memberships
  has_many :active_memberships, -> { active }, class_name: 'AccountMembership'
  has_many :active_users, through: :active_memberships, source: :user
  has_many :owners, -> { where(account_memberships: { role: :owner, active: true }) },
           through: :account_memberships, source: :user
  
  # Tenant associations (will be added by acts_as_tenant)
  has_many :expenses, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :budgets, dependent: :destroy
  has_many :email_accounts, dependent: :destroy
  
  # Validations
  validates :name, presence: true, 
                   length: { minimum: 2, maximum: 100 }
  
  validates :slug, presence: true, 
                   uniqueness: { case_sensitive: false },
                   format: { with: /\A[a-z0-9-]+\z/,
                           message: 'only lowercase letters, numbers and dashes' }
  
  validates :max_users, numericality: { 
    greater_than: 0,
    less_than_or_equal_to: 100
  }
  
  validate :max_users_within_type_limit
  validate :settings_structure
  
  # Callbacks
  before_validation :set_defaults, on: :create
  before_validation :generate_slug, on: :create
  after_create :create_default_categories
  after_create :initialize_subscription
  after_update :handle_suspension_change, if: :saved_change_to_suspended_at?
  
  # Scopes
  scope :active, -> { where(suspended_at: nil) }
  scope :suspended, -> { where.not(suspended_at: nil) }
  scope :trialing, -> { where('trial_ends_at > ?', Time.current) }
  scope :with_stats, -> {
    select('accounts.*, 
            COUNT(DISTINCT account_memberships.id) as members_count,
            COUNT(DISTINCT expenses.id) as expenses_count')
    .left_joins(:account_memberships, :expenses)
    .group('accounts.id')
  }
  
  # Store accessors for JSONB
  store_accessor :settings, :currency, :fiscal_year_start, :week_start,
                 :date_format, :notifications, :privacy, :features
  
  # Class methods
  def self.create_with_owner!(user, attributes = {})
    transaction do
      account = create!(attributes)
      account.account_memberships.create!(
        user: user,
        role: :owner,
        joined_at: Time.current
      )
      account
    end
  end
  
  # Instance methods
  def suspended?
    suspended_at.present?
  end
  
  def suspend!(reason = nil)
    update!(
      suspended_at: Time.current,
      suspension_reason: reason
    )
  end
  
  def reactivate!
    update!(
      suspended_at: nil,
      suspension_reason: nil
    )
  end
  
  def can_add_user?
    active_users.count < max_users
  end
  
  def owner?(user)
    account_memberships.owner.active.exists?(user: user)
  end
  
  def member?(user)
    account_memberships.active.exists?(user: user)
  end
  
  def usage_percentage
    return 0 if max_users.zero?
    (active_users.count.to_f / max_users * 100).round(2)
  end
  
  private
  
  def set_defaults
    self.settings = DEFAULT_SETTINGS.deep_merge(settings || {})
    self.max_users ||= MAX_USERS_BY_TYPE[account_type.to_sym] || 5
  end
  
  def generate_slug
    return if slug.present?
    
    base_slug = name.parameterize
    counter = 0
    
    loop do
      test_slug = counter.zero? ? base_slug : "#{base_slug}-#{counter}"
      unless Account.exists?(slug: test_slug)
        self.slug = test_slug
        break
      end
      counter += 1
    end
  end
  
  def max_users_within_type_limit
    return unless account_type.present?
    
    limit = MAX_USERS_BY_TYPE[account_type.to_sym]
    if max_users > limit
      errors.add(:max_users, "cannot exceed #{limit} for #{account_type} accounts")
    end
  end
  
  def settings_structure
    return if settings.blank?
    
    # Validate settings structure
    required_keys = %w[currency notifications privacy features]
    missing_keys = required_keys - settings.keys
    
    if missing_keys.any?
      errors.add(:settings, "missing required keys: #{missing_keys.join(', ')}")
    end
  end
  
  def create_default_categories
    default_categories = [
      { name: 'Groceries', color: '#10B981', icon: 'shopping-cart' },
      { name: 'Dining', color: '#F59E0B', icon: 'restaurant' },
      { name: 'Transportation', color: '#3B82F6', icon: 'car' },
      { name: 'Utilities', color: '#6366F1', icon: 'home' },
      { name: 'Entertainment', color: '#EC4899', icon: 'movie' },
      { name: 'Healthcare', color: '#EF4444', icon: 'medical' },
      { name: 'Shopping', color: '#8B5CF6', icon: 'shopping-bag' },
      { name: 'Other', color: '#6B7280', icon: 'dots' }
    ]
    
    categories.create!(default_categories)
  end
  
  def handle_suspension_change
    if suspended?
      SuspendAccountJob.perform_later(self)
    else
      ReactivateAccountJob.perform_later(self)
    end
  end
end
```

#### Enhanced User Model with Devise
```ruby
# app/models/user.rb
class User < ApplicationRecord
  include SoftDeletable
  
  # Devise modules
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :lockable, :trackable,
         :timeoutable, :omniauthable
  
  # Constants
  PASSWORD_MIN_LENGTH = 8
  PASSWORD_REQUIREMENTS = /\A
    (?=.*\d)           # Must contain a digit
    (?=.*[a-z])        # Must contain a lowercase letter
    (?=.*[A-Z])        # Must contain an uppercase letter
    (?=.*[[:^alnum:]]) # Must contain a special character
  /x
  
  # Associations
  has_many :account_memberships, dependent: :destroy
  has_many :accounts, through: :account_memberships
  has_many :active_memberships, -> { active }, class_name: 'AccountMembership'
  has_many :active_accounts, through: :active_memberships, source: :account
  has_many :owned_accounts, -> { where(account_memberships: { role: :owner }) },
           through: :account_memberships, source: :account
  
  belongs_to :current_account, class_name: 'Account', optional: true
  
  has_many :created_expenses, class_name: 'Expense', foreign_key: :created_by_id
  has_many :api_tokens, dependent: :destroy
  has_many :activities, dependent: :destroy
  
  # Validations
  validates :email, presence: true,
                   uniqueness: { case_sensitive: false },
                   format: { with: URI::MailTo::EMAIL_REGEXP }
  
  validates :name, length: { maximum: 100 }
  
  validates :timezone, inclusion: { 
    in: ActiveSupport::TimeZone.all.map(&:name) 
  }
  
  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }
  
  validate :password_complexity, if: :password_required?
  
  # Callbacks
  before_validation :normalize_email, on: [:create, :update]
  after_create :create_personal_account
  after_create :send_welcome_email
  before_destroy :check_account_ownership
  
  # Scopes
  scope :confirmed, -> { where.not(confirmed_at: nil) }
  scope :locked, -> { where.not(locked_at: nil) }
  scope :active, -> { confirmed.where(locked_at: nil, deleted_at: nil) }
  scope :recently_active, -> { where('last_seen_at > ?', 30.days.ago) }
  
  # Store accessors for preferences
  store_accessor :preferences, :theme, :email_frequency, 
                 :default_category_id, :auto_categorize,
                 :dashboard_widgets, :notification_settings
  
  # Devise customizations
  def active_for_authentication?
    super && !deleted_at && !locked_at
  end
  
  def inactive_message
    if deleted_at
      :deleted_account
    elsif locked_at
      :locked
    else
      super
    end
  end
  
  # Instance methods
  def display_name
    name.presence || email.split('@').first
  end
  
  def initials
    display_name.split.map(&:first).join.upcase[0..1]
  end
  
  def has_role?(role, account = current_account)
    return false unless account
    
    membership = account_memberships.find_by(account: account)
    return false unless membership&.active?
    
    membership.has_role?(role)
  end
  
  def can?(permission, account = current_account)
    return false unless account
    
    membership = account_memberships.find_by(account: account)
    return false unless membership&.active?
    
    membership.can?(permission)
  end
  
  def switch_account!(account)
    return false unless member_of?(account)
    
    update!(current_account: account)
    account_memberships.find_by(account: account)
          .update!(last_accessed_at: Time.current)
    true
  end
  
  def member_of?(account)
    account_memberships.active.exists?(account: account)
  end
  
  def track_activity!
    update_columns(
      last_seen_at: Time.current,
      sign_in_count: sign_in_count + 1
    )
  end
  
  private
  
  def normalize_email
    self.email = email&.downcase&.strip
  end
  
  def password_complexity
    return if password.blank?
    
    unless password.match?(PASSWORD_REQUIREMENTS)
      errors.add(:password, 'must include at least one uppercase letter, ' \
                          'one lowercase letter, one digit, and one special character')
    end
  end
  
  def create_personal_account
    Account.create_with_owner!(self, {
      name: "#{display_name}'s Account",
      account_type: :personal,
      max_users: 1
    })
  end
  
  def send_welcome_email
    UserMailer.welcome(self).deliver_later
  end
  
  def check_account_ownership
    owned_accounts.each do |account|
      if account.owners.count == 1
        errors.add(:base, "Cannot delete user who is the sole owner of #{account.name}")
        throw :abort
      end
    end
  end
end
```

#### Enhanced AccountMembership Model
```ruby
# app/models/account_membership.rb
class AccountMembership < ApplicationRecord
  # Constants
  ROLE_PERMISSIONS = {
    owner: %w[all],
    admin: %w[manage_users manage_settings view_all edit_all delete_all],
    member: %w[view_all edit_own create delete_own],
    viewer: %w[view_all]
  }.freeze
  
  # Enums
  enum role: {
    owner: 0,
    admin: 1,
    member: 2,
    viewer: 3
  }
  
  # Associations
  belongs_to :account
  belongs_to :user
  belongs_to :invited_by, class_name: 'User', optional: true
  
  # Validations
  validates :account_id, uniqueness: { 
    scope: :user_id,
    message: 'User is already a member of this account'
  }
  
  validates :role, presence: true
  
  validate :at_least_one_owner, if: :role_changed?
  validate :cannot_demote_last_owner
  validate :invitation_token_uniqueness, if: :invitation_token?
  
  # Callbacks
  before_validation :set_joined_at, on: :create
  after_create :send_invitation_email, if: :invitation_token?
  after_update :handle_role_change, if: :saved_change_to_role?
  after_update :handle_activation_change, if: :saved_change_to_active?
  
  # Scopes
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :pending, -> { where.not(invitation_token: nil, invitation_accepted_at: nil) }
  scope :accepted, -> { where.not(invitation_accepted_at: nil) }
  scope :by_role, ->(role) { where(role: role) }
  scope :with_access, -> { active.where(role: [:owner, :admin, :member]) }
  
  # Store accessors for permissions
  store_accessor :permissions, :custom_permissions, :restrictions
  
  # Class methods
  def self.invite!(account:, email:, role:, invited_by:)
    user = User.find_or_initialize_by(email: email)
    
    transaction do
      user.save!(validate: false) if user.new_record?
      
      create!(
        account: account,
        user: user,
        role: role,
        invited_by: invited_by,
        invitation_token: SecureRandom.urlsafe_base64,
        invitation_sent_at: Time.current,
        active: false
      )
    end
  end
  
  # Instance methods
  def accept_invitation!(accepting_user = nil)
    if accepting_user && accepting_user.id != user_id
      errors.add(:base, 'Invitation can only be accepted by the invited user')
      return false
    end
    
    update!(
      invitation_accepted_at: Time.current,
      invitation_token: nil,
      active: true,
      joined_at: Time.current
    )
  end
  
  def resend_invitation!
    return false if invitation_accepted_at.present?
    
    update!(
      invitation_token: SecureRandom.urlsafe_base64,
      invitation_sent_at: Time.current
    )
    
    send_invitation_email
    true
  end
  
  def has_role?(check_role)
    return true if role == 'owner'
    
    role_hierarchy = %w[viewer member admin owner]
    role_hierarchy.index(role.to_s) >= role_hierarchy.index(check_role.to_s)
  end
  
  def can?(permission)
    return true if role == 'owner'
    
    base_permissions = ROLE_PERMISSIONS[role.to_sym] || []
    all_permissions = base_permissions + (custom_permissions || [])
    
    all_permissions.include?('all') || all_permissions.include?(permission.to_s)
  end
  
  def deactivate!
    update!(active: false)
  end
  
  def reactivate!
    update!(active: true)
  end
  
  private
  
  def set_joined_at
    self.joined_at ||= Time.current
  end
  
  def at_least_one_owner
    return unless account && role_changed? && role_was == 'owner'
    
    other_owners = account.account_memberships
                         .where.not(id: id)
                         .owner
                         .active
                         .count
    
    if other_owners.zero?
      errors.add(:role, 'Cannot change role: account must have at least one owner')
    end
  end
  
  def cannot_demote_last_owner
    return unless persisted? && role_changed? && role_was == 'owner'
    
    if account.owners.count == 1
      errors.add(:role, 'Cannot demote the last owner of the account')
    end
  end
  
  def invitation_token_uniqueness
    if AccountMembership.where.not(id: id)
                        .exists?(invitation_token: invitation_token)
      errors.add(:invitation_token, 'must be unique')
    end
  end
  
  def send_invitation_email
    AccountInvitationMailer.invite(self).deliver_later
  end
  
  def handle_role_change
    AuditLog.create!(
      account: account,
      user: Current.user,
      action: 'membership.role_changed',
      details: {
        user_id: user_id,
        from_role: role_before_last_save,
        to_role: role
      }
    )
  end
  
  def handle_activation_change
    if active?
      UserMailer.account_access_restored(user, account).deliver_later
    else
      UserMailer.account_access_revoked(user, account).deliver_later
    end
  end
end
```

### Performance Considerations

#### Query Optimization
```ruby
# app/models/concerns/account_query_optimizer.rb
module AccountQueryOptimizer
  extend ActiveSupport::Concern
  
  included do
    # Preload associations for common queries
    scope :with_member_counts, -> {
      left_joins(:account_memberships)
        .group('accounts.id')
        .select('accounts.*, 
                COUNT(CASE WHEN account_memberships.active = true THEN 1 END) as active_members_count,
                COUNT(account_memberships.id) as total_members_count')
    }
    
    scope :with_usage_stats, -> {
      left_joins(:expenses, :categories)
        .group('accounts.id')
        .select('accounts.*,
                COUNT(DISTINCT expenses.id) as expenses_count,
                COUNT(DISTINCT categories.id) as categories_count,
                COALESCE(SUM(expenses.amount_cents), 0) as total_spent_cents')
    }
  end
  
  class_methods do
    def find_with_members(id)
      includes(account_memberships: :user)
        .find(id)
    end
    
    def search(query)
      where('name ILIKE :query OR slug ILIKE :query', 
            query: "%#{sanitize_sql_like(query)}%")
    end
  end
end
```

### Security Implementation

#### Devise Security Configuration
```ruby
# config/initializers/devise.rb
Devise.setup do |config|
  # Security settings
  config.password_length = 8..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/
  config.timeout_in = 30.minutes
  config.lock_strategy = :failed_attempts
  config.unlock_strategy = :both # email and time
  config.maximum_attempts = 5
  config.unlock_in = 1.hour
  config.reset_password_within = 6.hours
  config.sign_in_after_reset_password = false
  config.paranoid = true # Don't reveal if email exists
  config.stretches = Rails.env.test? ? 1 : 12 # bcrypt cost
  config.pepper = Rails.application.credentials.devise_pepper
  config.send_email_changed_notification = true
  config.send_password_change_notification = true
  
  # Session security
  config.rememberable_options = { 
    secure: Rails.env.production?,
    httponly: true
  }
  
  # Enable CSRF protection
  config.clean_up_csrf_token_on_authentication = true
end
```

### Testing Strategy

#### Comprehensive Model Tests
```ruby
# spec/models/account_spec.rb
RSpec.describe Account, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_least(2).is_at_most(100) }
    it { should validate_uniqueness_of(:slug).case_insensitive }
    it { should validate_numericality_of(:max_users).is_greater_than(0) }
    
    describe 'max_users_within_type_limit' do
      it 'enforces limits based on account type' do
        account = build(:account, account_type: :personal, max_users: 2)
        expect(account).not_to be_valid
        expect(account.errors[:max_users]).to include('cannot exceed 1 for personal accounts')
      end
    end
  end
  
  describe 'callbacks' do
    describe 'slug generation' do
      it 'generates unique slug from name' do
        account1 = create(:account, name: 'Test Account')
        account2 = create(:account, name: 'Test Account')
        
        expect(account1.slug).to eq('test-account')
        expect(account2.slug).to eq('test-account-1')
      end
    end
    
    describe 'default categories creation' do
      it 'creates default categories after account creation' do
        account = create(:account)
        expect(account.categories.count).to eq(8)
        expect(account.categories.pluck(:name)).to include('Groceries', 'Dining')
      end
    end
  end
  
  describe 'associations' do
    it { should have_many(:account_memberships).dependent(:destroy) }
    it { should have_many(:users).through(:account_memberships) }
    it { should have_many(:expenses).dependent(:destroy) }
    it { should have_many(:categories).dependent(:destroy) }
  end
  
  describe '#create_with_owner!' do
    let(:user) { create(:user) }
    
    it 'creates account with owner membership' do
      account = Account.create_with_owner!(user, name: 'New Account')
      
      expect(account).to be_persisted
      expect(account.owners).to include(user)
      expect(account.account_memberships.first.role).to eq('owner')
    end
    
    it 'rolls back on failure' do
      expect {
        Account.create_with_owner!(user, name: nil)
      }.to raise_error(ActiveRecord::RecordInvalid)
      
      expect(Account.count).to eq(0)
      expect(AccountMembership.count).to eq(0)
    end
  end
  
  describe 'suspension' do
    let(:account) { create(:account) }
    
    it 'suspends and reactivates account' do
      account.suspend!('Payment failed')
      
      expect(account).to be_suspended
      expect(account.suspension_reason).to eq('Payment failed')
      
      account.reactivate!
      
      expect(account).not_to be_suspended
      expect(account.suspension_reason).to be_nil
    end
  end
end
```

### Risk Mitigation

#### Data Migration Safety
```ruby
# lib/tasks/user_account_migration.rake
namespace :migration do
  desc 'Safely migrate existing data to multi-tenant structure'
  task migrate_to_multi_tenant: :environment do
    ActiveRecord::Base.transaction do
      # Create personal accounts for existing users
      User.find_each do |user|
        next if user.accounts.any?
        
        Account.create_with_owner!(user, {
          name: "#{user.display_name}'s Account",
          account_type: :personal
        })
        
        puts "Created account for user #{user.email}"
      end
      
      # Migrate orphaned expenses
      Expense.where(account_id: nil).find_each do |expense|
        if expense.email_account&.user
          account = expense.email_account.user.accounts.first
          expense.update!(account: account) if account
        end
      end
    end
  end
end
```

## Definition of Done
- [ ] All models created with full test coverage (>95%)
- [ ] Devise authentication working end-to-end
- [ ] Model callbacks tested and verified
- [ ] Database constraints match model validations
- [ ] Performance benchmarks established (<50ms for common queries)
- [ ] Indexes verified with EXPLAIN ANALYZE
- [ ] Security audit passed (password complexity, session management)
- [ ] At least one owner enforcement working
- [ ] Account switching functionality implemented
- [ ] Invitation system tested
- [ ] Soft delete working correctly
- [ ] Documentation for model relationships created
- [ ] Seed data updated to create sample accounts/users
- [ ] Code reviewed and approved
- [ ] Load testing completed (100+ concurrent users)