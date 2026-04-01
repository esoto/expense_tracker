# PER-133: Mobile Table/Card Layout for Expenses — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the cramped mobile table view with a card-based layout that automatically switches at the `md:` (768px) breakpoint.

**Architecture:** Add a new `_expense_card.html.erb` partial rendered inside the existing `index.html.erb` via a responsive toggle — table hidden on mobile, cards hidden on desktop. A new `mobile_card_controller.js` Stimulus controller handles tap-to-expand actions and long-press batch selection. Filters collapse behind a toggle button on mobile. Category summary hides behind a toggle on mobile.

**Tech Stack:** Rails ERB, Stimulus.js, Tailwind CSS, existing Pagy pagination

**Design Decisions:**
- Breakpoint: `md:` (768px) — matches existing `view_toggle_controller.js`
- Card layout: Compact — merchant + amount top row, date + category second row, status badge only if not "processed"
- Actions: Tap card to expand action buttons (categorize, status, duplicate, delete)
- Batch selection: Long-press to enter selection mode, then tap to toggle
- Filters: Collapsible panel with "Filtrar" button, badge shows active filter count
- Category summary: Hidden by default on mobile, expandable via toggle
- Color palette: Financial Confidence (teal/amber/rose/emerald — never blue)

**Playwright Verification:** Screenshots can be taken at each stage using the Playwright MCP server to verify visual changes at both 375px and 1280px viewports.

---

## Task 1: Create the Expense Card Partial

**Files:**
- Create: `app/views/expenses/_expense_card.html.erb`
- Test: `spec/views/expenses/_expense_card.html.erb_spec.rb`

**Step 1: Write the failing view spec**

```ruby
# spec/views/expenses/_expense_card.html.erb_spec.rb
require "rails_helper"

RSpec.describe "expenses/_expense_card", type: :view, unit: true do
  let(:category) { create(:category, name: "Supermercado", color: "#0F766E") }
  let(:expense) { create(:expense, merchant_name: "Auto Mercado", amount: 15000, transaction_date: Date.new(2026, 3, 1), category: category, status: "processed", bank_name: "BAC") }

  before do
    render partial: "expenses/expense_card", locals: { expense: expense, categories: [category] }
  end

  it "renders the merchant name" do
    expect(rendered).to have_text("Auto Mercado")
  end

  it "renders the amount" do
    expect(rendered).to have_text("15.000")
  end

  it "renders the date" do
    expect(rendered).to have_text("01/03/2026")
  end

  it "renders the category badge" do
    expect(rendered).to have_text("Supermercado")
  end

  it "hides status badge when processed" do
    expect(rendered).not_to have_css("[data-testid='status-badge']")
  end

  context "when expense is pending" do
    let(:expense) { create(:expense, merchant_name: "Test", amount: 100, transaction_date: Date.today, category: category, status: "pending", bank_name: "BAC") }

    it "shows the status badge" do
      expect(rendered).to have_css("[data-testid='status-badge']")
    end
  end

  it "has tap-to-expand action target" do
    expect(rendered).to have_css("[data-mobile-card-target='card']")
  end

  it "has hidden actions container" do
    expect(rendered).to have_css("[data-mobile-card-target='actions'].hidden")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/views/expenses/_expense_card.html.erb_spec.rb -v`
Expected: FAIL — partial does not exist

**Step 3: Create the expense card partial**

