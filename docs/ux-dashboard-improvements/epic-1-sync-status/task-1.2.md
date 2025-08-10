Task 1.2: Sync Conflict Resolution UI

**Task ID:** EXP-1.2  
**Parent Epic:** EXP-EPIC-001  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 8  

### Description
Create user interface components for handling sync conflicts when duplicate transactions are detected or when transactions need manual review.

### Acceptance Criteria
- [ ] Modal/drawer displays conflicting transactions side-by-side
- [ ] User can choose: keep existing, keep new, keep both, or merge
- [ ] Bulk conflict resolution for multiple similar conflicts
- [ ] Conflict history log maintained
- [ ] Undo capability for conflict resolutions
- [ ] Clear visual indicators for conflicts in main list

### Designs
```
┌─────────────────────────────────────┐
│ Sync Conflict Resolution            │
├─────────────────────────────────────┤
│ 3 potential duplicates found        │
│                                     │
│ ┌─────────┬─────────┬─────────┐   │
│ │Existing │  New    │ Action  │   │
│ ├─────────┼─────────┼─────────┤   │
│ │$45.00   │$45.00   │[Keep]   │   │
│ │Walmart  │WALMART  │[Merge]  │   │
│ │Jan 15   │Jan 15   │[Skip]   │   │
│ └─────────┴─────────┴─────────┘   │
│                                     │
│ [Apply to All Similar] [Review Each]│
└─────────────────────────────────────┘
```

### Technical Notes

#### Conflict Resolution Implementation:

1. **Duplicate Detection Algorithm:**
   ```ruby
   # app/services/duplicate_detector.rb
   class DuplicateDetector
     SIMILARITY_THRESHOLD = 0.85
     
     def find_duplicates(new_expense, existing_expenses)
       potential_duplicates = []
       
       existing_expenses.each do |existing|
         similarity = calculate_similarity(new_expense, existing)
         
         if similarity >= SIMILARITY_THRESHOLD
           potential_duplicates << {
             expense: existing,
             similarity: similarity,
             differences: identify_differences(new_expense, existing)
           }
         end
       end
       
       potential_duplicates.sort_by { |d| -d[:similarity] }
     end
     
     private
     
     def calculate_similarity(expense1, expense2)
       scores = []
       
       # Amount similarity (exact match or within 1%)
       amount_diff = (expense1.amount - expense2.amount).abs
       amount_score = amount_diff <= expense1.amount * 0.01 ? 1.0 : 0.0
       scores << amount_score * 0.4 # 40% weight
       
       # Date similarity (same day)
       date_score = expense1.date == expense2.date ? 1.0 : 0.0
       scores << date_score * 0.3 # 30% weight
       
       # Description similarity (fuzzy match)
       desc_score = fuzzy_match(expense1.description, expense2.description)
       scores << desc_score * 0.3 # 30% weight
       
       scores.sum
     end
     
     def fuzzy_match(str1, str2)
       return 0.0 if str1.nil? || str2.nil?
       
       # Normalize strings
       s1 = str1.downcase.gsub(/[^a-z0-9]/, '')
       s2 = str2.downcase.gsub(/[^a-z0-9]/, '')
       
       # Calculate Levenshtein distance
       distance = levenshtein_distance(s1, s2)
       max_length = [s1.length, s2.length].max
       
       return 1.0 if max_length == 0
       
       1.0 - (distance.to_f / max_length)
     end
   end
   ```

