# Compact View Mode Toggle Feature

## Overview
The Compact View Mode Toggle feature allows users to switch between compact and expanded views of the expense list for improved data density and customization based on user preference.

## Features

### View Modes

#### Compact Mode
- **Essential Fields Only**: Displays Date, Merchant, Category, and Amount
- **Hidden Elements**: 
  - Bank column
  - Status column  
  - Actions column
  - Expense descriptions
  - ML confidence badges (hidden on smaller screens)
- **Reduced Row Height**: Uses `h-12` class for more expenses per screen
- **Mobile Optimized**: Better information density on small screens

#### Expanded Mode (Default)
- **Full Information**: Shows all available columns and details
- **Visible Elements**:
  - All columns including Bank, Status, Actions
  - Expense descriptions below merchant names
  - ML confidence badges and indicators
  - Quick action buttons
- **Standard Row Height**: Uses `min-h-[4rem]` for comfortable viewing

### User Interface

#### Toggle Button
- Located in the expense list header
- Shows current mode with descriptive text
- Icons change based on active mode
- Visual feedback with color changes (teal-100 for compact, slate-100 for expanded)
- Accessible with proper ARIA labels

#### Keyboard Shortcuts
- **Ctrl/Cmd + Shift + V**: Toggle between view modes
- Tooltip on button shows keyboard shortcut

### Session Persistence
- View preference is saved in `sessionStorage`
- Persists across page reloads within the same browser session
- Automatically restored when returning to the expense list

### Responsive Behavior
- **Desktop**: Full toggle control with both modes available
- **Mobile (<768px)**: 
  - Automatically switches to compact mode
  - Optimized for small screen viewing
  - Hides less critical columns

## Technical Implementation

### Stimulus Controller
**Location**: `/app/javascript/controllers/view_toggle_controller.js`

Key methods:
- `connect()`: Loads saved preference and applies initial state
- `toggle()`: Switches between modes and saves preference
- `updateView()`: Applies the current mode styling
- `applyCompactView()`: Hides expanded elements, reduces row height
- `applyExpandedView()`: Shows all elements, restores full layout
- `handleKeydown()`: Processes keyboard shortcuts
- `handleResize()`: Auto-adjusts for mobile screens

### CSS Styling
**Location**: `/app/assets/stylesheets/components/view_toggle.css`

Key classes:
- `.compact-mode`: Applied to table in compact view
- `.expanded-mode`: Applied to table in expanded view
- Responsive styles for mobile optimization
- Smooth transitions between modes
- Print styles always show expanded view

### View Integration
**Location**: `/app/views/expenses/index.html.erb`

Data attributes used:
- `data-controller="view-toggle"`: Initializes the controller
- `data-view-toggle-target="toggleButton"`: Toggle button element
- `data-view-toggle-target="expandedColumns"`: Columns hidden in compact mode
- `data-view-toggle-target="table"`: Main table element

## Testing

### System Tests
**Location**: `/spec/system/expense_view_toggle_spec.rb`

Test coverage includes:
- Toggle button display and functionality
- Compact mode column hiding
- Expanded mode full display
- Session persistence
- Keyboard shortcuts
- Responsive behavior
- Accessibility features
- Performance with many expenses

### Running Tests
```bash
bundle exec rspec spec/system/expense_view_toggle_spec.rb
```

## Performance Considerations

- CSS-based hiding/showing for instant toggling
- No server requests required
- Efficient DOM manipulation through Stimulus targets
- Smooth transitions without layout shift
- Optimized for lists with 100+ expenses

## Accessibility

- Proper ARIA labels on toggle button
- Keyboard navigation maintained in both modes
- Focus management preserved
- Screen reader compatible
- High contrast mode support through Tailwind classes

## Browser Compatibility

- Modern browsers with ES6 support
- SessionStorage API support required
- Tested on:
  - Chrome 90+
  - Firefox 88+
  - Safari 14+
  - Edge 90+

## Future Enhancements

Potential improvements for future iterations:
1. User preference persistence in database
2. Customizable column selection
3. Density options (comfortable, compact, condensed)
4. Export view preferences
5. Column reordering capability