# Frontend Guidelines

## Color Palette (MANDATORY)

ALL frontend code MUST use the Financial Confidence color palette. See [Style Guide](style-guide.md) for complete color reference.

**Critical Rules:**
- NEVER use `blue-*`, `gray-*`, `red-*`, `yellow-*`, or `green-*` classes
- ALWAYS use `teal-*`, `slate-*`, `rose-*`, `amber-*`, and `emerald-*` instead
- Primary actions: `bg-teal-700 hover:bg-teal-800`
- Cards: `bg-white rounded-xl shadow-sm border border-slate-200`

## Stimulus Controllers

- Keep Stimulus controllers focused and single-purpose
- Use data attributes for configuration
- Follow Stimulus naming conventions
- Prefer composition over inheritance for complex behaviors

## Tailwind CSS

- Use Tailwind utility classes for styling
- Avoid custom CSS unless absolutely necessary
- Use responsive design utilities
- Keep class lists organized and readable
- MUST use Financial Confidence palette colors (teal, amber, rose, emerald, slate)
- Component standards:
  - Cards: `rounded-xl` not `rounded-lg`
  - Shadows: `shadow-sm` for subtle depth
  - Borders: Always include `border border-slate-200` on cards
  - Buttons: Always include `shadow-sm` on primary buttons

## HTML/ERB

- Use semantic HTML elements
- Keep ERB templates clean and readable
- Extract complex logic into helper methods
- Use partials for reusable components
- Follow accessibility best practices (alt tags, ARIA labels, etc.)

## JavaScript

- Use modern ES6+ syntax
- Keep JavaScript modules small and focused
- Handle errors appropriately
- Use async/await for asynchronous operations
- Minimize global variables and side effects

## Performance

- Optimize images and assets
- Use lazy loading for non-critical content
- Minimize HTTP requests
- Use Rails asset pipeline efficiently
- Consider caching strategies for static content