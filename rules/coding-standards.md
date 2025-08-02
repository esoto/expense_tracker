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