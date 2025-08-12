### Task 2.4: Confidence Display Enhancement
**Priority**: Medium  
**Estimated Hours**: 4  
**Dependencies**: Task 2.3  

#### Description
Add confidence indicators and explanation tooltips to expense views.

#### Acceptance Criteria
- [ ] Confidence badge with color coding
- [ ] Hover tooltip with explanation
- [ ] One-click correction interface
- [ ] Visual feedback for learning
- [ ] Keyboard shortcuts for corrections
- [ ] Mobile-friendly touch interactions

#### Technical Implementation
```erb
<!-- app/views/expenses/_category_with_confidence.html.erb -->
<div data-controller="category-confidence"
     data-category-confidence-expense-id-value="<%= expense.id %>">
  
  <div class="flex items-center gap-2">
    <!-- Category Display -->
    <% if expense.category.present? %>
      <span class="text-sm font-medium text-slate-900">
        <%= expense.category.name %>
      </span>
      
      <!-- Confidence Badge -->
      <% if expense.ml_confidence.present? %>
        <span class="<%= confidence_badge_class(expense.ml_confidence) %>">
          <%= confidence_label(expense.ml_confidence) %>
        </span>
        
        <!-- Info Icon with Tooltip -->
        <button type="button"
                data-action="mouseenter->category-confidence#showTooltip 
                           mouseleave->category-confidence#hideTooltip"
                class="text-slate-400 hover:text-slate-600">
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/>
          </svg>
        </button>
      <% end %>
    <% else %>
      <span class="text-sm text-slate-500 italic">Uncategorized</span>
    <% end %>
    
    <!-- Quick Correction Button -->
    <button type="button"
            data-action="click->category-confidence#openCorrection"
            class="text-xs text-teal-600 hover:text-teal-700 underline">
      Change
    </button>
  </div>
  
  <!-- Tooltip Content (Hidden by default) -->
  <div data-category-confidence-target="tooltip"
       class="hidden absolute z-10 bg-slate-900 text-white text-xs rounded-lg p-3 mt-2 w-64">
    <div class="font-semibold mb-1">Why this category?</div>
    <div data-category-confidence-target="explanation">
      <!-- Populated by JavaScript -->
    </div>
  </div>
  
  <!-- Correction Modal -->
  <div data-category-confidence-target="modal"
       class="hidden fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
    <div class="bg-white rounded-lg p-6 w-96">
      <h3 class="text-lg font-semibold mb-4">Correct Category</h3>
      
      <div class="space-y-2">
        <% Category.all.each_with_index do |category, index| %>
          <button data-action="click->category-confidence#selectCategory"
                  data-category-id="<%= category.id %>"
                  class="w-full text-left px-4 py-2 rounded hover:bg-teal-50 
                         flex justify-between items-center group">
            <span><%= category.name %></span>
            <span class="text-xs text-slate-500"><%= index + 1 %></span>
          </button>
        <% end %>
      </div>
      
      <button data-action="click->category-confidence#closeModal"
              class="mt-4 text-sm text-slate-500 hover:text-slate-700">
        Cancel (Esc)
      </button>
    </div>
  </div>
</div>
```
