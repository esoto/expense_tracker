# Testing Guidelines

## Test Structure

- Write tests before or alongside implementation (TDD/BDD approach)
- Use descriptive test names that explain the behavior being tested
- Follow the Arrange-Act-Assert pattern
- Keep tests isolated and independent
- Use factories (FactoryBot) instead of fixtures when possible

## RSpec Conventions

- Use `describe` for classes/methods, `context` for different scenarios
- Use `it` for specific behaviors
- Prefer `let` over instance variables for test data
- Use `subject` for the main object being tested
- Group related tests with shared examples when appropriate

## Test Coverage

- Aim for high test coverage but focus on critical paths
- Test edge cases and error conditions
- Test model validations and associations
- Test controller actions and authentication
- Include system tests for important user flows

## Test Data

- Use FactoryBot for creating test data
- Keep test data minimal and relevant
- Use traits for variations in factory data
- Avoid test data dependencies between tests

## Service Testing Patterns

### Testing Service Classes

Service classes require special testing approaches due to their business logic complexity:

```ruby
# Good: Service testing pattern
RSpec.describe EmailParser, type: :service do
  let(:parsing_rule) { create(:parsing_rule, :bac) }
  let(:email_account) { create(:email_account, :bac) }
  let(:email_data) { { body: sample_email_content } }
  let(:parser) { 
    parsing_rule  # Ensure dependencies exist first
    EmailParser.new(email_account, email_data) 
  }

  describe '#parse_expense' do
    context 'with valid data' do
      it 'creates expense successfully' do
        expect { parser.parse_expense }.to change(Expense, :count).by(1)
      end
    end

    context 'with invalid data' do
      it 'handles errors gracefully' do
        # Test error scenarios with realistic failure conditions
      end
    end
  end
end
```

### External Dependency Mocking

When testing services that interact with external APIs or complex libraries:

```ruby
# Good: Strategic mocking approach
describe EmailFetcher do
  let(:mock_imap) { instance_double(Net::IMAP) }
  
  before do
    allow(Net::IMAP).to receive(:new).and_return(mock_imap)
    allow(mock_imap).to receive(:login)
    allow(mock_imap).to receive(:select)
    allow(mock_imap).to receive(:logout)
    allow(mock_imap).to receive(:disconnect)
  end

  it 'handles IMAP connection properly' do
    # Test core functionality without complex IMAP internals
  end
end

# Avoid: Over-mocking complex internal structures
# Instead: Focus on behavior testing and integration scenarios
```

### Factory Dependency Management

Ensure proper factory dependency ordering in service tests:

```ruby
# Good: Explicit dependency creation
let(:parsing_rule) { create(:parsing_rule, :bac) }
let(:email_account) { create(:email_account, bank_name: parsing_rule.bank_name) }
let(:parser) { 
  parsing_rule  # Force creation before parser initialization
  EmailParser.new(email_account, email_data) 
}

# Good: Factory traits with realistic data
FactoryBot.define do
  factory :parsing_rule do
    trait :bac do
      bank_name { "BAC" }
      amount_pattern { '(?:Monto)[: ]*(?:USD|CRC)[: ]*([\\d,]+\\.\\d{2})' }
      # Patterns that match real email formats
    end
  end
end
```

## Mocking Best Practices

### When to Mock
- External APIs and services (IMAP, HTTP APIs)
- Time-dependent operations
- Complex dependencies that slow down tests
- Third-party gem interactions

### When NOT to Mock
- ActiveRecord models and associations
- Core Rails functionality
- Simple Ruby objects
- Business logic that should be tested end-to-end

### Mocking Strategies
```ruby
# Good: Mock at service boundaries
allow(ProcessEmailJob).to receive(:perform_later)

# Good: Mock external dependencies
allow(Net::IMAP).to receive(:new).and_return(mock_imap)

# Avoid: Mocking internal implementation details
# allow(expense).to receive(:save).and_return(false)
```

## Test Organization

### Test File Structure
```
spec/
├── models/           # Unit tests for ActiveRecord models
├── services/         # Unit tests for service classes  
├── controllers/      # Controller action tests
├── requests/         # Integration tests for API endpoints
├── system/          # End-to-end browser tests
├── factories/       # FactoryBot factory definitions
└── support/         # Shared test helpers and configurations
```

### Test Naming Conventions
```ruby
# Good: Descriptive test names
it 'creates expense when parsing valid BAC email'
it 'returns nil when email content lacks required amount'
it 'auto-categorizes restaurant expenses correctly'

# Avoid: Vague test names
it 'works'
it 'parses email'
it 'handles errors'
```