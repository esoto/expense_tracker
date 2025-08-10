---

## Task 1.3: Performance Monitoring Dashboard

**Task ID:** EXP-1.3  
**Parent Epic:** EXP-EPIC-001  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 6  

### Description
Create a performance monitoring interface for sync operations, displaying metrics, success rates, and performance trends.

### Acceptance Criteria
- [ ] Dashboard shows sync performance metrics (speed, success rate)
- [ ] Historical sync performance graph (last 30 days)
- [ ] Error rate tracking and categorization
- [ ] Average sync duration by email account
- [ ] Peak sync times identification
- [ ] Export performance data to CSV

### Technical Notes

#### Performance Monitoring Implementation:

1. **Metrics Collection Service:**
   ```ruby
   # app/services/sync_metrics_collector.rb
   class SyncMetricsCollector
     METRICS_RETENTION = 90.days
     
     def record_sync_metrics(sync_session)
       metrics = {
         session_id: sync_session.id,
         duration: sync_session.duration,
         total_emails: sync_session.total_emails,
         processed_emails: sync_session.processed_emails,
         detected_expenses: sync_session.detected_expenses,
         success_rate: calculate_success_rate(sync_session),
         processing_speed: calculate_processing_speed(sync_session),
         error_count: sync_session.sync_session_accounts.sum(:error_count),
         timestamp: Time.current
       }
       
       # Store in time-series format
       store_metrics(metrics)
       
       # Update aggregated stats
       update_aggregated_stats(sync_session)
       
       # Check for anomalies
       detect_performance_anomalies(metrics)
     end
     
     private
     
     def store_metrics(metrics)
       # Store in Redis for real-time access
       redis_key = "metrics:sync:#{metrics[:session_id]}:#{metrics[:timestamp].to_i}"
       
       Redis.current.multi do |redis|
         redis.hset(redis_key, metrics)
         redis.expire(redis_key, METRICS_RETENTION)
         
         # Add to sorted set for time-based queries
         redis.zadd(
           "metrics:sync:timeline",
           metrics[:timestamp].to_i,
           redis_key
         )
       end
       
       # Also persist to database for long-term storage
       SyncMetric.create!(metrics)
     end
     
     def calculate_processing_speed(session)
       return 0 if session.duration.nil? || session.duration.zero?
       
       (session.processed_emails.to_f / session.duration) * 60 # emails per minute
     end
     
     def detect_performance_anomalies(metrics)
       # Get baseline from last 30 days
       baseline = calculate_baseline_performance
       
       # Check for significant deviations
       if metrics[:processing_speed] < baseline[:speed] * 0.5
         notify_performance_degradation(metrics, baseline)
       end
       
       if metrics[:error_count] > baseline[:errors] * 2
         notify_error_spike(metrics, baseline)
       end
     end
   end
   ```

2. **Dashboard Controller:**
   ```ruby
   # app/controllers/sync_performance_controller.rb
   class SyncPerformanceController < ApplicationController
     def index
       @metrics = SyncMetricsService.new.dashboard_data(
         period: params[:period] || '7d',
         account_id: params[:account_id]
       )
       
       respond_to do |format|
         format.html
         format.json { render json: @metrics }
       end
     end
     
     def export
       data = SyncMetricsService.new.export_data(
         start_date: params[:start_date],
         end_date: params[:end_date]
       )
       
       respond_to do |format|
         format.csv { send_data data.to_csv, filename: "sync_metrics_#{Date.current}.csv" }
         format.xlsx { send_data data.to_xlsx, filename: "sync_metrics_#{Date.current}.xlsx" }
       end
     end
   end
   ```

