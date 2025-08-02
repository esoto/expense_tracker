# Check

Perform comprehensive code quality and security checks.

## Primary Task:
Run Rails-specific check commands and resolve any resulting errors.

## Important:
- DO NOT commit any code during this process
- DO NOT change version numbers
- Focus only on fixing issues identified by checks

## Common Checks Include:
1. **Linting**: Code style and syntax errors (`bundle exec rubocop`)
2. **Security Scan**: Vulnerability detection (`bundle exec brakeman`)
3. **Unit Tests**: Failing test cases (`bin/rails test` or `bundle exec rspec`)
4. **Database**: Migration and schema issues (`bin/rails db:migrate:status`)
5. **Asset Compilation**: Frontend build verification (`bin/rails assets:precompile`)
6. **Dependencies**: Gem security audit (`bundle audit`)

## Process:
1. Run the check commands in order
2. Analyze output for errors and warnings
3. Fix issues in priority order:
   - Security vulnerabilities first
   - Build-breaking errors
   - Test failures
   - Linting errors
   - Warnings
4. Re-run checks after each fix
5. Continue until all checks pass

## Rails Check Commands:
- **Ruby Linting**: `bundle exec rubocop`
- **Security Analysis**: `bundle exec brakeman`
- **Test Suite**: `bin/rails test:all` or `bundle exec rspec`
- **Database Status**: `bin/rails db:migrate:status`
- **Asset Compilation**: `bin/rails assets:precompile RAILS_ENV=production`
- **Gem Audit**: `bundle audit check --update`
- **Load Test**: `bin/rails runner "puts 'Rails loads successfully'"`