2. **Conflict Resolution UI Component:**
   ```erb
   <!-- app/views/sync_sessions/_conflict_modal.html.erb -->
   <div data-controller="conflict-resolver"
        data-conflict-resolver-conflicts-value="<%= @conflicts.to_json %>"
        class="fixed inset-0 z-50 overflow-y-auto hidden"
        data-conflict-resolver-target="modal">
     
     <div class="min-h-screen px-4 text-center">
       <div class="fixed inset-0 bg-slate-900 bg-opacity-75 transition-opacity"></div>
       
       <div class="inline-block w-full max-w-4xl my-8 text-left align-middle transition-all transform bg-white shadow-xl rounded-xl">
         <div class="px-6 py-4 border-b border-slate-200">
           <h3 class="text-xl font-semibold text-slate-900">
             Resolver Conflictos de Sincronización
           </h3>
           <p class="mt-1 text-sm text-slate-600">
             Se encontraron <%= @conflicts.size %> posibles duplicados
           </p>
         </div>
         
         <div class="px-6 py-4 max-h-96 overflow-y-auto">
           <% @conflicts.each_with_index do |conflict, index| %>
             <div class="mb-6 p-4 bg-slate-50 rounded-lg" 
                  data-conflict-index="<%= index %>">
               
               <div class="grid grid-cols-3 gap-4">
                 <!-- Existing expense -->
                 <div class="space-y-2">
                   <h4 class="font-medium text-slate-700">Existente</h4>
                   <div class="bg-white p-3 rounded border border-slate-200">
                     <p class="font-semibold"><%= format_currency(conflict[:existing].amount) %></p>
                     <p class="text-sm text-slate-600"><%= conflict[:existing].description %></p>
                     <p class="text-xs text-slate-500"><%= l(conflict[:existing].date) %></p>
                   </div>
                 </div>
                 
                 <!-- New expense -->
                 <div class="space-y-2">
                   <h4 class="font-medium text-slate-700">Nuevo</h4>
                   <div class="bg-white p-3 rounded border border-teal-200">
                     <p class="font-semibold"><%= format_currency(conflict[:new].amount) %></p>
                     <p class="text-sm text-slate-600"><%= conflict[:new].description %></p>
                     <p class="text-xs text-slate-500"><%= l(conflict[:new].date) %></p>
                   </div>
                 </div>
                 
                 <!-- Actions -->
                 <div class="space-y-2">
                   <h4 class="font-medium text-slate-700">Acción</h4>
                   <div class="space-y-2">
                     <button data-action="click->conflict-resolver#keepExisting"
                             data-conflict-index="<%= index %>"
                             class="w-full px-3 py-2 bg-white border border-slate-200 rounded-lg text-sm hover:bg-slate-50">
                       Mantener Existente
                     </button>
                     <button data-action="click->conflict-resolver#keepNew"
                             data-conflict-index="<%= index %>"
                             class="w-full px-3 py-2 bg-teal-700 text-white rounded-lg text-sm hover:bg-teal-800">
                       Usar Nuevo
                     </button>
                     <button data-action="click->conflict-resolver#keepBoth"
                             data-conflict-index="<%= index %>"
                             class="w-full px-3 py-2 bg-amber-600 text-white rounded-lg text-sm hover:bg-amber-700">
                       Mantener Ambos
                     </button>
                     <button data-action="click->conflict-resolver#merge"
                             data-conflict-index="<%= index %>"
                             class="w-full px-3 py-2 bg-slate-600 text-white rounded-lg text-sm hover:bg-slate-700">
                       Combinar
                     </button>
                   </div>
                 </div>
               </div>
               
               <!-- Similarity indicator -->
               <div class="mt-3 flex items-center space-x-2">
                 <span class="text-xs text-slate-500">Similaridad:</span>
                 <div class="flex-1 bg-slate-200 rounded-full h-2">
                   <div class="bg-amber-600 h-2 rounded-full"
                        style="width: <%= (conflict[:similarity] * 100).round %>%"></div>
                 </div>
                 <span class="text-xs font-medium text-slate-700">
                   <%= (conflict[:similarity] * 100).round %>%
                 </span>
               </div>
             </div>
           <% end %>
         </div>
         
         <!-- Bulk actions -->
         <div class="px-6 py-4 bg-slate-50 border-t border-slate-200">
           <div class="flex items-center justify-between">
             <div class="flex items-center space-x-2">
               <input type="checkbox" 
                      data-conflict-resolver-target="applyToAll"
                      class="rounded border-slate-300 text-teal-700 focus:ring-teal-500">
               <label class="text-sm text-slate-700">
                 Aplicar a todos los conflictos similares
               </label>
             </div>
             
             <div class="flex space-x-3">
               <button data-action="click->conflict-resolver#cancel"
                       class="px-4 py-2 bg-white border border-slate-200 rounded-lg text-slate-700 hover:bg-slate-50">
                 Cancelar
               </button>
               <button data-action="click->conflict-resolver#resolve"
                       class="px-4 py-2 bg-teal-700 text-white rounded-lg hover:bg-teal-800">
                 Resolver Conflictos
               </button>
             </div>
           </div>
         </div>
       </div>
     </div>
   </div>
   ```

