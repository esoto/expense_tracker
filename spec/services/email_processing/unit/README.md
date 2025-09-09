# EmailProcessing::Parser Unit Test Suite

This directory contains comprehensive unit tests for the `EmailProcessing::Parser` class, organized into 5 specialized test files to ensure 100% coverage.

## Test File Structure

### 1. parser_core_spec.rb
**Purpose:** Tests core parsing logic and validation
- Initialization and setup
- Main `parse_expense` method flow
- Validation methods (`valid_parsed_data?`)
- Finding parsing rules
- Email content processing and caching
- Error accumulation
- Standard email processing (quoted-printable decoding)
- Private method testing

### 2. parser_edge_cases_spec.rb
**Purpose:** Tests edge cases, error scenarios, and large email handling
- Large email processing (>50KB threshold)
- StringIO resource management for memory efficiency
- Processing only first 100 lines for large emails
- Encoding errors and invalid UTF-8 handling
- Malformed quoted-printable sequences
- Nil and empty value handling
- Boundary conditions (size thresholds)
- Special characters and control characters
- Exception handling in service integrations

### 3. parser_duplicate_detection_spec.rb
**Purpose:** Tests duplicate expense detection logic
- Date range calculation (±1 day)
- Matching criteria (email_account, amount, transaction_date)
- Month/year boundary handling
- Leap year considerations
- Status transitions for duplicates
- Database query optimization
- Complex duplicate scenarios
- Error handling during duplicate checks

### 4. parser_integration_spec.rb
**Purpose:** Tests service integrations
- StrategyFactory integration
  - Strategy creation and configuration
  - Different strategy types (Regex, ML, Custom)
  - Error handling
- CurrencyDetectorService integration
  - Currency detection from email content
  - Currency application to expenses
  - Multi-currency support (USD, EUR, CRC)
- CategoryGuesserService integration
  - Automatic categorization
  - Category matching logic
  - Default category handling
- Full parsing flow with all services

### 5. parser_performance_spec.rb
**Purpose:** Tests performance and memory management
- Memory management with StringIO
- Content caching mechanisms
- Performance characteristics and thresholds
  - MAX_EMAIL_SIZE (50KB)
  - TRUNCATE_SIZE (10KB)
- Line processing limits (100 lines max)
- Resource lifecycle management
- Encoding operation efficiency
- Optimization patterns (lazy evaluation, early returns)
- Scalability considerations
- Performance monitoring points

## Key Testing Patterns

### Mocking Strategy
All tests use `instance_double` for complete isolation:
```ruby
let(:email_account) { instance_double(EmailAccount, email: 'test@example.com', bank_name: 'TEST_BANK') }
let(:parsing_rule) { instance_double(ParsingRule, id: 1, bank_name: 'TEST_BANK') }
```

### Test Tags
All tests are tagged with `unit: true` for easy filtering:
```ruby
RSpec.describe EmailProcessing::Parser, type: :service, unit: true do
```

### Private Method Testing
Private methods are tested using `send`:
```ruby
parser.send(:email_content)
parser.send(:find_duplicate_expense, parsed_data)
```

## Running the Tests

```bash
# Run all parser unit tests
bundle exec rspec spec/services/email_processing/unit/parser_*_spec.rb --tag unit

# Run individual test files
bundle exec rspec spec/services/email_processing/unit/parser_core_spec.rb
bundle exec rspec spec/services/email_processing/unit/parser_edge_cases_spec.rb
bundle exec rspec spec/services/email_processing/unit/parser_duplicate_detection_spec.rb
bundle exec rspec spec/services/email_processing/unit/parser_integration_spec.rb
bundle exec rspec spec/services/email_processing/unit/parser_performance_spec.rb
```

## Coverage Goals

These tests aim for 100% coverage of:
- All public methods
- All private methods
- All error paths
- All edge cases
- All integration points
- Performance-critical code paths

## Key Features Tested

1. **Email Size Handling**
   - Standard emails (<50KB)
   - Large emails (>50KB)
   - Line limiting (100 lines max)

2. **Encoding Support**
   - Quoted-printable decoding
   - UTF-8 handling
   - Invalid byte sequence scrubbing

3. **Duplicate Detection**
   - ±1 day date range
   - Same account, amount matching
   - Status updates for duplicates

4. **Service Integration**
   - Strategy pattern implementation
   - Currency detection
   - Category guessing

5. **Performance**
   - Memory-efficient large email processing
   - Content caching
   - Resource cleanup