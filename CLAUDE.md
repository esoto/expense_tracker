# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

This is a Ruby on Rails 8.1.2 application. Key commands:

- `bin/rails server` or `bin/rails s` - Start the Rails development server
- `bin/rails console` or `bin/rails c` - Start the Rails console
- `bin/rails test` - Run the test suite (excludes system tests)
- `bin/rails test:system` - Run system tests
- `bin/rails test:all` - Run all tests including system tests
- `bundle exec rspec` - Run RSpec tests (RSpec is configured)
- `bin/rails db:migrate` - Run database migrations
- `bin/rails db:setup` - Create database, load schema, and seed data
- `bin/rails db:reset` - Drop and recreate database from migrations
- `tailwindcss:build` - Build Tailwind CSS
- `tailwindcss:watch` - Watch and build Tailwind CSS on file changes
- `bundle exec rubocop` - Run Ruby linter (rubocop-rails-omakase)
- `bundle exec brakeman` - Run security analysis

## Git Pre-commit Hook

A pre-commit hook is available to automatically run code quality checks and security scanning before allowing commits. This ensures code quality and security standards are maintained.

**Setup:** Run `./bin/setup-git-hooks` after cloning the repository to install the hooks.

The hook runs:
1. **RuboCop** - Ensures code style compliance
2. **Brakeman** - Security vulnerability scanner
3. **RSpec unit tests** - Runs only tests tagged with `:unit` (uses `bundle exec rspec --tag unit`)

To bypass the hook (not recommended): `git commit --no-verify`

## Git Worktrees & Test Database Isolation

When multiple Claude Code sessions (or other processes) run tests concurrently against the same PostgreSQL test database, **deadlock errors** (`PG::TRDeadlockDetected`) will occur. This is caused by competing `AccessExclusiveLock` and `RowExclusiveLock` operations on shared tables.

**Solution:** Use git worktrees with a separate test database per worktree.

### Setup Steps

1. **Create a worktree:**
   ```bash
   git worktree add .worktrees/<branch-name> -b <branch-name> main
   cd .worktrees/<branch-name>
   ```

2. **Modify `config/database.yml` in the worktree** — change the test database name:
   ```yaml
   test:
     <<: *default
     database: expense_tracker_test_worktree<%= ENV['TEST_ENV_NUMBER'] %>
   ```

3. **Create and load the isolated test database:**
   ```bash
   bundle install
   RAILS_ENV=test bin/rails db:create
   RAILS_ENV=test bin/rails db:schema:load
   ```

4. **Work normally in this worktree** — pre-commit hooks will use the isolated database with zero deadlocks.

> **Note:** The `.worktrees/` directory is already in `.gitignore`. Do NOT commit the `database.yml` change — it's local to the worktree only.

## Architecture

This is a mature Rails 8.1.2 expense tracking application with the following stack:

**Backend:**
- Rails 8.1.2 with PostgreSQL database (pg_trgm and unaccent extensions)
- Solid Cache, Queue, and Cable for performance
- Puma web server

**Frontend:**
- Turbo and Stimulus (Hotwire) for SPA-like behavior — 48 Stimulus controllers
- Tailwind CSS for styling (Financial Confidence color palette)
- Import maps for JavaScript modules
- Propshaft asset pipeline
- Chart.js for data visualization

**Testing:**
- RSpec with 8,000+ unit tests (all tagged `:unit`, 100% pass rate)
- Capybara and Selenium for system testing
- FactoryBot, WebMock, VCR, DatabaseCleaner
- Separate configurations: `.rspec-unit`, `.rspec-integration`, `.rspec-performance`

**Key Directories:**
- `app/models/` - 26 ActiveRecord models (Expense, Category, Budget, AdminUser, CategorizationPattern, etc.)
- `app/controllers/` - 38 controllers across main, admin, analytics, and API namespaces
- `app/views/` - ERB templates with Turbo Frame integration
- `app/javascript/` - 48 Stimulus controllers and utility modules
- `app/services/` - 86 domain-organized service objects across 12+ domains
- `app/jobs/` - 15 background jobs (email processing, categorization, metrics, broadcast recovery)
- `config/` - Application configuration
- `db/` - 46 migrations, comprehensive strategic indexing
- `spec/` - 350+ test files mirroring service organization
- `docs/` - Plans, roadmaps, and implementation documentation

**Service Architecture:**
The application follows Domain-Driven Design principles with services organized by business domain:

- **Email Domain** (`Services::Email::*`)
  - `ProcessingService` - Email fetching, parsing, and expense extraction
  - `SyncService` - Synchronization orchestration and conflict management
  - `EncodingService` - Email encoding/decoding

- **Categorization Domain** (`Services::Categorization::*`) — 18+ services
  - `Engine` / `Orchestrator` - Core categorization logic and workflow coordination
  - `PatternLearner` / `ConfidenceCalculator` - ML-powered pattern learning and confidence scoring
  - `PatternCache` - High-performance LRU pattern caching
  - `BulkCategorizationService` - Bulk operations for expense categorization
  - `Matchers/*` - Multiple pattern matching implementations
  - `Monitoring/*` - 10+ monitoring and metrics services

