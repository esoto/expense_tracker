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
