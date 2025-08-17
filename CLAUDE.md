# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

This is a Ruby on Rails 8.0.2 application. Key commands:

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

A pre-commit hook has been configured to automatically run tests, RuboCop linting, Brakeman security scanning, and Rails Best Practices before allowing commits. This ensures code quality and security standards are maintained.

## Architecture

This is a fresh Rails 8 application with the following stack:

**Backend:**
- Rails 8.0.2 with PostgreSQL database
- Solid Cache, Queue, and Cable for performance
- Puma web server

**Frontend:**
- Turbo and Stimulus (Hotwire) for SPA-like behavior
- Tailwind CSS for styling
- Import maps for JavaScript modules
- Propshaft asset pipeline

**Testing:**
- RSpec configured alongside default Rails test framework
- Capybara and Selenium for system testing

**Key Directories:**
- `app/models/` - ActiveRecord models (currently only ApplicationRecord base class)
- `app/controllers/` - Rails controllers (currently only ApplicationController base class)
- `app/views/` - ERB templates
- `app/javascript/` - Stimulus controllers and JavaScript
- `app/services/` - Domain-organized service objects:
  - `email/` - Email processing and synchronization services
  - `categorization/` - Expense categorization engines and utilities
  - `infrastructure/` - Cross-cutting concerns (monitoring, broadcasting)
- `config/` - Application configuration
- `db/` - Database schema and migrations
- `spec/` - RSpec tests (mirroring service organization)

**Service Architecture:**
The application follows Domain-Driven Design principles with services organized by business domain:

- **Email Domain** (`Services::Email::*`)
  - `ProcessingService` - Email fetching, parsing, and expense extraction
  - `SyncService` - Synchronization orchestration and conflict management

- **Categorization Domain** (`Services::Categorization::*`)
  - `BulkCategorizationService` - Bulk operations for expense categorization
  - Multiple sub-modules for pattern matching, caching, and ML-based categorization

- **Infrastructure Domain** (`Services::Infrastructure::*`)
  - `BroadcastService` - WebSocket broadcasting with reliability features
  - `MonitoringService` - System health, metrics, and error tracking

**Current State:**
- Fully functional expense tracking Rails application with comprehensive models and services
- Core models: Category, EmailAccount, Expense, ParsingRule, ApiToken (all with full validation and associations)
- Domain-organized service layer with clear separation of concerns
- API endpoints for iPhone Shortcuts integration via webhooks controller
- Database seeded with Costa Rican bank data and expense categories
- Background job processing with Solid Queue
- Comprehensive test suite: 236 examples with 100% pass rate (148 model tests, 88 service tests)
- Production-ready security with encrypted credentials and API token authentication

**Epic 3 Implementation Complete:**
- **Task 3.2**: View toggle system (compact/expanded) with persistent user preferences
- **Task 3.3**: Inline quick actions (95/100 QA score) with keyboard navigation
- **Task 3.4**: Batch selection system with full accessibility compliance and keyboard shortcuts
- **Enhanced Dashboard**: Improved UX with DashboardExpenseFilterService extending ExpenseFilterService
- **Performance Optimized**: <50ms query performance with strategic database indexing
- **Financial Confidence Design**: Complete color palette implementation across all components

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