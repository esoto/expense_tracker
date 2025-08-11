# Option 1: Core Implementation Tasks - Pattern-Based Categorization

## Phase 2: Core Implementation (Week 1, Days 4-5 & Week 2, Days 1-2)

### Task 2.1: Pattern API Endpoints
**Priority**: Critical  
**Estimated Hours**: 6  
**Dependencies**: Tasks 1.1-1.6  

#### Description
Create RESTful API endpoints for pattern management and categorization.

#### Acceptance Criteria
- [ ] POST /api/v1/categorization/suggest - Returns category suggestion
- [ ] GET /api/v1/patterns - Lists patterns with pagination
- [ ] POST /api/v1/patterns - Creates new pattern
- [ ] PATCH /api/v1/patterns/:id - Updates pattern
- [ ] DELETE /api/v1/patterns/:id - Soft deletes pattern
- [ ] POST /api/v1/categorization/feedback - Records user feedback
- [ ] API documentation with examples
- [ ] Rate limiting implemented (100 req/min)
- [ ] Authentication via API tokens

#### Technical Implementation
```ruby
# app/controllers/api/v1/patterns_controller.rb
class Api::V1::PatternsController < Api::V1::BaseController
  before_action :authenticate_api_token!
  before_action :set_pattern, only: [:show, :update, :destroy]
  
  def index
    @patterns = CategorizationPattern
      .active
      .includes(:category)
      .page(params[:page])
      .per(params[:per_page] || 25)
    
    render json: PatternSerializer.new(@patterns, {
      meta: pagination_meta(@patterns)
    })
  end
  
  def create
    @pattern = CategorizationPattern.new(pattern_params)
    
    if @pattern.save
      PatternCacheInvalidator.perform_async
      render json: PatternSerializer.new(@pattern), status: :created
    else
      render json: { errors: @pattern.errors }, status: :unprocessable_entity
    end
  end
  
  def suggest
    expense_data = suggestion_params
    engine = Categorization::PatternEngine.new
    
    result = engine.categorize_from_data(expense_data)
    
    render json: {
      category: CategorySerializer.new(result.category),
      confidence: result.confidence,
      explanation: result.explanation,
      alternatives: result.alternatives.map { |alt|
        {
          category: CategorySerializer.new(alt.category),
          confidence: alt.confidence
        }
      }
    }
  end
  
  private
  
  def pattern_params
    params.require(:pattern).permit(
      :pattern_type, :pattern_value, :category_id,
      :confidence_weight, metadata: {}
    )
  end
end
```

#### Testing Requirements
```ruby
# spec/requests/api/v1/patterns_spec.rb
RSpec.describe "Patterns API" do
  let(:api_token) { create(:api_token) }
  let(:headers) { { 'X-API-Token' => api_token.token } }
  
  describe "POST /api/v1/patterns" do
    it "creates pattern with valid data" do
      post "/api/v1/patterns", 
           params: { pattern: valid_attributes },
           headers: headers
      
      expect(response).to have_http_status(:created)
      expect(json_response['data']['attributes']['pattern_value'])
        .to eq(valid_attributes[:pattern_value])
    end
    
    it "invalidates cache after creation" do
      expect(PatternCacheInvalidator).to receive(:perform_async)
      
      post "/api/v1/patterns",
           params: { pattern: valid_attributes },
           headers: headers
    end
  end
end
```

---

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

---

### Task 2.3: Bulk Categorization UI
**Priority**: High  
**Estimated Hours**: 6  
**Dependencies**: Tasks 2.1, 2.2  

#### Description
Create interface for bulk categorization of uncategorized expenses.

#### Acceptance Criteria
- [ ] Groups similar uncategorized expenses
- [ ] Shows suggested category with confidence
- [ ] One-click approval for groups
- [ ] Individual expense override option
- [ ] Progress tracking for bulk operations
- [ ] Undo functionality
- [ ] Export categorization report