3. **Conflict Resolution Controller:**
   ```javascript
   // app/javascript/controllers/conflict_resolver_controller.js
   export default class extends Controller {
     static targets = ['modal', 'applyToAll']
     static values = { conflicts: Array }
     
     connect() {
       this.resolutions = new Map()
       this.initializeResolutions()
     }
     
     initializeResolutions() {
       this.conflictsValue.forEach((conflict, index) => {
         this.resolutions.set(index, { action: null, data: conflict })
       })
     }
     
     keepExisting(event) {
       const index = parseInt(event.currentTarget.dataset.conflictIndex)
       this.setResolution(index, 'keep_existing')
       
       if (this.applyToAllTarget.checked) {
         this.applyToSimilar(index, 'keep_existing')
       }
     }
     
     keepNew(event) {
       const index = parseInt(event.currentTarget.dataset.conflictIndex)
       this.setResolution(index, 'keep_new')
       
       if (this.applyToAllTarget.checked) {
         this.applyToSimilar(index, 'keep_new')
       }
     }
     
     merge(event) {
       const index = parseInt(event.currentTarget.dataset.conflictIndex)
       this.showMergeDialog(index)
     }
     
     async resolve() {
       const resolutions = Array.from(this.resolutions.values())
         .filter(r => r.action !== null)
       
       try {
         const response = await fetch('/sync_sessions/resolve_conflicts', {
           method: 'POST',
           headers: {
             'Content-Type': 'application/json',
             'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
           },
           body: JSON.stringify({ resolutions })
         })
         
         if (response.ok) {
           this.hideModal()
           this.showSuccessMessage('Conflictos resueltos exitosamente')
         } else {
           throw new Error('Failed to resolve conflicts')
         }
       } catch (error) {
         this.showErrorMessage('Error al resolver conflictos')
       }
     }
   }
   ```

4. **Conflict History Tracking:**
   ```ruby
   # app/models/sync_conflict_resolution.rb
   class SyncConflictResolution < ApplicationRecord
     belongs_to :sync_session
     belongs_to :existing_expense, class_name: 'Expense', optional: true
     belongs_to :new_expense, class_name: 'Expense', optional: true
     
     validates :action, inclusion: { 
       in: %w[keep_existing keep_new keep_both merge skip] 
     }
     
     scope :recent, -> { order(created_at: :desc) }
     scope :by_action, ->(action) { where(action: action) }
     
     def undo!
       case action
       when 'keep_new'
         new_expense&.destroy
       when 'keep_existing'
         # Re-create the new expense if we have the data
         recreate_new_expense if new_expense_data.present?
       when 'merge'
         # Revert to original states
         revert_merge
       end
       
       update!(undone: true, undone_at: Time.current)
     end
   end
   ```

5. **Testing:**
   ```ruby
   RSpec.describe DuplicateDetector do
     it "detects exact duplicates" do
       expense1 = create(:expense, amount: 100, date: Date.today)
       expense2 = build(:expense, amount: 100, date: Date.today)
       
       duplicates = detector.find_duplicates(expense2, [expense1])
       
       expect(duplicates).not_to be_empty
       expect(duplicates.first[:similarity]).to be >= 0.85
     end
     
     it "handles fuzzy description matching" do
       expense1 = create(:expense, description: "WALMART STORE #1234")
       expense2 = build(:expense, description: "Walmart Store")
       
       score = detector.fuzzy_match(
         expense1.description,
         expense2.description
       )
       
       expect(score).to be > 0.5
     end
   end
   ```

6. **Performance Considerations:**
   - Index on (amount, date) for fast duplicate queries
   - Cache similarity calculations for session
   - Batch conflict resolution to minimize DB calls
   - Use PostgreSQL full-text search for descriptions