```erb
<%# app/views/expenses/_expense_card.html.erb %>
<div class="bg-white border border-slate-200 rounded-xl p-4 shadow-sm"
     data-mobile-card-target="card"
     data-expense-id="<%= expense.id %>"
     data-action="click->mobile-card#toggleActions touchstart->mobile-card#touchStart touchend->mobile-card#touchEnd"
     role="article"
     aria-label="Gasto: <%= expense.merchant_name || 'Sin comercio' %> — ₡<%= number_with_delimiter(expense.amount.to_i) %>">

  <%# Top row: Merchant + Amount %>
  <div class="flex items-start justify-between mb-2">
    <div class="flex items-center gap-3 flex-1 min-w-0">
      <%# Batch selection checkbox (hidden until selection mode) %>
      <input type="checkbox"
             data-mobile-card-target="checkbox"
             data-expense-id="<%= expense.id %>"
             class="hidden h-5 w-5 text-teal-600 focus:ring-teal-500 border-slate-300 rounded flex-shrink-0"
             aria-label="Seleccionar gasto <%= expense.merchant_name %>">

      <%# Category color dot %>
      <% if expense.category %>
        <div class="w-8 h-8 rounded-full flex items-center justify-center text-white font-bold text-xs flex-shrink-0"
             style="background-color: <%= expense.category.color %>;">
          <%= expense.category.name.first.upcase %>
        </div>
      <% else %>
        <div class="w-8 h-8 rounded-full flex items-center justify-center bg-slate-400 text-white font-bold text-xs flex-shrink-0">?</div>
      <% end %>

      <%# Merchant name %>
      <div class="min-w-0 flex-1">
        <div class="font-medium text-slate-900 truncate">
          <%= expense.merchant_name.presence || content_tag(:span, "Sin comercio", class: "text-rose-600 italic") %>
        </div>
      </div>
    </div>

    <%# Amount %>
    <div class="text-right flex-shrink-0 ml-3">
      <span class="text-base font-bold text-slate-900">₡<%= number_with_delimiter(expense.amount.to_i) %></span>
    </div>
  </div>

  <%# Bottom row: Date + Category + Status %>
  <div class="flex items-center justify-between text-sm">
    <div class="flex items-center gap-2 text-slate-500">
      <span><%= expense.transaction_date.strftime("%d/%m/%Y") %></span>
      <span class="text-slate-300">·</span>
      <% if expense.category %>
        <span class="text-slate-600"><%= expense.category.name %></span>
      <% else %>
        <span class="text-slate-400">Sin categoría</span>
      <% end %>
    </div>

    <% if expense.status != "processed" %>
      <span data-testid="status-badge">
        <%= render "expenses/status_badge", expense: expense %>
      </span>
    <% end %>
  </div>

  <%# Expandable actions (hidden by default) %>
  <div class="hidden mt-3 pt-3 border-t border-slate-100"
       data-mobile-card-target="actions">
    <div class="flex items-center justify-between gap-2">
      <%# Quick categorize %>
      <button type="button"
              class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg bg-teal-50 text-teal-700 hover:bg-teal-100 transition-colors"
              data-action="click->mobile-card#openCategoryPicker"
              aria-label="Cambiar categoría">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"></path>
        </svg>
        Categoría
      </button>

      <%# Toggle status %>
      <button type="button"
              class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg bg-emerald-50 text-emerald-700 hover:bg-emerald-100 transition-colors"
              data-action="click->mobile-card#toggleStatus"
              aria-label="<%= expense.status == 'pending' ? 'Marcar como revisado' : 'Marcar como pendiente' %>">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
        Estado
      </button>

      <%# Edit %>
      <%= link_to edit_expense_path(expense),
                  class: "flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg bg-slate-100 text-slate-700 hover:bg-slate-200 transition-colors",
                  aria_label: "Editar gasto" do %>
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"></path>
        </svg>
        Editar
      <% end %>

      <%# Delete %>
      <button type="button"
              class="inline-flex items-center justify-center w-10 h-10 rounded-lg bg-rose-50 text-rose-600 hover:bg-rose-100 transition-colors"
              data-action="click->mobile-card#confirmDelete"
              aria-label="Eliminar gasto">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
        </svg>
      </button>
    </div>
  </div>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/views/expenses/_expense_card.html.erb_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/views/expenses/_expense_card.html.erb spec/views/expenses/_expense_card.html.erb_spec.rb
git commit -m "✨ feat(ui): add expense card partial for mobile layout

Closes PER-133 (partial)"
```

---

## Task 2: Create the Mobile Card Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/mobile_card_controller.js`
- Test: `spec/javascript/controllers/mobile_card_controller_spec.js` (manual verification via Playwright)

**Step 1: Write the Stimulus controller**

