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