3. **Performance Dashboard View:**
   ```erb
   <!-- app/views/sync_performance/index.html.erb -->
   <div class="p-6" data-controller="performance-dashboard">
     <div class="mb-6">
       <h2 class="text-2xl font-bold text-slate-900">Monitor de Rendimiento de Sincronización</h2>
       
       <!-- Period selector -->
       <div class="mt-4 flex space-x-2">
         <% %w[1d 7d 30d 90d].each do |period| %>
           <%= link_to period.upcase,
                       sync_performance_path(period: period),
                       class: "px-3 py-1 rounded-lg #{
                         params[:period] == period ? 
                         'bg-teal-700 text-white' : 
                         'bg-slate-200 text-slate-700'
                       }" %>
         <% end %>
       </div>
     </div>
     
     <!-- Key metrics cards -->
     <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
       <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-4">
         <div class="text-sm text-slate-600">Velocidad Promedio</div>
         <div class="text-2xl font-bold text-slate-900">
           <%= @metrics[:avg_speed] %> emails/min
         </div>
         <div class="text-xs text-<%= @metrics[:speed_trend] > 0 ? 'emerald' : 'rose' %>-600">
           <%= @metrics[:speed_trend] > 0 ? '↑' : '↓' %>
           <%= number_to_percentage(@metrics[:speed_trend].abs, precision: 1) %>
         </div>
       </div>
       
       <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-4">
         <div class="text-sm text-slate-600">Tasa de Éxito</div>
         <div class="text-2xl font-bold text-slate-900">
           <%= number_to_percentage(@metrics[:success_rate], precision: 1) %>
         </div>
         <div class="mt-2">
           <div class="w-full bg-slate-200 rounded-full h-2">
             <div class="bg-emerald-600 h-2 rounded-full" 
                  style="width: <%= @metrics[:success_rate] %>%"></div>
           </div>
         </div>
       </div>
       
       <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-4">
         <div class="text-sm text-slate-600">Errores Totales</div>
         <div class="text-2xl font-bold text-<%= @metrics[:error_count] > 0 ? 'rose' : 'emerald' %>-600">
           <%= @metrics[:error_count] %>
         </div>
         <div class="text-xs text-slate-500">
           <%= @metrics[:error_categories].to_sentence %>
         </div>
       </div>
       
       <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-4">
         <div class="text-sm text-slate-600">Duración Promedio</div>
         <div class="text-2xl font-bold text-slate-900">
           <%= distance_of_time_in_words(@metrics[:avg_duration]) %>
         </div>
         <div class="text-xs text-slate-500">
           Por <%= number_with_delimiter(@metrics[:avg_email_count]) %> emails
         </div>
       </div>
     </div>
     
     <!-- Performance chart -->
     <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 mb-6">
       <h3 class="text-lg font-semibold text-slate-900 mb-4">Rendimiento en el Tiempo</h3>
       
       <div data-performance-dashboard-target="chart"
            data-chart-data="<%= @metrics[:chart_data].to_json %>">
         <%= line_chart @metrics[:chart_data],
                        height: "300px",
                        library: {
                          scales: {
                            y: { beginAtZero: true }
                          },
                          plugins: {
                            legend: { position: 'bottom' }
                          }
                        } %>
       </div>
     </div>
     
     <!-- Account-specific metrics -->
     <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
       <h3 class="text-lg font-semibold text-slate-900 mb-4">Rendimiento por Cuenta</h3>
       
       <div class="overflow-x-auto">
         <table class="min-w-full divide-y divide-slate-200">
           <thead>
             <tr>
               <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                 Cuenta
               </th>
               <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                 Sincronizaciones
               </th>
               <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                 Velocidad Promedio
               </th>
               <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                 Tasa de Éxito
               </th>
               <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                 Último Error
               </th>
             </tr>
           </thead>
           <tbody class="divide-y divide-slate-200">
             <% @metrics[:by_account].each do |account_metrics| %>
               <tr>
                 <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-900">
                   <%= account_metrics[:name] %>
                 </td>
                 <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-600">
                   <%= account_metrics[:sync_count] %>
                 </td>
                 <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-600">
                   <%= account_metrics[:avg_speed] %> emails/min
                 </td>
                 <td class="px-6 py-4 whitespace-nowrap text-sm">
                   <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full 
                          bg-<%= account_metrics[:success_rate] > 95 ? 'emerald' : 'amber' %>-100 
                          text-<%= account_metrics[:success_rate] > 95 ? 'emerald' : 'amber' %>-800">
                     <%= number_to_percentage(account_metrics[:success_rate], precision: 0) %>
                   </span>
                 </td>
                 <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-600">
                   <%= account_metrics[:last_error] || 'Ninguno' %>
                 </td>
               </tr>
             <% end %>
           </tbody>
         </table>
       </div>
     </div>
     
     <!-- Export button -->
     <div class="mt-6 flex justify-end">
       <%= link_to "Exportar Datos",
                   export_sync_performance_path(format: :csv),
                   class: "px-4 py-2 bg-teal-700 text-white rounded-lg hover:bg-teal-800" %>
     </div>
   </div>
   ```

4. **Peak Time Analysis:**
   ```ruby
   # app/services/sync_peak_analyzer.rb
   class SyncPeakAnalyzer
     def analyze_peak_times(period = 30.days)
       data = SyncSession.where(created_at: period.ago..Time.current)
                        .group_by_hour_of_day(:created_at)
                        .count
       
       peak_hours = data.sort_by { |_, count| -count }.first(3)
       
       {
         peak_hours: peak_hours.map { |hour, count| 
           { hour: hour, count: count, label: format_hour(hour) }
         },
         recommendations: generate_recommendations(peak_hours)
       }
     end
     
     private
     
     def generate_recommendations(peak_hours)
       recommendations = []
       
       if peak_hours.any? { |hour, _| hour.between?(9, 17) }
         recommendations << "Consider scheduling syncs outside business hours for better performance"
       end
       
       if peak_hours.any? { |hour, _| hour.between?(0, 6) }
         recommendations << "Early morning syncs show good performance"
       end
       
       recommendations
     end
   end
   ```

5. **Testing:**
   ```ruby
   RSpec.describe SyncMetricsCollector do
     it "records metrics correctly" do
       session = create(:sync_session, :completed)
       
       collector.record_sync_metrics(session)
       
       metrics = SyncMetric.last
       expect(metrics.session_id).to eq(session.id)
       expect(metrics.processing_speed).to be > 0
     end
     
     it "detects performance anomalies" do
       allow(collector).to receive(:notify_performance_degradation)
       
       slow_session = create(:sync_session, 
         processed_emails: 10,
         duration: 3600 # Very slow
       )
       
       collector.record_sync_metrics(slow_session)
       
       expect(collector).to have_received(:notify_performance_degradation)
     end
   end
   ```

6. **Performance Optimizations:**
   - Use materialized views for aggregated metrics
   - Cache dashboard data for 5 minutes
   - Background job for heavy calculations
   - Index on created_at for time-based queries