```javascript
// app/javascript/controllers/mobile_card_controller.js
import { Controller } from "@hotwired/stimulus"

/**
 * Mobile Card Controller
 * Handles tap-to-expand actions and long-press batch selection for mobile expense cards.
 */
export default class extends Controller {
  static targets = ["card", "actions", "checkbox"]

  static values = {
    expenseId: Number,
    expanded: { type: Boolean, default: false },
    selectionMode: { type: Boolean, default: false }
  }

  // Long press threshold in ms
  static LONG_PRESS_DURATION = 500

  connect() {
    this._longPressTimer = null
    this._touchMoved = false
  }

  disconnect() {
    this._clearLongPress()
  }

  // --- Tap to expand ---

  toggleActions(event) {
    // Don't toggle if in selection mode (tap = select)
    if (this.selectionModeValue) {
      this._toggleCheckbox()
      return
    }

    // Don't toggle if tapping an action button inside expanded area
    if (event.target.closest("[data-mobile-card-target='actions']")) return

    this.expandedValue = !this.expandedValue

    if (this.hasActionsTarget) {
      this.actionsTarget.classList.toggle("hidden", !this.expandedValue)
    }

    // Collapse other expanded cards
    if (this.expandedValue) {
      this._collapseOtherCards()
    }
  }

  // --- Long press for batch selection ---

  touchStart(event) {
    this._touchMoved = false
    this._longPressTimer = setTimeout(() => {
      this._enterSelectionMode()
    }, this.constructor.LONG_PRESS_DURATION)
  }

  touchEnd(event) {
    this._clearLongPress()
  }

  touchMove() {
    this._touchMoved = true
    this._clearLongPress()
  }

  // --- Actions ---

  openCategoryPicker(event) {
    event.stopPropagation()
    // Dispatch event for the inline-actions controller to handle
    this.dispatch("categorize", { detail: { expenseId: this.expenseIdValue } })
  }

  toggleStatus(event) {
    event.stopPropagation()
    this.dispatch("toggleStatus", { detail: { expenseId: this.expenseIdValue } })
  }

  confirmDelete(event) {
    event.stopPropagation()
    this.dispatch("delete", { detail: { expenseId: this.expenseIdValue } })
  }

  // --- Selection mode ---

  enterSelectionMode() {
    this.selectionModeValue = true
    // Show all checkboxes
    document.querySelectorAll("[data-mobile-card-target='checkbox']").forEach(cb => {
      cb.classList.remove("hidden")
    })
    // Dispatch global event
    this.dispatch("selectionModeChanged", { detail: { active: true } })
  }

  exitSelectionMode() {
    this.selectionModeValue = false
    document.querySelectorAll("[data-mobile-card-target='checkbox']").forEach(cb => {
      cb.classList.add("hidden")
      cb.checked = false
    })
    this.dispatch("selectionModeChanged", { detail: { active: false } })
  }

  // --- Private ---

  _enterSelectionMode() {
    this.enterSelectionMode()
    // Select the long-pressed card
    if (this.hasCheckboxTarget) {
      this.checkboxTarget.checked = true
    }
    // Haptic feedback if available
    if (navigator.vibrate) navigator.vibrate(50)
  }

  _toggleCheckbox() {
    if (this.hasCheckboxTarget) {
      this.checkboxTarget.checked = !this.checkboxTarget.checked
    }
  }

  _clearLongPress() {
    if (this._longPressTimer) {
      clearTimeout(this._longPressTimer)
      this._longPressTimer = null
    }
  }

  _collapseOtherCards() {
    const allCards = document.querySelectorAll("[data-controller='mobile-card']")
    allCards.forEach(card => {
      if (card !== this.element) {
        const actions = card.querySelector("[data-mobile-card-target='actions']")
        if (actions) actions.classList.add("hidden")
      }
    })
  }
}
```

**Step 2: Register the controller in the import map**

The controller should auto-register via Stimulus's `controllers/` convention. Verify:

Run: `grep -r "mobile.card" app/javascript/controllers/index.js` or check if eagerLoadControllersFrom is used.

**Step 3: Commit**

```bash
git add app/javascript/controllers/mobile_card_controller.js
git commit -m "✨ feat(ui): add mobile card Stimulus controller with tap-to-expand and long-press selection

Closes PER-133 (partial)"
```

---

## Task 3: Integrate Cards into Expenses Index (Responsive Toggle)

**Files:**
- Modify: `app/views/expenses/index.html.erb` (lines 98-253)
- Test: `spec/views/expenses/index.html.erb_spec.rb` (add mobile card rendering test)

