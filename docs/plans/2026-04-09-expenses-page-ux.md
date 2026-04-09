# Expenses Page UX Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix bugs and apply Data-Dense Dashboard UX pattern to expenses index page

**Architecture:** Modify existing ERB views + Stimulus controllers. No new models or services. Changes to: index.html.erb, _expense_item.html.erb, filter-persistence-controller.js, batch-selection-controller.js, new date-preset-controller.js, new kebab-menu-controller.js. Mockup reference: `docs/mockups/expenses-index-v2.html`

**Tech Stack:** Rails 8.1, Hotwire (Turbo + Stimulus), Tailwind CSS, Import Maps

**Linear Tickets:** PER-426 (bugs), PER-427 (date presets), PER-428 (kebab menu), PER-429 (table styling)

---

### Task 1: Fix bulk actions toolbar visibility (PER-426 part 1)

**Files:**
- Modify: `app/views/expenses/index.html.erb:20` — remove `overflow-x-hidden` from container
- Modify: `app/views/expenses/index.html.erb:251` — change toolbar z-index from `z-40` to `z-50`
- Test: `spec/requests/per419_expenses_index_standalone_spec.rb` — add assertion for toolbar visibility

**Step 1: Write failing test**

Add to `spec/requests/per419_expenses_index_standalone_spec.rb`:
```ruby
it "bulk selection toolbar has z-50 for visibility" do
  get expenses_path
  expect(response.body).to include("z-50")
  expect(response.body).not_to include("overflow-x-hidden")
end
```

**Step 2: Run test — verify fail**
Run: `bundle exec rspec spec/requests/per419_expenses_index_standalone_spec.rb -e "z-50"`

**Step 3: Fix the CSS**
- Line 20: change `overflow-x-hidden` to remove it (or use `overflow-x-clip` which doesn't create stacking context)
- Line 251: change `z-40` to `z-50`

**Step 4: Run test — verify pass**

**Step 5: Commit**
```
fix(expenses): fix bulk toolbar z-index and remove overflow-hidden clipping
```

---

### Task 2: Fix clear filters button (PER-426 part 2)

**Files:**
- Modify: `app/views/expenses/index.html.erb:104` — clear filters link
- Modify: `app/javascript/controllers/filter_persistence_controller.js` — add clearStorage method
- Test: request spec

**Step 1: Investigate the clear button**
The clear button is `link_to expenses_path` (line 104) which navigates to `/expenses` without params. BUT `filter-persistence-controller` auto-restores from sessionStorage, so the cleared URL gets re-populated. The fix: add `data-action="click->filter-persistence#clearStorage"` to the clear button, and implement `clearStorage()` in the controller.

**Step 2: Write failing test**
```ruby
it "clear filters link includes data-action for filter persistence clear" do
  get expenses_path
  expect(response.body).to include("filter-persistence#clearStorage")
end
```

**Step 3: Implement fix**
- Add `data: { action: "click->filter-persistence#clearStorage" }` to the clear link
- Add `clearStorage()` method to filter_persistence_controller.js that clears sessionStorage keys

**Step 4: Verify pass + commit**

---

### Task 3: Add date filter quick presets (PER-427)

**Files:**
- Create: `app/javascript/controllers/date_preset_controller.js`
- Modify: `app/views/expenses/index.html.erb` — add preset pills above filter form
- Test: request spec

**Step 1: Create Stimulus controller**
```javascript
// date_preset_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preset", "startDate", "endDate", "customDates", "form"]

  select(event) {
    const period = event.currentTarget.dataset.period
    this.highlightPreset(event.currentTarget)

    if (period === "custom") {
      this.customDatesTarget.classList.remove("hidden")
      return
    }

    this.customDatesTarget.classList.add("hidden")
    const { start, end } = this.calculateDates(period)
    this.startDateTarget.value = start
    this.endDateTarget.value = end
    this.formTarget.requestSubmit()
  }

  calculateDates(period) {
    const today = new Date()
    let start, end
    switch (period) {
      case "this_month":
        start = new Date(today.getFullYear(), today.getMonth(), 1)
        end = new Date(today.getFullYear(), today.getMonth() + 1, 0)
        break
      case "last_month":
        start = new Date(today.getFullYear(), today.getMonth() - 1, 1)
        end = new Date(today.getFullYear(), today.getMonth(), 0)
        break
      case "this_quarter":
        const q = Math.floor(today.getMonth() / 3) * 3
        start = new Date(today.getFullYear(), q, 1)
        end = new Date(today.getFullYear(), q + 3, 0)
        break
      case "year_to_date":
        start = new Date(today.getFullYear(), 0, 1)
        end = today
        break
    }
    return {
      start: start.toISOString().split("T")[0],
      end: end.toISOString().split("T")[0]
    }
  }

  highlightPreset(active) {
    this.presetTargets.forEach(p => {
      p.className = "date-preset px-3 py-1.5 rounded-full text-xs font-medium bg-slate-100 text-slate-700 hover:bg-slate-200 cursor-pointer transition-colors"
    })
    active.className = "date-preset px-3 py-1.5 rounded-full text-xs font-medium bg-teal-700 text-white shadow-sm cursor-pointer"
  }
}
```

**Step 2: Add preset pills to index.html.erb** — insert above the filter form, inside the filter-persistence div

**Step 3: Write test + verify**

**Step 4: Commit**

---

### Task 4: Replace inline actions with kebab menu (PER-428)

**Files:**
- Create: `app/javascript/controllers/kebab_menu_controller.js`
- Create: `app/views/expenses/_kebab_menu.html.erb`
- Modify: `app/views/expenses/_expense_item.html.erb` — replace inline action buttons with kebab button
- Test: request spec

**Step 1: Create kebab Stimulus controller**
Simple controller: toggles a dropdown. Closes on click outside. Positions dropdown to avoid viewport overflow.

**Step 2: Create kebab menu partial**
Dropdown with: Categorizar, Marcar Procesado, Duplicar, Editar, separator, Eliminar (rose colored).

**Step 3: Replace inline actions in _expense_item.html.erb**
Remove the inline action buttons from the desktop grid columns. Add a kebab button as the last column. For mobile, replace the action drawer with the same kebab pattern.

**Step 4: Write tests + verify**

**Step 5: Commit**

---

### Task 5: Improve table density and styling (PER-429)

**Files:**
- Modify: `app/views/expenses/index.html.erb` — column headers
- Modify: `app/views/expenses/_expense_item.html.erb` — row padding, font sizes, stacked merchant+bank
- Test: visual verification via Playwright

**Step 1: Reduce row padding**
- Change `py-3` to `py-2` on rows
- Change data text to `text-[13px]`
- Add `tabular-nums` to amount columns

**Step 2: Stack merchant + bank in one column**
Show merchant name as primary, bank as secondary text below. Remove separate bank column.

**Step 3: Add sticky headers**
Add `sticky top-0 z-10` to column header row.

**Step 4: Simplify column grid**
New grid: `[40px_100px_1fr_160px_120px_100px_40px]` — checkbox, date, merchant+bank, category, amount, status, kebab

**Step 5: Write test + verify + commit**

---

### Task 6: Final integration test + cleanup

**Files:**
- Test: `spec/requests/expenses_index_ux_spec.rb`
- Run: full unit test suite

**Step 1: Write integration spec**
Cover: page renders, presets present, kebab menu markup, no inline action buttons, toolbar z-50, tabular-nums on amounts

**Step 2: Run full suite**
`bundle exec rspec --tag unit`

**Step 3: Commit + push + PR**
