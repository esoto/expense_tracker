# Coding Standards

## Ruby/Rails Conventions

- Follow Rails conventions and naming patterns
- Use descriptive method and variable names
- Keep methods short and focused (max 10-15 lines)
- Use `snake_case` for methods, variables, and file names
- Use `PascalCase` for classes and modules
- Prefer explicit over implicit returns
- Use `&&` and `||` for boolean logic, `and` and `or` for flow control

## Code Organization

- Keep controllers thin, move business logic to models or services
- Use concerns for shared functionality
- Group related methods together
- Add private methods at the bottom of classes
- Use meaningful commit messages following conventional commits format

## Service Class Patterns

### Service Class Structure
```ruby
# Good: Service class pattern
class EmailParser
  attr_reader :email_account, :email_data, :errors

  def initialize(email_account, email_data)
    @email_account = email_account
    @email_data = email_data
    @errors = []
  end

  def parse_expense
    return nil unless valid_preconditions?
    
    begin
      # Main business logic
      create_expense(parsed_data)
    rescue StandardError => e
      add_error("Error parsing email: #{e.message}")
      nil
    end
  end

  private

  def valid_preconditions?
    # Validation logic
  end

  def add_error(message)
    @errors << message
    Rails.logger.error "[#{self.class.name}] #{message}"
  end
end
```

### Service Class Guidelines
- Use dependency injection through initializer
- Maintain immutable service state after initialization  
- Provide clear public interface methods
- Include comprehensive error handling and logging
- Return meaningful results (objects, nil, or booleans)
- Use private methods for internal logic breakdown

## Error Handling

- Always handle potential errors gracefully
- Use Rails rescue_from for controller error handling
- Log errors appropriately for debugging
- Provide user-friendly error messages

## Security

- Never commit secrets, API keys, or passwords
- Use strong parameters in controllers
- Validate all user inputs
- Use Rails built-in security features (CSRF protection, etc.)
- Follow OWASP guidelines for web application security