**Step 1: Write the failing test**

```ruby
# Add to existing spec or create new
RSpec.describe "expenses/index", type: :view, unit: true do
  # ... existing setup ...

  it "renders the mobile card container" do
    expect(rendered).to have_css("#expense_cards.md\\:hidden")
  end

  it "hides the table on mobile" do
    expect(rendered).to have_css("#expense_list.hidden.md\\:block")
  end

  it "renders one card per expense" do
    expect(rendered).to have_css("[data-controller='mobile-card']", count: @expenses.count)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/views/expenses/index.html.erb_spec.rb -v`

**Step 3: Modify index.html.erb**

Add the mobile card list BEFORE the existing table div (line 98). Add responsive classes to toggle visibility:

After line 97 (end of category summary), add:

```erb
  <!-- Mobile Card View (visible < md:) -->
  <div id="expense_cards" class="md:hidden space-y-3">
    <div class="px-4 py-3 flex items-center justify-between">
      <h2 class="text-lg font-semibold text-slate-900">Lista de Gastos</h2>
      <span class="text-sm text-slate-500"><%= @expense_count %> gastos</span>
    </div>
    <div class="px-3 space-y-2">
      <% @expenses.each do |expense| %>
        <%= render "expense_card", expense: expense, categories: @categories %>
      <% end %>
    </div>

    <!-- Mobile Pagination -->
    <div class="px-4 py-4">
      <% if @pagy && @pagy.pages > 1 %>
        <%= pagy_financial_nav(@pagy) %>
        <p class="text-sm text-slate-600 text-center mt-2">
          Mostrando <%= @pagy.from %>-<%= @pagy.to %> de <%= number_with_delimiter(@pagy.count) %> gastos
        </p>
      <% end %>
    </div>
  </div>
```

Then modify the existing table div (line 99) to add `hidden md:block`:

```erb
  <!-- Expenses Table (visible >= md:) -->
  <div id="expense_list" class="hidden md:block bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden"
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/views/expenses/index.html.erb_spec.rb -v`

**Step 5: Take Playwright screenshots to verify**

```
# Desktop (1280px): should show table, hide cards
# Mobile (375px): should show cards, hide table
```

**Step 6: Commit**

```bash
git add app/views/expenses/index.html.erb spec/views/expenses/index.html.erb_spec.rb
git commit -m "✨ feat(ui): integrate responsive table/card toggle at md: breakpoint

Table visible on desktop (md:+), cards on mobile (<md:).
Closes PER-133 (partial)"
```

---

## Task 4: Collapsible Filters on Mobile

**Files:**
- Modify: `app/views/expenses/index.html.erb` (lines 53-80, filter section)
- Create: `app/javascript/controllers/collapsible_filter_controller.js`
- Test: `spec/views/expenses/index.html.erb_spec.rb` (add filter collapse test)

**Step 1: Write the failing test**

```ruby
it "renders collapsible filter toggle on mobile" do
  expect(rendered).to have_css("[data-controller='collapsible-filter']")
  expect(rendered).to have_button("Filtrar")
end

it "shows active filter count badge" do
  assign(:active_filter_count, 2)
  render
  expect(rendered).to have_css("[data-collapsible-filter-target='badge']", text: "2")
end
```

**Step 2: Create collapsible filter Stimulus controller**

```javascript
// app/javascript/controllers/collapsible_filter_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "badge", "toggleButton"]
  static values = { open: { type: Boolean, default: false } }

  toggle() {
    this.openValue = !this.openValue
    this.contentTarget.classList.toggle("hidden", !this.openValue)
  }
}
```

**Step 3: Wrap filter form with collapsible markup**

Replace the filter form section (lines 53-80) with:

