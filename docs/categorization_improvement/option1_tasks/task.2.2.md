### Task 2.2: Pattern Management UI
**Priority**: High  
**Estimated Hours**: 8  
**Dependencies**: Task 2.1  

#### Description
Build admin interface for viewing and managing categorization patterns.

#### Acceptance Criteria
- [ ] Pattern list with search and filters
- [ ] Create/Edit pattern forms with validation
- [ ] Pattern performance metrics display
- [ ] Bulk import/export functionality
- [ ] Pattern testing tool
- [ ] Real-time pattern effectiveness chart
- [ ] Responsive design with Tailwind CSS
- [ ] Keyboard shortcuts for common actions

#### Technical Implementation
```erb
<!-- app/views/admin/patterns/index.html.erb -->
<div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-slate-900">Categorization Patterns</h1>
    
    <div class="flex gap-3">
      <%= link_to "Import", "#", 
          data: { action: "click->pattern-import#open" },
          class: "btn-secondary" %>
      <%= link_to "New Pattern", new_admin_pattern_path,
          class: "btn-primary" %>
    </div>
  </div>
  
  <div data-controller="pattern-list"
       data-pattern-list-url-value="<%= api_v1_patterns_path %>">
    
    <!-- Search and Filters -->
    <div class="mb-6 grid grid-cols-1 md:grid-cols-4 gap-4">
      <input type="text" 
             placeholder="Search patterns..."
             data-pattern-list-target="search"
             data-action="input->pattern-list#search"
             class="form-input" />
      
      <select data-pattern-list-target="typeFilter"
              data-action="change->pattern-list#filter"
              class="form-select">
        <option value="">All Types</option>
        <% CategorizationPattern::PATTERN_TYPES.each do |type| %>
          <option value="<%= type %>"><%= type.humanize %></option>
        <% end %>
      </select>
      
      <select data-pattern-list-target="categoryFilter"
              data-action="change->pattern-list#filter"
              class="form-select">
        <option value="">All Categories</option>
        <% Category.all.each do |category| %>
          <option value="<%= category.id %>"><%= category.name %></option>
        <% end %>
      </select>
      
      <select data-pattern-list-target="statusFilter"
              data-action="change->pattern-list#filter"
              class="form-select">
        <option value="active">Active</option>
        <option value="all">All</option>
        <option value="inactive">Inactive</option>
      </select>
    </div>
    
    <!-- Pattern List -->
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-slate-200">
        <thead class="bg-slate-50">
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
              Pattern
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
              Category
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
              Success Rate
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
              Usage
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
              Actions
            </th>
          </tr>
        </thead>
        <tbody data-pattern-list-target="tbody"
               class="bg-white divide-y divide-slate-200">
          <!-- Populated by Stimulus -->
        </tbody>
      </table>
    </div>
  </div>
</div>
```

```javascript
// app/javascript/controllers/pattern_list_controller.js
import { Controller } from "@hotwired/stimulus"
import { get } from "@rails/request.js"

export default class extends Controller {
  static targets = ["search", "typeFilter", "categoryFilter", 
                    "statusFilter", "tbody"]
  static values = { url: String }
  
  connect() {
    this.loadPatterns()
    this.setupKeyboardShortcuts()
  }
  
  async loadPatterns() {
    const params = this.buildParams()
    const response = await get(this.urlValue, { 
      query: params,
      responseKind: "json" 
    })
    
    if (response.ok) {
      const data = await response.json
      this.renderPatterns(data.data)
    }
  }
  
  renderPatterns(patterns) {
    this.tbodyTarget.innerHTML = patterns.map(pattern => 
      this.patternRow(pattern)
    ).join('')
  }
  
  patternRow(pattern) {
    const successRate = (pattern.attributes.success_rate * 100).toFixed(1)
    const statusColor = this.getStatusColor(pattern.attributes.success_rate)
    
    return `
      <tr>
        <td class="px-6 py-4 whitespace-nowrap">
          <div class="flex items-center">
            <span class="px-2 py-1 text-xs rounded-full bg-slate-100">
              ${pattern.attributes.pattern_type}
            </span>
            <span class="ml-2 text-sm text-slate-900">
              ${pattern.attributes.pattern_value}
            </span>
          </div>
        </td>
        <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-500">
          ${pattern.attributes.category_name}
        </td>
        <td class="px-6 py-4 whitespace-nowrap">
          <div class="flex items-center">
            <div class="w-16 bg-slate-200 rounded-full h-2">
              <div class="bg-${statusColor}-600 h-2 rounded-full" 
                   style="width: ${successRate}%"></div>
            </div>
            <span class="ml-2 text-sm text-slate-900">${successRate}%</span>
          </div>
        </td>
        <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-500">
          ${pattern.attributes.usage_count}
        </td>
        <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
          <a href="/admin/patterns/${pattern.id}/edit" 
             class="text-teal-600 hover:text-teal-900 mr-3">Edit</a>
          <a href="#" 
             data-action="click->pattern-list#test"
             data-pattern-id="${pattern.id}"
             class="text-amber-600 hover:text-amber-900">Test</a>
        </td>
      </tr>
    `
  }
  
  getStatusColor(rate) {
    if (rate >= 0.8) return 'emerald'
    if (rate >= 0.6) return 'amber'
    return 'rose'
  }
}
```
