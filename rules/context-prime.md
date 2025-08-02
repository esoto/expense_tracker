# Context Prime

Prime Claude with comprehensive project understanding.

## Standard Context Loading:
1. Read README.md for project overview
2. Read CLAUDE.md for AI-specific instructions
3. List project files excluding ignored paths
4. Review key configuration files
5. Understand project structure and conventions

## Steps:
1. **Project Overview**:
   - Read README.md
   - Identify project type and purpose
   - Note key technologies and dependencies

2. **AI Guidelines**:
   - Read CLAUDE.md if present
   - Load project-specific AI instructions
   - Note coding standards and preferences

3. **Repository Structure**:
   - Run: `git ls-files | head -50` for initial structure
   - Identify main directories and their purposes
   - Note naming conventions

4. **Rails Configuration Review**:
   - Gemfile for dependencies and Ruby version
   - config/application.rb for Rails configuration
   - config/routes.rb for routing structure
   - config/database.yml for database setup
   - config/environments/ for environment-specific settings

5. **Development Context**:
   - Identify test framework (RSpec, Minitest)
   - Check db/schema.rb for current database structure
   - Review app/ directory structure (models, controllers, views)
   - Note asset pipeline configuration (JavaScript, CSS)
   - Check for custom rake tasks in lib/tasks/

## Rails-Specific Files to Review:
- **Gemfile**: Dependencies and Ruby version
- **config/routes.rb**: Application routing
- **db/schema.rb**: Database structure
- **app/models/**: ActiveRecord models
- **app/controllers/**: Application controllers
- **config/application.rb**: Rails application configuration
- **bin/** scripts: Development and deployment scripts

## Advanced Options:
- Load specific Rails subsystem context (ActiveRecord, ActionController, etc.)
- Focus on particular Rails version features
- Include recent migration history
- Load custom rake task definitions

## Output:
Establish clear understanding of:
- Rails application goals and constraints
- Database schema and relationships
- MVC architecture and patterns
- Development and testing workflow
- Deployment and environment configuration