```erb
    <!-- Filters -->
    <div data-controller="collapsible-filter">
      <%# Mobile: toggle button %>
      <div class="md:hidden flex items-center gap-2 mb-3">
        <button type="button"
                data-collapsible-filter-target="toggleButton"
                data-action="click->collapsible-filter#toggle"
                class="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg bg-slate-100 text-slate-700 hover:bg-slate-200">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z"></path>
          </svg>
          Filtrar
          <% active_count = [params[:category], params[:bank], params[:start_date], params[:end_date]].count(&:present?) %>
          <% if active_count > 0 %>
            <span data-collapsible-filter-target="badge"
                  class="inline-flex items-center justify-center w-5 h-5 text-xs font-bold text-white bg-teal-600 rounded-full">
              <%= active_count %>
            </span>
          <% end %>
        </button>
      </div>

      <%# Filter form (hidden on mobile by default, always visible on desktop) %>
      <div data-collapsible-filter-target="content" class="hidden md:block">
        <%= form_with url: expenses_path, method: :get,
                      class: "space-y-4 md:space-y-0 md:flex md:gap-4",
                      local: true,
                      data: { "filter-persistence-target": "filterForm" } do |form| %>
          <%# ... existing filter fields unchanged ... %>
        <% end %>
      </div>
    </div>
```

**Step 4: Run tests, verify, commit**

```bash
git add app/views/expenses/index.html.erb app/javascript/controllers/collapsible_filter_controller.js
git commit -m "✨ feat(ui): add collapsible filter panel on mobile with active count badge

Closes PER-133 (partial)"
```

---

## Task 5: Collapsible Category Summary on Mobile

**Files:**
- Modify: `app/views/expenses/index.html.erb` (lines 83-96, category summary section)

**Step 1: Write the failing test**

```ruby
it "renders category summary toggle on mobile" do
  expect(rendered).to have_button("Ver resumen")
end
```

**Step 2: Wrap category summary with collapsible markup**

Replace lines 83-96:

```erb
  <% if params[:category].blank? && @categories_summary.any? %>
  <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6"
       data-controller="collapsible-filter">
    <div class="flex items-center justify-between mb-4">
      <h2 class="text-lg font-semibold text-slate-900">Resumen por Categoría</h2>
      <button type="button"
              data-action="click->collapsible-filter#toggle"
              class="md:hidden text-sm text-teal-700 font-medium hover:text-teal-800">
        Ver resumen
      </button>
    </div>
    <div data-collapsible-filter-target="content" class="hidden md:block">
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <% @categories_summary.first(6).each do |category_name, amount| %>
        <div class="flex items-center justify-between p-3 bg-slate-50 rounded-lg">
          <span class="font-medium text-slate-700"><%= category_name %></span>
          <span class="font-bold text-slate-900">₡<%= number_with_delimiter(amount.to_i) %></span>
        </div>
        <% end %>
      </div>
    </div>
  </div>
  <% end %>
```

**Step 3: Run tests, verify, commit**

```bash
git add app/views/expenses/index.html.erb
git commit -m "✨ feat(ui): collapse category summary on mobile behind toggle

Closes PER-133 (partial)"
```

---

## Task 6: Mobile Card CSS Styles

**Files:**
- Create: `app/assets/stylesheets/components/mobile_cards.css`

**Step 1: Create mobile card styles**

```css
/* Mobile Card Styles for Expense List */

/* Card base */
[data-controller="mobile-card"] {
  @apply transition-all duration-200;
}

/* Selected card in batch mode */
[data-controller="mobile-card"].selected {
  @apply bg-teal-50 border-teal-300 ring-1 ring-teal-200;
}

/* Expanded card */
[data-controller="mobile-card"].expanded {
  @apply shadow-md border-teal-200;
}

/* Action buttons in expanded card */
[data-mobile-card-target="actions"] button {
  min-height: 44px; /* WCAG touch target */
}

/* Long press visual feedback */
[data-controller="mobile-card"]:active {
  @apply scale-[0.98] transition-transform duration-100;
}

/* Selection mode checkbox animation */
[data-mobile-card-target="checkbox"] {
  @apply transition-all duration-200;
}

/* Hide cards on desktop, show on mobile */
@media (min-width: 768px) {
  #expense_cards {
    display: none !important;
  }
}
```

**Step 2: Import in application stylesheet**

Add to the main CSS imports (check `app/assets/stylesheets/application.css` or equivalent).

**Step 3: Commit**

```bash
git add app/assets/stylesheets/components/mobile_cards.css
git commit -m "🎨 style(ui): add mobile card CSS with selection states and touch targets

Closes PER-133 (partial)"
```

