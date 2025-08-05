# Parsing Improvements - Expense Tracker

## Current State Analysis
- **Total expenses**: 23
- **With merchant_name**: 18 (78%)
- **Without merchant_name**: 5 (22%)

## Root Cause: BAC Merchant Pattern Issue

### Current Failing Pattern
```ruby
merchant_pattern: "(?:Comercio)[: ]*([A-Z0-9 .]+?)(?: *Ciudad| *Fecha| *VISA| *MASTER)"
```

### Problem
The pattern expects "Ciudad" but actual BAC emails contain "Ciudad y país":
- **Failing case**: `Comercio: GITHUB, INC. Ciudad y país: +18774484820`
- **Working case**: `Comercio: VICORTECH Ciudad y país: CARTAGO, Costa Rica`

## Implementation Tasks

### 1. Fix BAC Merchant Pattern (CRITICAL)

**File**: `db/seeds.rb` (line 93)

**Updated Pattern**:
```ruby
merchant_pattern: "(?:Comercio)[: ]*([A-Z0-9 .,&-]+?)(?:\\s*Ciudad|\\s*Fecha|\\s*VISA|\\s*MASTER|$)"
```

**Changes**:
- Added `,`, `&`, `-` to character set
- Added `\\s*` for variable spacing
- Added `|$` as end-of-line anchor

### 2. Implement Fallback Merchant Extraction

**File**: `app/services/email_processing/strategies/regex.rb`

**Add this method**:
```ruby
def extract_merchant_with_fallback(email_content)
  # Primary pattern attempt
  if parsing_rule.merchant_pattern.present?
    if merchant_match = email_content.match(Regexp.new(parsing_rule.merchant_pattern, Regexp::IGNORECASE))
      return clean_merchant_name(merchant_match[1] || merchant_match[0])
    end
  end
  
  # Fallback patterns for common formats
  fallback_patterns = [
    /(?:Comercio|Merchant|Establecimiento)[:\s]+([^\n\r]+?)(?:\s+Ciudad|\s+Fecha|\s+VISA|\s+MASTER|\n|$)/i,
    /(?:Comercio|Merchant)[:\s]+([^\n\r]{5,50})/i
  ]
  
  fallback_patterns.each do |pattern|
    if match = email_content.match(pattern)
      return clean_merchant_name(match[1])
    end
  end
  
  nil
end

private

def clean_merchant_name(name)
  return nil if name.blank?
  
  name.strip
      .gsub(/\s+/, ' ')                    # Normalize whitespace
      .gsub(/[^\w\s.,&-]/, '')            # Remove unwanted characters
      .gsub(/\s*(ciudad|fecha|visa|master).*$/i, '') # Remove trailing keywords
      .strip
end
```

### 3. Add Pattern Testing Utility

**File**: `app/models/parsing_rule.rb`

**Add this method**:
```ruby
def test_merchant_extraction(email_content)
  return { success: false, error: "No merchant pattern" } if merchant_pattern.blank?
  
  begin
    match = email_content.match(Regexp.new(merchant_pattern, Regexp::IGNORECASE))
    if match
      {
        success: true,
        extracted: match[1] || match[0],
        full_match: match[0],
        position: match.begin(0)
      }
    else
      { success: false, error: "Pattern did not match" }
    end
  rescue RegexpError => e
    { success: false, error: "Invalid regex: #{e.message}" }
  end
end
```

### 4. Enhanced Test Coverage

**File**: `spec/services/email_processing/strategies/regex_parsing_strategy_spec.rb`

**Add these tests**:
```ruby
context 'BAC real-world email formats' do
  let(:bac_parsing_rule) do
    create(:parsing_rule, :bac)
  end
  
  let(:bac_strategy) { described_class.new(bac_parsing_rule) }

  it 'extracts merchant from GitHub email format' do
    email_content = <<~EMAIL
      Comercio: GITHUB, INC. Ciudad y país: +18774484820, Pais no Definido
      Fecha: Jul 29, 2025, 11:40
      Monto: USD 10.00
    EMAIL
    
    result = bac_strategy.parse_email(email_content)
    expect(result[:merchant_name]).to eq('GITHUB, INC.')
  end

  it 'extracts merchant from local business format' do
    email_content = <<~EMAIL
      Comercio: VICORTECH Ciudad y país: CARTAGO, Costa Rica
      Fecha: Jul 28, 2025, 21:15
      Monto: CRC 9,900.00
    EMAIL
    
    result = bac_strategy.parse_email(email_content)
    expect(result[:merchant_name]).to eq('VICORTECH')
  end

  it 'handles merchants with special characters' do
    email_content = <<~EMAIL
      Comercio: SMITH & SONS CO. Ciudad y país: SAN JOSE, Costa Rica
      Fecha: Jul 28, 2025, 21:15
      Monto: CRC 15,000.00
    EMAIL
    
    result = bac_strategy.parse_email(email_content)
    expect(result[:merchant_name]).to eq('SMITH & SONS CO.')
  end
end
```

### 5. Parsing Validation Rake Task

**File**: `lib/tasks/parsing_validation.rake`

```ruby
namespace :parsing do
  desc "Validate parsing rules against existing expense data"
  task validate: :environment do
    ParsingRule.active.each do |rule|
      puts "\n=== Testing #{rule.bank_name} patterns ==="
      
      expenses = Expense.joins(:email_account)
                       .where(email_accounts: { bank_name: rule.bank_name })
                       .where.not(merchant_name: nil)
                       .limit(10)
      
      success_count = 0
      fail_count = 0
      
      expenses.each do |expense|
        if expense.raw_email_content.present?
          test_result = rule.test_merchant_extraction(expense.raw_email_content)
          if test_result[:success]
            success_count += 1
            puts "✓ #{expense.id}: #{test_result[:extracted]}"
          else
            fail_count += 1
            puts "✗ #{expense.id}: #{test_result[:error]}"
          end
        end
      end
      
      puts "\nSummary: #{success_count} successful, #{fail_count} failed"
    end
  end

  desc "Test specific parsing rule pattern"
  task :test_pattern, [:bank_name, :pattern] => :environment do |t, args|
    rule = ParsingRule.find_by(bank_name: args[:bank_name])
    if rule
      test_content = <<~EMAIL
        Comercio: GITHUB, INC. Ciudad y país: +18774484820, Pais no Definido
        Fecha: Jul 29, 2025, 11:40
        Monto: USD 10.00
      EMAIL
      
      result = rule.test_merchant_extraction(test_content)
      puts "Test Result: #{result.inspect}"
    else
      puts "No parsing rule found for bank: #{args[:bank_name]}"
    end
  end
end
```

## Implementation Priority

1. **CRITICAL**: Fix BAC merchant pattern in seeds.rb
2. **HIGH**: Run migration to update existing parsing rules
3. **HIGH**: Add comprehensive test coverage
4. **MEDIUM**: Implement fallback extraction methods
5. **MEDIUM**: Add pattern validation utilities
6. **LOW**: Create pattern testing tools

## Expected Impact

- Reduce nil merchant_name cases from 22% to <5%
- Improve pattern reliability across different email formats
- Better debugging and testing capabilities
- Future-proof against email format changes

## Testing Commands

After implementation:
```bash
# Test parsing validation
bundle exec rake parsing:validate

# Test specific pattern
bundle exec rake parsing:test_pattern[BAC,"(?:Comercio)[: ]*([A-Z0-9 .,&-]+?)(?:\\s*Ciudad|\\s*Fecha|\\s*VISA|\\s*MASTER|$)"]

# Run updated specs
bundle exec rspec spec/services/email_processing/strategies/
```