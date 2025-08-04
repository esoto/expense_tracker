# Style Guide - Financial Confidence Color Palette

This style guide enforces the Financial Confidence color palette across the entire application. All developers and AI assistants MUST follow these guidelines.

## Mandatory Color Usage

### ❌ NEVER Use These Colors
- `blue-*` classes (except when mapped to teal in Tailwind config)
- `gray-*` classes (always use `slate-*` instead)
- `red-*` classes (use `rose-*` instead)
- `yellow-*` classes (use `amber-*` instead)
- `green-*` classes (use `emerald-*` instead)

### ✅ ALWAYS Use These Colors

#### Primary Actions & Navigation
```erb
<!-- Primary buttons -->
<%= link_to "Action", path, class: "bg-teal-700 hover:bg-teal-800 text-white rounded-lg shadow-sm" %>

<!-- Navigation active state -->
<%= link_to "Page", path, class: "bg-teal-50 text-teal-700" %>

<!-- Primary icons -->
<div class="bg-teal-100 p-2 rounded-lg">
  <svg class="text-teal-700">
```

#### Secondary Elements & Warnings
```erb
<!-- Warning messages -->
<div class="bg-amber-50 border border-amber-200 text-amber-700 rounded-lg">

<!-- Warning icons -->
<div class="bg-amber-100 text-amber-600">
```

#### Critical Actions & Errors
```erb
<!-- Error messages -->
<div class="bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">

<!-- Delete buttons -->
<%= button_to "Delete", path, class: "bg-rose-600 hover:bg-rose-700 text-white" %>
```

#### Success States
```erb
<!-- Success messages -->
<div class="bg-emerald-50 border border-emerald-200 text-emerald-700 rounded-lg">

<!-- Success indicators -->
<span class="text-emerald-600">✓ Saved successfully</span>
```

## Component Templates

### Card Component
```erb
<div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
  <h3 class="text-lg font-semibold text-slate-900">Title</h3>
  <p class="text-sm text-slate-600">Description</p>
</div>
```

### Form Elements
```erb
<%= form_with model: @model do |f| %>
  <!-- Text input -->
  <%= f.text_field :field, 
      class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500" %>
  
  <!-- Primary submit -->
  <%= f.submit "Save", 
      class: "bg-teal-700 hover:bg-teal-800 text-white font-medium py-2 px-4 rounded-lg shadow-sm" %>
  
  <!-- Cancel link -->
  <%= link_to "Cancel", path, 
      class: "bg-slate-200 hover:bg-slate-300 text-slate-700 font-medium py-2 px-4 rounded-lg" %>
<% end %>
```

### Table Styling
```erb
<table class="min-w-full divide-y divide-slate-200">
  <thead class="bg-slate-50">
    <tr>
      <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
        Column
      </th>
    </tr>
  </thead>
  <tbody class="bg-white divide-y divide-slate-100">
    <tr class="hover:bg-slate-50">
      <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-900">
        Data
      </td>
    </tr>
  </tbody>
</table>
```

### Status Badges
```erb
<!-- Success -->
<span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-emerald-100 text-emerald-800">
  Active
</span>

<!-- Warning -->
<span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-amber-100 text-amber-800">
  Pending
</span>

<!-- Error -->
<span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-rose-100 text-rose-800">
  Failed
</span>

<!-- Neutral -->
<span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-slate-100 text-slate-800">
  Draft
</span>
```

## Color Usage by Context

### Navigation & Headers
- Background: `bg-white`
- Border: `border-slate-200`
- Logo container: `bg-teal-700`
- Active nav: `bg-teal-50 text-teal-700`
- Inactive nav: `text-slate-600 hover:text-teal-700`

### Forms & Inputs
- Input border: `border-slate-300`
- Input focus: `focus:border-teal-500 focus:ring-teal-500`
- Label text: `text-slate-700`
- Help text: `text-slate-500`
- Error text: `text-rose-600`

### Data Display
- Table header: `bg-slate-50`
- Table rows: `hover:bg-slate-50`
- Primary metrics: `text-slate-900`
- Secondary metrics: `text-slate-600`
- Positive change: `text-emerald-600`
- Negative change: `text-rose-600`

### Interactive Elements
- Primary button: `bg-teal-700 hover:bg-teal-800`
- Secondary button: `bg-slate-200 hover:bg-slate-300`
- Danger button: `bg-rose-600 hover:bg-rose-700`
- Link: `text-teal-600 hover:text-teal-800`

## Enforcement Rules

1. **Linting**: All views should be checked for color compliance
2. **Code Review**: Reject any PR using non-palette colors
3. **AI Assistance**: AI tools must only suggest palette colors
4. **Testing**: Visual regression tests should verify color usage
5. **Documentation**: All examples must use the correct colors

## Quick Reference

| Use Case | Class | Hex |
|----------|-------|-----|
| Primary Action | `bg-teal-700` | #0F766E |
| Secondary Action | `bg-amber-600` | #D97706 |
| Danger/Error | `bg-rose-600` | #E11D48 |
| Success | `bg-emerald-600` | #059669 |
| Text Primary | `text-slate-900` | #0F172A |
| Text Secondary | `text-slate-600` | #475569 |
| Border | `border-slate-200` | #E2E8F0 |
| Background | `bg-slate-50` | #F8FAFC |

## Migration Checklist

When updating existing views:
- [ ] Replace all `gray-*` with `slate-*`
- [ ] Replace all `blue-*` with `teal-*`
- [ ] Replace all `red-*` with `rose-*`
- [ ] Replace all `yellow-*` with `amber-*`
- [ ] Replace all `green-*` with `emerald-*`
- [ ] Update shadow classes to use `shadow-sm`
- [ ] Update rounded classes to use `rounded-lg` or `rounded-xl`
- [ ] Add borders to cards: `border border-slate-200`