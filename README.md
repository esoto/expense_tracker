# Expense Tracker

A comprehensive Rails 8.0.2 expense tracking application designed for Costa Rican banking systems with advanced categorization, real-time synchronization, and intelligent expense management.

## Features

### Core Functionality
- **Email-based Expense Extraction**: Automatic parsing of bank emails to extract expense data
- **Intelligent Categorization**: AI-powered expense categorization with learning capabilities
- **Real-time Dashboard**: Live expense tracking with performance-optimized queries (<50ms)
- **Multi-bank Support**: Compatible with Costa Rican banking systems
- **API Integration**: iPhone Shortcuts support via webhook endpoints

### User Experience (Epic 3 Implementation)
- **View Toggle System**: Compact/expanded expense views with persistent user preferences
- **Inline Quick Actions**: Rapid expense management with keyboard navigation support
- **Batch Selection System**: Bulk operations with full accessibility compliance
- **Financial Confidence Design**: Professional color palette optimized for financial applications
- **Keyboard Navigation**: Complete keyboard accessibility (WCAG 2.1 AA compliant)

### Technical Features
- **Performance Optimized**: Strategic database indexing with <50ms query targets
- **Real-time Updates**: WebSocket broadcasting for live data synchronization
- **Background Processing**: Solid Queue for reliable job processing
- **Security Hardened**: Encrypted credentials, API token authentication, pre-commit security scanning
- **Comprehensive Testing**: 236+ test examples with 100% pass rate

## Architecture

### Technology Stack

**Backend:**
- Ruby on Rails 8.0.2
- PostgreSQL database with performance optimization
- Solid Cache, Queue, and Cable for high performance
- Puma web server

**Frontend:**
- Turbo and Stimulus (Hotwire) for SPA-like behavior
- Tailwind CSS with Financial Confidence color palette
- Import maps for JavaScript modules
- Propshaft asset pipeline

**Testing & Quality:**
- RSpec with Capybara for system testing
- RuboCop (rails-omakase) for code quality
- Brakeman for security analysis
- Rails Best Practices compliance
- Pre-commit hooks for quality gates

### Service Architecture

The application follows Domain-Driven Design principles:

```
app/services/
├── Email Domain
│   ├── ProcessingService - Email parsing and expense extraction
│   └── SyncService - Synchronization orchestration
├── Categorization Domain
│   ├── BulkCategorizationService - Bulk operations
│   └── CategoryGuesserService - AI-powered categorization
├── Infrastructure Domain
│   ├── BroadcastService - WebSocket reliability
│   └── MonitoringService - System health tracking
└── Dashboard Domain
    ├── DashboardService - Dashboard data aggregation
    └── DashboardExpenseFilterService - Enhanced filtering
```

### Database Design

**Core Models:**
- `Category` - Expense categorization with hierarchical support
- `EmailAccount` - Bank email account configuration
- `Expense` - Central expense records with full metadata
- `ParsingRule` - Configurable email parsing patterns
- `ApiToken` - Secure API authentication
- `Budget` - Budget tracking and monitoring

**Performance Features:**
- Strategic indexing for common query patterns
- Optimized foreign key relationships
- Efficient pagination and filtering
- Query performance monitoring

## Installation

### Prerequisites
- Ruby 3.2+
- PostgreSQL 14+
- Node.js 18+ (for asset compilation)
- Redis (for Solid Cache/Queue)

### Setup

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd expense_tracker
   ```

2. **Install dependencies:**
   ```bash
   bundle install
   npm install  # If using npm packages
   ```

3. **Database setup:**
   ```bash
   bin/rails db:setup
   # This creates database, loads schema, and seeds with Costa Rican data
   ```

4. **Configure credentials:**
   ```bash
   bin/rails credentials:edit
   # Add email account settings, API keys, etc.
   ```

5. **Start the application:**
   ```bash
   bin/dev
   # Runs Rails server, Tailwind watcher, and background jobs
   ```

## Development

### Development Commands

```bash
# Server
bin/rails server                # Start development server
bin/rails console              # Rails console

# Testing
bin/rails test                 # Run test suite (excludes system tests)
bin/rails test:system          # Run system tests
bin/rails test:all             # Run all tests
bundle exec rspec              # Run RSpec tests

# Database
bin/rails db:migrate           # Run migrations
bin/rails db:reset             # Reset database

# Assets
tailwindcss:build             # Build CSS
tailwindcss:watch             # Watch CSS changes

# Code Quality
bundle exec rubocop           # Ruby linting
bundle exec brakeman          # Security analysis
```

### Development Workflow

The project follows a multi-agent development pattern established during Epic 3:

1. **Implementation**: Senior architect implements core functionality
2. **Review**: Tech lead reviews and refines architecture
3. **Testing**: QA strategist ensures comprehensive testing
4. **Integration**: Final validation and performance testing

**Quality Gates:**
- A-grade code quality (90+ scores)
- 100% test coverage expectation
- <50ms database query performance
- WCAG 2.1 AA accessibility compliance
- Rails Best Practices adherence

### Code Standards

**Service Layer Pattern:**
```ruby
# Extend base services for specialized functionality
class DashboardExpenseFilterService < ExpenseFilterService
  # Add dashboard-specific logic while maintaining compatibility