---

## Task 7: RSpec Integration Tests

**Files:**
- Create: `spec/features/mobile_expense_cards_spec.rb`

**Step 1: Write comprehensive feature specs**

```ruby
# spec/features/mobile_expense_cards_spec.rb
require "rails_helper"

RSpec.describe "Mobile expense card layout", type: :feature, unit: true do
  let!(:category) { create(:category, name: "Supermercado", color: "#0F766E") }
  let!(:expense) { create(:expense, merchant_name: "Auto Mercado", amount: 25000, transaction_date: Date.today, category: category, status: "processed", bank_name: "BAC") }

  before { visit expenses_path }

  describe "responsive visibility" do
    it "renders both table and card containers" do
      expect(page).to have_css("#expense_list")
      expect(page).to have_css("#expense_cards")
    end

    it "card container has md:hidden class" do
      expect(page).to have_css("#expense_cards.md\\:hidden")
    end

    it "table container has hidden md:block classes" do
      expect(page).to have_css("#expense_list.hidden.md\\:block")
    end
  end

  describe "card content" do
    it "displays expense data in card format" do
      within("#expense_cards") do
        expect(page).to have_text("Auto Mercado")
        expect(page).to have_text("25.000")
        expect(page).to have_text(Date.today.strftime("%d/%m/%Y"))
        expect(page).to have_text("Supermercado")
      end
    end
  end

  describe "collapsible filters" do
    it "renders filter toggle button" do
      expect(page).to have_button("Filtrar")
    end
  end

  describe "collapsible category summary" do
    it "renders summary toggle button" do
      expect(page).to have_button("Ver resumen")
    end
  end
end
```

**Step 2: Run tests**

Run: `bundle exec rspec spec/features/mobile_expense_cards_spec.rb -v`

**Step 3: Commit**

```bash
git add spec/features/mobile_expense_cards_spec.rb
git commit -m "✅ test(ui): add integration tests for mobile expense card layout

Closes PER-133 (partial)"
```

---

## Task 8: Playwright Visual Verification & Final Commit

**Step 1: Take before/after screenshots**

Using Playwright MCP:
1. Navigate to `http://localhost:3000/expenses`
2. Resize to 375x812 (iPhone)
3. Take full-page screenshot: `expenses-mobile-after.png`
4. Resize to 1280x800 (desktop)
5. Take full-page screenshot: `expenses-desktop-after.png`
6. Compare with baseline screenshots taken at start

**Step 2: Manual verification checklist**
- [ ] Mobile (375px): Cards visible, table hidden
- [ ] Desktop (1280px): Table visible, cards hidden
- [ ] Card shows: merchant, amount, date, category
- [ ] Tap card: actions expand
- [ ] Filters: collapsed on mobile, visible on desktop
- [ ] Category summary: collapsed on mobile, visible on desktop
- [ ] Pagination works on mobile cards
- [ ] Touch targets meet 44px minimum

**Step 3: Final commit closing the ticket**

```bash
git commit -m "✨ feat(ui): mobile card layout for expenses (PER-133)

- Card-based layout on screens < 768px, table on desktop
- Tap to expand card actions (categorize, status, edit, delete)
- Long-press to enter batch selection mode
- Collapsible filter panel with active filter count badge
- Collapsible category summary on mobile
- WCAG 2.1 AA touch targets (44px minimum)
- Financial Confidence color palette throughout

Closes PER-133"
```

---

## Agent Dispatch Notes

**For Sonnet agent prompt, include these constraints:**
1. Isolated test DB: `expense_tracker_test_per133`
2. Run ONLY targeted specs — NOT full suite: `bundle exec rspec spec/views/expenses/ spec/features/mobile_expense_cards_spec.rb`
3. Follow Financial Confidence palette (teal/amber/rose/emerald — never blue)
4. All strings in Spanish (locale :es)
5. Existing Stimulus controllers auto-register via eagerLoadControllersFrom — no manual registration needed
6. Take Playwright screenshots at 375px and 1280px after each visual change
7. The `_expense_row.html.erb` partial must NOT be modified — the card is a separate partial
8. Pre-commit hook runs rubocop + brakeman + rspec unit — ensure all pass
