# Commit

Create well-formatted commits with conventional commit messages and emojis following project standards.

## Usage:
- `/commit` - Standard commit with pre-commit checks
- `/commit --no-verify` - Skip pre-commit checks
- `/commit "custom message"` - Use custom commit message

## Process:
1. Check git status for staged and unstaged changes
2. Run git diff to see what will be committed
3. Run git log to understand recent commit message style
4. If no staged changes, analyze and stage appropriate files
5. Run pre-commit checks (lint, test, build) unless --no-verify
6. Analyze changes to determine appropriate commit type and scope
7. Generate conventional commit message with emoji
8. Create commit with standardized format including Claude signature
9. Verify commit was created successfully

## Commit Types & Emojis:
- ✨ feat: New features
- 🐛 fix: Bug fixes  
- 📝 docs: Documentation changes
- ♻️ refactor: Code restructuring without changing functionality
- 🎨 style: Code formatting, missing semicolons, etc.
- ⚡️ perf: Performance improvements
- ✅ test: Adding or correcting tests
- 🧑‍💻 chore: Tooling, configuration, maintenance
- 🚧 wip: Work in progress
- 🔥 remove: Removing code or files
- 🚑 hotfix: Critical fixes
- 🔒 security: Security improvements

## Message Format:
```
[emoji] type(scope): description

Optional body explaining why these changes were made.

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Examples:
- `✨ feat(auth): add OAuth2 integration for user authentication`
- `🐛 fix(api): resolve timeout issues in webhook endpoints`
- `♻️ refactor(services): extract dashboard analytics to DashboardService`
- `✅ test(controllers): add comprehensive controller test coverage`

## Process Steps:
1. **Check Status**: Review staged/unstaged changes with `git status`
2. **Review Changes**: Examine diffs to understand what's being committed
3. **Stage Files**: Add appropriate files if nothing is staged
4. **Pre-commit Checks**: Run linting and tests (unless --no-verify)
5. **Determine Type**: Analyze changes to pick appropriate commit type
6. **Generate Message**: Create descriptive commit message
7. **Execute Commit**: Use heredoc format for proper message formatting
8. **Verify Success**: Confirm commit was created

## Notes:
- Commits should be atomic and focused on single concerns
- Use imperative mood ("Add feature" not "Added feature")
- Include scope when changes affect specific area (controller, service, model)
- Split unrelated changes into separate commits
- Reference issues/PRs when relevant
- Always include Claude signature unless user specifically requests otherwise