#### Technical Implementation
```ruby
# app/controllers/bulk_categorizations_controller.rb
class BulkCategorizationsController < ApplicationController
  def index
    @groups = UncategorizedGrouper.new.group_expenses
    @stats = {
      total_uncategorized: Expense.uncategorized.count,
      groups_count: @groups.count,
      high_confidence: @groups.count { |g| g.confidence > 0.8 }
    }
  end
  
  def create
    result = BulkCategorizer.new.categorize(bulk_params[:expense_ids])
    
    if result.success?
      redirect_to bulk_categorizations_path, 
                  notice: "Categorized #{result.count} expenses"
    else
      redirect_to bulk_categorizations_path,
                  alert: result.error_message
    end
  end
end

# app/services/uncategorized_grouper.rb
class UncategorizedGrouper
  def group_expenses
    expenses = Expense.uncategorized.includes(:email_account)
    
    # Group by merchant similarity
    groups = group_by_merchant(expenses)
    
    # Add categorization suggestions
    groups.map do |group|
      suggestion = PatternEngine.new.categorize(group.first)
      
      BulkGroup.new(
        expenses: group,
        suggested_category: suggestion.category,
        confidence: suggestion.confidence,
        pattern_matched: suggestion.pattern
      )
    end.sort_by { |g| -g.confidence }
  end
  
  private
  
  def group_by_merchant(expenses)
    groups = []
    processed = Set.new
    
    expenses.each do |expense|
      next if processed.include?(expense.id)
      
      # Find similar expenses
      similar = find_similar_expenses(expense, expenses - [expense])
      group = [expense] + similar
      
      group.each { |e| processed.add(e.id) }
      groups << group
    end
    
    groups
  end
end
```

---

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

---

### Task 2.5: Pattern Analytics Dashboard
**Priority**: Medium  
**Estimated Hours**: 5  
**Dependencies**: Tasks 2.1-2.4  

#### Description
Create dashboard showing pattern performance and system metrics.

#### Acceptance Criteria
- [ ] Overall accuracy metrics
- [ ] Per-category performance breakdown
- [ ] Most/least effective patterns
- [ ] Trend charts over time
- [ ] Pattern usage heatmap
- [ ] Export functionality
- [ ] Real-time updates

#### Technical Implementation
```ruby
# app/services/pattern_analytics.rb
class PatternAnalytics
  def dashboard_metrics
    {
      overall: overall_metrics,
      by_category: category_breakdown,
      top_patterns: top_performing_patterns,
      weak_patterns: patterns_needing_review,
      trends: calculate_trends,
      recent_activity: recent_corrections
    }
  end
  
  private
  
  def overall_metrics
    total = CategorizationFeedback.count
    correct = CategorizationFeedback.where(correct: true).count
    
    {
      accuracy: (correct.to_f / total * 100).round(1),
      total_patterns: CategorizationPattern.active.count,
      total_categorizations: total,
      uncategorized_expenses: Expense.uncategorized.count,
      avg_confidence: Expense.where.not(ml_confidence: nil)
                             .average(:ml_confidence).to_f.round(3)
    }
  end
  
  def category_breakdown
    Category.all.map do |category|
      patterns = category.categorization_patterns.active
      feedbacks = CategorizationFeedback
        .joins(:expense)
        .where(expenses: { category_id: category.id })
      
      {
        category: category.name,
        pattern_count: patterns.count,
        avg_success_rate: patterns.average(:success_rate).to_f.round(3),
        total_uses: patterns.sum(:usage_count),
        accuracy: calculate_category_accuracy(category)
      }
    end
  end
end
```

---

## Performance Optimizations

### Database Indexes
```ruby
class AddPatternPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # For pattern lookups
    add_index :categorization_patterns, 
              [:pattern_type, :active, :success_rate],
              name: 'idx_patterns_lookup'
    
    # For feedback queries
    add_index :categorization_feedbacks,
              [:created_at, :correct],
              name: 'idx_feedback_analytics'
    
    # For bulk operations
    add_index :expenses,
              [:category_id, :created_at],
              where: 'category_id IS NULL',
              name: 'idx_uncategorized_expenses'
  end
end
```

### Caching Strategy
```ruby
# config/initializers/pattern_caching.rb
Rails.application.config.after_initialize do
  # Warm pattern cache on startup
  if Rails.env.production?
    PatternCacheWarmer.perform_async
  end
  
  # Set up cache expiration
  Rails.cache.redis.config(:expire_after, 1.hour)
end
```

---

## Next Steps
- Integration testing
- Performance benchmarking
- User acceptance testing
- Production deployment planning