- **Broadcast Domain** (root-level services)
  - `CoreBroadcastService` - Base WebSocket broadcasting
  - `BroadcastReliabilityService` - Delivery guarantees and retry orchestration
  - `BroadcastAnalytics` / `BroadcastErrorHandler`

- **Bulk Operations Domain** (`BulkOperations::*`)
  - `BaseService`, `CategorizationService`, `DeletionService`, `StatusUpdateService`

- **Analytics Domain**
  - `DashboardExporter`, `PatternPerformanceAnalyzer`
  - `DashboardExpenseFilterService` extending `ExpenseFilterService`

- **Infrastructure** — Cross-cutting concerns
  - `ErrorTrackingService`, `MetricsCalculator`, `QueueMonitor`
  - `SyncMetricsCollector`

**Current State:**
- Fully functional expense tracking application with 26 models, 86 services, 48 Stimulus controllers
- Core models: Category, EmailAccount, Expense, Budget, AdminUser, CategorizationPattern, CompositePattern, CanonicalMerchant, and more
- ML-powered categorization with pattern learning, confidence scoring, and user feedback loops
- Real-time sync with conflict detection/resolution and undo support
- Full API layer for iPhone Shortcuts integration (webhooks, categories, patterns, health)
- Admin panel with pattern management, testing, import/export, and analytics
- Database seeded with Costa Rican bank data and expense categories
- Background job processing with Solid Queue
- 8,000+ unit tests with 100% pass rate
- Production-ready security with encrypted credentials, API token authentication, and CSP headers
- Spanish localization (i18n) in progress across all interfaces

**Completed Epics:**
- **Epic 1**: Core expense tracking (models, controllers, views, API)
- **Epic 2**: Advanced categorization (ML patterns, bulk operations, analytics)
- **Epic 3**: UX/Dashboard enhancements (view toggle, inline actions, batch selection, keyboard navigation)

**QA Remediation (In Progress):**
- Phase 0 (Emergency Fixes): Complete — 7/7 tasks merged
- Phase 1 (Critical Performance): Complete — 7/8 tasks merged
- Phase 2 (Security Hardening): Complete — 8/8 tasks merged
- Phase 3 (UX & Design): Complete — 31 tickets closed
- Phase 4 (Performance Polish): In progress — 6 tasks
- Phase 5 (Cleanup & Polish): Pending — 5 tasks

## Development Rules

The following rules and guidelines should be followed when working on this project:

- [Coding Standards](rules/coding-standards.md) - Ruby/Rails conventions, code organization, error handling, and security practices
- [Testing Guidelines](rules/testing.md) - Test structure, RSpec conventions, coverage goals, and test data management
- [Frontend Guidelines](rules/frontend.md) - Stimulus controllers, Tailwind CSS, HTML/ERB, JavaScript, and performance considerations
- [Database Guidelines](rules/database.md) - Migration best practices, model design, ActiveRecord usage, performance, and data management
- [Code Analysis](rules/code-analysis.md) - Advanced code analysis with multiple inspection options, quality evaluation, and performance analysis
- [Commit](rules/commit.md) - Well-formatted commits with conventional commit messages and emojis
- [Fast Commit](rules/commit-fast.md) - Quick commit process with automatic message selection
- [Check](rules/check.md) - Comprehensive code quality and security checks for Rails projects
- [Five Whys Analysis](rules/five.md) - Root cause analysis technique to deeply understand problems
- [Context Prime](rules/context-prime.md) - Prime Claude with comprehensive Rails project understanding
- [Create Command](rules/create-command.md) - Guide for creating new custom Claude commands with proper structure
- [Continuous Improvement](rules/continuous-improvement.md) - Systematic approach for improving Claude Rails development rules
- [Style Guide](rules/style-guide.md) - UI/UX style guidelines and design system reference

## Design System - Financial Confidence Color Palette

This application uses the "Financial Confidence" color palette. ALL new features and updates MUST follow this color scheme:

