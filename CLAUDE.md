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
- Rails 8.0.2 with SQLite3 database
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
- `config/` - Application configuration
- `db/` - Database schema and migrations
- `spec/` - RSpec tests

**Current State:**
- Fully functional expense tracking Rails application with comprehensive models and services
- Core models: Category, EmailAccount, Expense, ParsingRule, ApiToken (all with full validation and associations)
- Service layer: EmailFetcher (IMAP integration), EmailParser (transaction parsing)
- API endpoints for iPhone Shortcuts integration via webhooks controller
- Database seeded with Costa Rican bank data and expense categories
- Background job processing with Solid Queue
- Comprehensive test suite: 236 examples with 100% pass rate (148 model tests, 88 service tests)
- Production-ready security with encrypted credentials and API token authentication

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