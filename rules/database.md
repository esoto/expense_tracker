# Database Guidelines

## Migration Best Practices

- Write reversible migrations when possible
- Use descriptive migration names
- Include proper indexes for foreign keys and frequently queried columns
- Test migrations in development before deploying
- Never edit existing migrations that have been deployed

## Model Design

- Use appropriate data types for columns
- Add database constraints for data integrity
- Use foreign key constraints for referential integrity
- Normalize data appropriately but avoid over-normalization
- Add proper validations at both model and database levels

## ActiveRecord

- Use scopes for commonly used queries
- Avoid N+1 queries by using includes/joins
- Use database-level defaults when appropriate
- Prefer database functions for complex calculations
- Use transactions for multi-step operations

## Performance

- Add indexes for frequently queried columns
- Use database-specific features when beneficial
- Monitor query performance with tools like bullet gem
- Use explain plans to optimize slow queries
- Consider database-level constraints for data integrity

## Data Management

- Use seeds.rb for essential data
- Create rake tasks for data migrations
- Backup database before major changes
- Use database-specific features appropriately
- Plan for data growth and scaling needs