end
```

**Stimulus Controller Standards:**
- Keyboard navigation support
- Accessibility attributes
- Performance optimization
- Error handling

**Testing Organization:**
```ruby
describe "Feature" do
  context "User Interaction" do
    it "handles primary flow" { }
  end
  
  context "Keyboard Navigation" do
    it "supports accessibility" { }
  end
  
  context "Performance" do
    it "meets requirements" { }
  end
end
```

## Configuration

### Email Accounts
Configure bank email accounts in Rails credentials:

```yaml
email_accounts:
  bac_san_jose:
    email: "notifications@baccredomatic.com"
    imap_server: "mail.baccredomatic.com"
    # ... other settings
```

### API Configuration
For iPhone Shortcuts integration:

```yaml
api:
  webhook_token: "secure_token_here"
  allowed_origins: ["shortcuts://"]
```

### Performance Configuration
Database and caching settings in `config/database.yml` and `config/cache.yml`.

## Testing

### Test Structure
- **Unit Tests**: Model validations, service logic
- **Integration Tests**: Cross-service communication
- **System Tests**: Full user workflows, accessibility
- **Performance Tests**: Query optimization, load testing

### Running Tests
```bash
# Quick test suite (excludes system tests)
bin/rails test

# Full test suite including system tests
bin/rails test:all

# RSpec tests (comprehensive suite)
bundle exec rspec

# Specific test categories
bundle exec rspec spec/models/
bundle exec rspec spec/services/
bundle exec rspec spec/system/
```

### Test Coverage
The project maintains comprehensive test coverage:
- 236+ test examples
- 100% pass rate target
- Model, service, and system test coverage
- Performance benchmarking tests

## Deployment

### Pre-deployment Checklist
- [ ] All tests passing
- [ ] Security scan clean (Brakeman)
- [ ] Code quality check (RuboCop)
- [ ] Performance benchmarks met
- [ ] Database migrations tested

### Production Configuration
- Configure Redis for Solid Cache/Queue
- Set up PostgreSQL with performance tuning
- Configure SSL certificates
- Set up monitoring and logging
- Configure backup strategies

#### Required Environment Variables
```bash
# Sidekiq Web UI Authentication (Required in production/staging)
SIDEKIQ_WEB_USERNAME=your_admin_username
SIDEKIQ_WEB_PASSWORD=your_secure_password

# These credentials are required to access the Sidekiq dashboard at /sidekiq
# No default credentials are provided for security reasons
```

## Contributing

### Development Rules
Follow the established patterns documented in `rules/`:
- [Coding Standards](rules/coding-standards.md)
- [Testing Guidelines](rules/testing.md)
- [Frontend Guidelines](rules/frontend.md)
- [Database Guidelines](rules/database.md)

### Quality Standards
- Use Financial Confidence color palette
- Follow accessibility requirements (WCAG 2.1 AA)
- Maintain test coverage
- Follow conventional commit messages
- Use pre-commit hooks for quality checks

### Git Worktrees & Parallel Development

When running multiple development sessions concurrently (e.g., multiple Claude Code instances), use **git worktrees with isolated test databases** to avoid PostgreSQL deadlocks:

```bash
# 1. Create a worktree
git worktree add .worktrees/my-feature -b my-feature main
cd .worktrees/my-feature

# 2. Edit config/database.yml — change test database name (use unique name per worktree)
# database: expense_tracker_test_<worktree-name><%= ENV['TEST_ENV_NUMBER'] %>

# 3. Set up the isolated test database
bundle install
RAILS_ENV=test bin/rails db:create
RAILS_ENV=test bin/rails db:schema:load

# 4. Work normally — no deadlocks with other sessions
```

> The `.worktrees/` directory is already gitignored. Don't commit the `database.yml` change.

### Branch Strategy
- Feature branches: `epic-N-feature-description`
- Comprehensive testing before PR
- Multi-agent review process

## Performance

### Database Performance
- Strategic indexing for common patterns
- Query optimization (<50ms targets)
- Efficient pagination and filtering
- Performance monitoring

### Frontend Performance
- Optimized Tailwind CSS compilation
- Efficient Stimulus controllers
- Image optimization and lazy loading
- JavaScript performance budgets

### Background Jobs
- Solid Queue for reliable processing
- Job monitoring and retry logic
- Performance metrics and alerting

## Security

### Security Features
- Encrypted Rails credentials
- API token authentication
- Pre-commit security scanning (Brakeman)
- Input validation and sanitization
- SQL injection prevention
- Sidekiq Web UI requires explicit credentials (no defaults)
- Timing-safe credential comparison

### Security Monitoring
- Regular security audits
- Dependency vulnerability scanning
- Security-focused code reviews
- Production security monitoring

## License

[Add your license information here]

## Support

For development questions or issues:
1. Check the established development patterns in `CLAUDE.md`
2. Review the comprehensive rule documentation in `rules/`
3. Examine existing test patterns for guidance
4. Follow the multi-agent development workflow for complex features

---

**Built with Rails 8.0.2 • Designed for Costa Rican Banking Systems • Optimized for Performance & Accessibility**