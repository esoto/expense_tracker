# Issue: Accessibility Compliance Violations

## Description
The queue visualization component lacks proper accessibility attributes, making it unusable for users with screen readers or other assistive technologies. This violates WCAG 2.1 AA standards and could prevent users with disabilities from accessing critical queue management functionality.

## Severity
**CRITICAL** - Blocks production deployment for compliance reasons

## Impact
- Users with screen readers cannot navigate the queue interface
- Interactive elements are not properly announced
- Dynamic status updates are not communicated to assistive technologies
- May violate legal accessibility requirements (ADA compliance)

## Steps to Reproduce
1. Open the expense dashboard with queue visualization
2. Use a screen reader (e.g., VoiceOver on Mac, JAWS on Windows)
3. Navigate to the queue visualization section
4. Attempt to interact with pause/resume buttons
5. Try to understand the current queue status

**Expected Result**: All elements should be properly announced with descriptive labels
**Actual Result**: Screen reader provides minimal or confusing information

## Files Affected
- `/Users/soto/development/vs-agent/expense_tracker/app/views/sync_sessions/_queue_visualization.html.erb` (Primary)
- `/Users/soto/development/vs-agent/expense_tracker/app/javascript/controllers/queue_monitor_controller.js` (Secondary - for dynamic updates)

## Code Examples
**Current problematic code:**
```erb
<button data-action="click->queue-monitor#pause"
        data-queue-monitor-target="pauseButton"
        class="px-3 py-1 bg-amber-600 text-white rounded-lg text-sm hover:bg-amber-700">
  Pausar
</button>

<div class="text-2xl font-bold text-slate-600" 
     data-queue-monitor-target="pendingCount">0</div>
```

**What's missing:**
- No `aria-label` or `aria-describedby` attributes
- No `role` attributes for status indicators
- No `aria-live` regions for dynamic updates
- No semantic landmark roles

## Test Cases to Add
```gherkin
Feature: Queue Visualization Accessibility

Scenario: Screen reader navigation
  Given a user with VoiceOver enabled accesses the dashboard
  When they navigate to the queue visualization section
  Then all buttons should have descriptive accessible names
  And all status counters should be properly announced
  And dynamic updates should be announced automatically

Scenario: Keyboard navigation
  Given a user navigating only with keyboard
  When they tab through the queue controls
  Then all interactive elements should be focusable
  And focus indicators should be clearly visible
  And logical tab order should be maintained
```

## Acceptance Criteria for Fix
- [ ] All interactive buttons have proper `aria-label` attributes
- [ ] Status counters have `role="status"` or `role="img"` with alt text
- [ ] Dynamic updates use `aria-live="polite"` regions
- [ ] Complex elements have `aria-describedby` relationships
- [ ] Tab order is logical and complete
- [ ] Focus indicators meet WCAG contrast requirements
- [ ] Passes automated accessibility testing (axe-core)

---

## Technical Notes (from Tech-Lead-Architect)

### **Priority Assessment**
- **Priority**: P1 (Pre-Launch)
- **Rationale**: Critical for compliance but can be deployed with rapid follow-up if necessary
- **Risk**: Legal exposure under ADA, excludes users with disabilities

### **Recommended Technical Approach**
Implement a **progressive enhancement strategy** using Rails ViewComponents for consistent accessibility:

```ruby
# app/components/accessible_button_component.rb
class AccessibleButtonComponent < ViewComponent::Base
  def initialize(label:, action:, variant: :primary, **options)
    @label = label
    @action = action
    @variant = variant
    @options = options
  end

  private

  def button_classes
    base = "transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2"
    variant_classes = {
      primary: "bg-teal-700 hover:bg-teal-800 text-white focus:ring-teal-500",
      secondary: "bg-amber-600 hover:bg-amber-700 text-white focus:ring-amber-500"
    }
    "#{base} #{variant_classes[@variant]}"
  end
end
```

### **Architecture Impact**
- Introduce ViewComponent pattern for reusable accessible UI elements
- Minimal impact on existing Stimulus controllers
- Enhances maintainability through component abstraction

### **Implementation Complexity**
- **Effort**: 2-3 days
- **Risk**: Low - additive changes only
- **Dependencies**: None

### **Testing Strategy**
```ruby
# spec/system/accessibility_spec.rb
require 'axe-core-rspec'

RSpec.describe "Queue Visualization Accessibility", type: :system do
  it "meets WCAG 2.1 AA standards" do
    visit dashboard_path
    expect(page).to be_accessible.according_to :wcag2aa
  end

  it "announces dynamic updates to screen readers" do
    visit dashboard_path
    expect(page).to have_css('[aria-live="polite"]')
    # Trigger update and verify announcement
  end
end
```

### **Recommended Solution**
Adopt **ViewComponent pattern** for accessible UI components:
- Encapsulates accessibility requirements
- Provides consistent implementation
- Enables automated testing with axe-core
- Simplifies future accessibility updates