### Primary Colors
- **Primary**: `teal-700` (#0F766E) - Main actions, navigation, primary buttons
- **Primary Light**: `teal-50` - Active states, selected items
- **Primary Medium**: `teal-100` - Icon backgrounds, badges

### Secondary Colors  
- **Secondary**: `amber-600` (#D97706) - Warnings, important highlights
- **Secondary Light**: `amber-50` - Warning backgrounds
- **Secondary Medium**: `amber-100` - Special highlights

### Accent Colors
- **Accent**: `rose-400` (#FB7185) - Critical actions, errors requiring attention
- **Accent Light**: `rose-50` - Error backgrounds
- **Accent Medium**: `rose-100` - Soft error states

### Status Colors
- **Success**: `emerald-500`, `emerald-600` - Positive states, confirmations
- **Warning**: `amber-600`, `amber-700` - Caution states
- **Error**: `rose-600`, `rose-700` - Error states
- **Info**: `slate-600`, `slate-700` - Neutral information

### Neutral Colors
- **Text Primary**: `slate-900` - Main text
- **Text Secondary**: `slate-600` - Secondary text
- **Text Muted**: `slate-500` - Disabled/muted text
- **Background**: `slate-50` - Page backgrounds
- **Card Background**: `white` - Card backgrounds
- **Borders**: `slate-200` - All borders

### UI Components Style
- **Cards**: `bg-white rounded-xl shadow-sm border border-slate-200`
- **Primary Button**: `bg-teal-700 hover:bg-teal-800 text-white rounded-lg shadow-sm`
- **Secondary Button**: `bg-slate-200 hover:bg-slate-300 text-slate-700 rounded-lg`
- **Input Focus**: `focus:border-teal-500 focus:ring-teal-500`
- **Success Messages**: `bg-emerald-50 border-emerald-200 text-emerald-700`
- **Error Messages**: `bg-rose-50 border-rose-200 text-rose-700`

NEVER use the default blue colors (`blue-600`, `blue-500`, etc.) - always use the palette colors above.

## Established Development Practices

Based on Epic 3 implementation, the following development patterns and practices have been established:

### Multi-Agent Development Pattern

Epic 3 established a rigorous multi-agent development workflow:

1. **rails-senior-architect**: Initial implementation with comprehensive technical design
2. **tech-lead-architect**: Code review and architectural refinement 
3. **qa-test-strategist**: Comprehensive testing and quality assurance
4. **Final Review**: Integration testing and performance validation

**Quality Gates:**
- A-grade code quality standards (90+ scores)
- 100% test coverage expectation
- Performance requirements (<50ms queries)
- Accessibility compliance (WCAG 2.1 AA)
- Rails Best Practices adherence

### Epic Implementation Structure

**Phase 1: Database Foundation**
- Performance optimization with strategic indexing
- Query analysis and optimization
- Service architecture establishment

**Phase 2: Core Functionality**
- UI/UX implementation following Financial Confidence design
- Stimulus controller development for JavaScript interactions
- Service layer extension (e.g., DashboardExpenseFilterService)

**Phase 3: Enhancement & Testing**
- Accessibility improvements and keyboard navigation
- Comprehensive system testing
- Performance benchmarking and validation

### Technical Architecture Patterns

**Service Layer Extension:**
```ruby
# Established pattern: Extend base services for specialized functionality
class DashboardExpenseFilterService < ExpenseFilterService
  # Add dashboard-specific filtering logic
  # Maintain base service compatibility
  # Enhance with dashboard-specific optimizations
end
```

**Stimulus Controller Standards:**
- Keyboard navigation support (arrow keys, escape, enter)
- Accessibility attributes (aria-labels, roles)
- Performance optimization (debouncing, efficient DOM updates)
- Error handling and graceful degradation

**Database Optimization:**
- Strategic indexing for common query patterns
- Performance monitoring and measurement
- Query optimization with <50ms targets

### Testing Standards

**System Test Coverage:**
- User interaction flows
- Keyboard navigation scenarios
- Accessibility compliance testing
- Performance benchmarking
- Error handling and edge cases

**Test Organization:**
```ruby
# Follow this structure for system tests
describe "Feature Name" do
  context "User Interaction" do
    it "handles primary user flow" do
      # Test implementation
    end
  end
  
  context "Keyboard Navigation" do
    it "supports standard keyboard shortcuts" do
      # Test accessibility
    end
  end
  
  context "Performance" do
    it "meets response time requirements" do
      # Test performance
    end
  end
end
```

### Code Quality Standards

**Mandatory Checks:**
- RuboCop compliance (rubocop-rails-omakase)
- Brakeman security scanning
- Rails Best Practices validation
- Test coverage maintenance

**Performance Requirements:**
- Database queries: <50ms
- Page load times: <200ms initial, <100ms subsequent
- JavaScript interactions: <16ms for 60fps

### Accessibility Requirements

**WCAG 2.1 AA Compliance:**
- Keyboard navigation for all interactive elements
- ARIA labels and roles for screen readers
- Color contrast ratios meeting standards
- Focus management and visual indicators

**Implementation Pattern:**
```erb
<!-- Established accessible component pattern -->
<button 
  type="button"
  class="<%= financial_confidence_button_classes %>"
  aria-label="<%= descriptive_action_label %>"
  data-action="<%= stimulus_controller_action %>"
  <%= keyboard_navigation_attributes %>
>
  <%= button_content %>
</button>
```

### Development Workflow Standards

**Branch Strategy:**
- Feature branches from main: `epic-N-feature-description`
- Comprehensive testing before PR creation
- Multi-agent review process

**Commit Standards:**
- Conventional commit messages with emojis
- Atomic commits with single responsibility
- Pre-commit hook validation

**Documentation Requirements:**
- Update CLAUDE.md for architectural changes
- Maintain comprehensive test documentation
- Document performance optimizations and benchmarks

These practices ensure consistent, high-quality development that maintains the standards established during Epic 3 implementation.