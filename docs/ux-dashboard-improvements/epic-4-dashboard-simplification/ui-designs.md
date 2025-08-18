# Dashboard Simplification UI Designs

## Executive Summary

This document provides comprehensive UI specifications for the dashboard simplification epic, including detailed wireframes, Tailwind CSS implementations, ERB template modifications, and responsive design patterns. All designs strictly adhere to the Financial Confidence color palette and prioritize mobile-first, accessible interfaces.

## Design Principles

### Visual Hierarchy
1. **Primary Level**: Hero metrics with maximum visual weight (60px font, gradient backgrounds)
2. **Secondary Level**: Period metrics with moderate prominence (24px font, white cards)
3. **Tertiary Level**: Supporting details with minimal emphasis (14px font, subtle borders)

### Spacing System
```css
/* Consistent 8px grid system */
--space-xs: 0.25rem;  /* 4px */
--space-sm: 0.5rem;   /* 8px */
--space-md: 1rem;     /* 16px */
--space-lg: 1.5rem;   /* 24px */
--space-xl: 2rem;     /* 32px */
--space-2xl: 3rem;    /* 48px */
--space-3xl: 4rem;    /* 64px */
```

### Color Usage Guidelines
- **Primary Actions**: `teal-700` (#0F766E)
- **Success States**: `emerald-500` (#10B981)
- **Warnings**: `amber-600` (#D97706)
- **Errors**: `rose-600` (#E11D48)
- **Text Hierarchy**: `slate-900` → `slate-600` → `slate-500`
- **Backgrounds**: `white` → `slate-50` → `slate-100`

## Story 1: Remove Duplicate Sync Sections

### Before State (Current Dashboard)
```
┌─────────────────────────────────────────────────────────────────┐
│ Dashboard Header                                                │
├─────────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Email Sync Section (Lines 13-177)                           │ │
│ │ - Sync controls                                              │ │
│ │ - Progress bars                                               │ │
│ │ - Account list                                                │ │
│ │ - Status indicators                                           │ │
│ │ [165 lines of code]                                          │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Sync Status Widget (Line 181)                               │ │
│ │ [Duplicate functionality]                                     │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Queue Visualization (Line 186)                              │ │
│ │ [Another sync-related widget]                                │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### After State (Simplified)
```
┌─────────────────────────────────────────────────────────────────┐
│ Dashboard Header                                                │
├─────────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Unified Sync Widget                                          │ │
│ │ ┌─────────────────────────────────────────────────────────┐ │ │
│ │ │ [●] Sincronización Activa         Auto-sync ON    [⚙]   │ │ │
│ │ ├─────────────────────────────────────────────────────────┤ │ │
│ │ │ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░  75% (150/200 emails)            │ │ │
│ │ │ 42 gastos detectados • 2 min restantes                  │ │ │
│ │ ├─────────────────────────────────────────────────────────┤ │ │
│ │ │ ✓ Gmail Personal    ✓ Outlook Work    ⟲ BAC (syncing)  │ │ │
│ │ └─────────────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### ERB Template Implementation
```erb
<!-- app/views/expenses/dashboard.html.erb (Lines 13-186 replaced with:) -->
<%= turbo_frame_tag "unified_sync_widget", 
    class: "block",
    data: { turbo_stream: true } do %>
  
  <div class="bg-white rounded-xl shadow-sm p-6 mb-6"
       data-controller="unified-sync"
       data-unified-sync-user-id-value="<%= current_user.id %>"
       data-unified-sync-session-id-value="<%= @active_sync_session&.id %>">
    
    <!-- Compact Header with Controls -->
    <div class="flex items-center justify-between mb-4">
      <div class="flex items-center space-x-3">
        <!-- Status Indicator -->
        <div class="relative">
          <% if @active_sync_session %>
            <span class="flex h-3 w-3">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-teal-400 opacity-75"></span>
              <span class="relative inline-flex rounded-full h-3 w-3 bg-teal-500"></span>
            </span>
          <% else %>
            <span class="inline-flex rounded-full h-3 w-3 bg-slate-300"></span>
          <% end %>
        </div>
        
        <h3 class="text-base font-semibold text-slate-900">
          <%= @active_sync_session ? "Sincronización Activa" : "Sincronización" %>
        </h3>
      </div>
      
      <!-- Quick Actions -->
      <div class="flex items-center space-x-2">
        <!-- Auto-sync Toggle -->
        <label class="inline-flex items-center cursor-pointer">
          <span class="text-sm text-slate-600 mr-2">Auto-sync</span>
          <button type="button"
                  class="relative inline-flex h-6 w-11 items-center rounded-full 
                         <%= @auto_sync_enabled ? 'bg-teal-600' : 'bg-slate-200' %>"
                  data-action="click->unified-sync#toggleAutoSync">
            <span class="<%= @auto_sync_enabled ? 'translate-x-6' : 'translate-x-1' %> 
                         inline-block h-4 w-4 transform rounded-full bg-white transition">
            </span>
          </button>
        </label>
        
        <!-- Settings -->
        <button class="p-1.5 text-slate-400 hover:text-slate-600 transition-colors"
                data-action="click->unified-sync#openSettings">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                  d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/>
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                  d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
          </svg>
        </button>
      </div>
    </div>
    
    <!-- Progress Section (Only shown when syncing) -->
    <% if @active_sync_session %>
      <div class="space-y-3 mb-4" data-unified-sync-target="progressSection">
        <!-- Progress Bar -->
        <div class="relative">
          <div class="overflow-hidden h-2 text-xs flex rounded-full bg-slate-100">
            <div class="shadow-none flex flex-col text-center whitespace-nowrap text-white 
                        justify-center bg-gradient-to-r from-teal-600 to-teal-700 transition-all 
                        duration-500 ease-out"
                 data-unified-sync-target="progressBar"
                 style="width: <%= @active_sync_session.progress_percentage %>%"
                 role="progressbar"
                 aria-valuenow="<%= @active_sync_session.progress_percentage %>"
                 aria-valuemin="0"
                 aria-valuemax="100">
            </div>
          </div>
        </div>
        
        <!-- Progress Details -->
        <div class="flex items-center justify-between text-sm">
          <span class="text-slate-600">
            <span class="font-medium text-slate-900" data-unified-sync-target="percentage">
              <%= @active_sync_session.progress_percentage %>%
            </span>
            (<span data-unified-sync-target="processed"><%= @active_sync_session.processed_emails %></span>/<%= @active_sync_session.total_emails %> correos)
          </span>
          <span class="text-teal-700 font-medium">
            <span data-unified-sync-target="detected"><%= @active_sync_session.detected_expenses %></span> gastos detectados
          </span>
          <span class="text-slate-500" data-unified-sync-target="timeRemaining">
            <%= distance_of_time_in_words(@active_sync_session.estimated_time_remaining) %> restante
          </span>
        </div>
      </div>
    <% end %>
    
    <!-- Account Status Grid -->
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
      <% @email_accounts.each do |account| %>
        <div class="flex items-center justify-between p-2 rounded-lg 
                    <%= account.syncing? ? 'bg-teal-50 border border-teal-200' : 'bg-slate-50' %>"
             data-account-id="<%= account.id %>">
          <div class="flex items-center space-x-2">
            <!-- Account Status Icon -->
            <% if account.syncing? %>
              <svg class="animate-spin h-4 w-4 text-teal-600" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
            <% elsif account.last_sync_successful? %>
              <svg class="h-4 w-4 text-emerald-500" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
              </svg>
            <% else %>
              <svg class="h-4 w-4 text-rose-500" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
              </svg>
            <% end %>
            
            <span class="text-sm font-medium text-slate-700 truncate max-w-[150px]">
              <%= account.display_name %>
            </span>
          </div>
          
          <!-- Individual Sync Button -->
          <button class="px-2 py-1 text-xs font-medium rounded
                         <%= account.syncing? ? 'text-slate-400 bg-slate-100 cursor-not-allowed' : 'text-teal-700 bg-teal-50 hover:bg-teal-100' %>"
                  data-action="click->unified-sync#syncAccount"
                  data-account-id="<%= account.id %>"
                  <%= 'disabled' if account.syncing? || @active_sync_session %>>
            <%= account.syncing? ? 'Sincronizando...' : 'Sincronizar' %>
          </button>
        </div>
      <% end %>
    </div>
    
    <!-- Main Sync Button (Only shown when not syncing) -->
    <% unless @active_sync_session %>
      <div class="mt-4 pt-4 border-t border-slate-200">
        <button class="w-full bg-teal-700 hover:bg-teal-800 text-white font-medium py-2.5 px-4 
                       rounded-lg transition-colors duration-200 flex items-center justify-center space-x-2"
                data-action="click->unified-sync#syncAll">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                  d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
          </svg>
          <span>Sincronizar Todas las Cuentas</span>
        </button>
      </div>
    <% end %>
  </div>
<% end %>
```

### Responsive Breakpoints
```css
/* Mobile (< 640px) */
@media (max-width: 639px) {
  .unified-sync-widget {
    padding: 1rem;
  }
  .account-grid {
    grid-template-columns: 1fr;
  }
}

/* Tablet (640px - 1024px) */
@media (min-width: 640px) and (max-width: 1023px) {
  .account-grid {
    grid-template-columns: repeat(2, 1fr);
  }
}

/* Desktop (> 1024px) */
@media (min-width: 1024px) {
  .account-grid {
    grid-template-columns: repeat(3, 1fr);
  }
}
```

## Story 2: Simplify Metric Cards

### Before State (Complex Metrics)
```
┌──────────────────────────────────────────────────────────┐
│ Primary Metric Card                                      │
│ ┌────────────────────────────────────────────────────┐  │
│ │ Total Anual                                        │  │
│ │ ₡1,234,567                                         │  │
│ │ ├──────────────────────────────────────────────┤  │  │
│ │ │ Transacciones │ Promedio │ Categorías         │  │  │
│ │ │     142       │ ₡8,693   │    12              │  │  │
│ │ ├──────────────────────────────────────────────┤  │  │
│ │ │ Budget Progress: ▓▓▓▓▓▓░░░░ 65%              │  │  │
│ │ │ Trend: ↑ 23.5% vs last year                   │  │  │
│ │ └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

### After State (Simplified)
```
┌──────────────────────────────────────────────────────────┐
│ ┌────────────────────────────────────────────────────┐  │
│ │                  TOTAL ANUAL                        │  │
│ │                                                      │  │
│ │              ₡1,234,567                             │  │
│ │                                                      │  │
│ │              ↓ vs período anterior                  │  │
│ └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

### ERB Implementation for Primary Metric
```erb
<!-- app/views/expenses/_primary_metric.html.erb -->
<div class="relative overflow-hidden bg-gradient-to-br from-teal-700 to-teal-800 
            rounded-2xl shadow-xl p-8 lg:p-10"
     data-controller="animated-metric"
     data-animated-metric-value="<%= @total_amount %>"
     data-animated-metric-currency-value="true">
  
  <!-- Background Pattern (Subtle) -->
  <div class="absolute inset-0 opacity-10">
    <svg class="absolute inset-0 w-full h-full" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <pattern id="grid" width="20" height="20" patternUnits="userSpaceOnUse">
          <circle cx="10" cy="10" r="1" fill="white"/>
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill="url(#grid)"/>
    </svg>
  </div>
  
  <!-- Content -->
  <div class="relative text-center">
    <!-- Label -->
    <h2 class="text-sm font-medium text-teal-100 uppercase tracking-wider mb-3">
      Total Anual
    </h2>
    
    <!-- Amount -->
    <div class="mb-4">
      <span class="text-5xl lg:text-6xl font-bold text-white tracking-tight"
            data-animated-metric-target="display">
        ₡0
      </span>
    </div>
    
    <!-- Simple Trend Indicator -->
    <div class="inline-flex items-center space-x-2">
      <% if @trend_direction == :up %>
        <svg class="w-5 h-5 text-rose-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6"/>
        </svg>
        <span class="text-sm text-rose-200">Mayor que período anterior</span>
      <% elsif @trend_direction == :down %>
        <svg class="w-5 h-5 text-emerald-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 17h8m0 0V9m0 8l-8-8-4 4-6-6"/>
        </svg>
        <span class="text-sm text-emerald-200">Menor que período anterior</span>
      <% else %>
        <svg class="w-5 h-5 text-teal-200" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14"/>
        </svg>
        <span class="text-sm text-teal-200">Sin cambios</span>
      <% end %>
    </div>
    
    <!-- Hidden Tooltip Trigger for Details -->
    <button class="absolute top-4 right-4 p-2 text-teal-200 hover:text-white 
                   transition-colors opacity-0 hover:opacity-100"
            data-controller="metric-tooltip"
            data-metric-tooltip-content-value="<%= @metric_details.to_json %>"
            aria-label="Ver detalles">
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
              d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
      </svg>
    </button>
  </div>
</div>
```

### Secondary Metric Cards
```erb
<!-- app/views/expenses/_secondary_metrics.html.erb -->
<div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
  <% [:month, :week, :today].each do |period| %>
    <div class="bg-white rounded-xl shadow-sm p-6 hover:shadow-md transition-all duration-200
                border border-slate-100 group"
         data-controller="metric-card"
         data-metric-card-period-value="<%= period %>">
      
      <!-- Header -->
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-xs font-medium text-slate-500 uppercase tracking-wider">
          <%= t("metrics.period.#{period}") %>
        </h3>
        
        <!-- Trend Icon (Minimal) -->
        <% if @metrics[period][:trend] %>
          <div class="w-6 h-6 rounded-full flex items-center justify-center
                      <%= @metrics[period][:trend] == :up ? 'bg-rose-50' : 'bg-emerald-50' %>">
            <% if @metrics[period][:trend] == :up %>
              <svg class="w-3 h-3 text-rose-500" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 7.414V15a1 1 0 11-2 0V7.414L6.707 9.707a1 1 0 01-1.414 0z" clip-rule="evenodd"/>
              </svg>
            <% else %>
              <svg class="w-3 h-3 text-emerald-500" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M14.707 10.293a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 111.414-1.414L9 12.586V5a1 1 0 012 0v7.586l2.293-2.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
              </svg>
            <% end %>
          </div>
        <% end %>
      </div>
      
      <!-- Amount -->
      <div class="mb-2">
        <span class="text-2xl font-semibold text-slate-900">
          ₡<%= number_with_delimiter(@metrics[period][:amount]) %>
        </span>
      </div>
      
      <!-- Hidden details on hover -->
      <div class="h-4">
        <p class="text-xs text-slate-500 opacity-0 group-hover:opacity-100 transition-opacity">
          <%= @metrics[period][:transaction_count] %> transacciones
        </p>
      </div>
    </div>
  <% end %>
</div>
```

### Tooltip Component for Progressive Disclosure
```erb
<!-- app/views/shared/_metric_tooltip.html.erb -->
<div class="metric-tooltip hidden" data-tooltip-target="content">
  <div class="bg-slate-900 text-white p-3 rounded-lg shadow-xl max-w-xs">
    <div class="space-y-2">
      <div class="flex justify-between">
        <span class="text-slate-300 text-xs">Transacciones:</span>
        <span class="font-medium text-sm"><%= @details[:transaction_count] %></span>
      </div>
      <div class="flex justify-between">
        <span class="text-slate-300 text-xs">Promedio:</span>
        <span class="font-medium text-sm">₡<%= number_with_delimiter(@details[:average]) %></span>
      </div>
      <div class="flex justify-between">
        <span class="text-slate-300 text-xs">Categorías:</span>
        <span class="font-medium text-sm"><%= @details[:category_count] %></span>
      </div>
      <% if @details[:budget_progress] %>
        <div class="pt-2 border-t border-slate-700">
          <div class="flex justify-between">
            <span class="text-slate-300 text-xs">Presupuesto:</span>
            <span class="font-medium text-sm"><%= @details[:budget_progress] %>%</span>
          </div>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

## Story 3: Consolidate Merchant Information

### Before State (Separate Sections)
```
┌────────────────────────────────────────────────────────────┐
│ Top Merchants Section                                      │
│ ┌────────────────────────────────────────────────────┐    │
│ │ 1. Automercado         ₡234,567  (23 transactions) │    │
│ │ 2. Walmart             ₡189,234  (18 transactions) │    │
│ │ 3. Fresh Market        ₡156,789  (15 transactions) │    │
│ │ 4. Amazon              ₡134,567  (42 transactions) │    │
│ │ 5. Uber                ₡98,765   (67 transactions) │    │
│ └────────────────────────────────────────────────────┘    │
│                                                             │
│ Recent Expenses Section                                    │
│ ┌────────────────────────────────────────────────────┐    │
│ │ Date     Merchant        Category    Amount        │    │
│ │ 15/01    Automercado     Food        ₡45,678       │    │
│ │ 15/01    Uber            Transport   ₡3,456        │    │
│ │ 14/01    Walmart         Shopping    ₡67,890       │    │
│ └────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────┘
```

### After State (Consolidated View)
```
┌────────────────────────────────────────────────────────────┐
│ Actividad Reciente                    [Quick filters: #1 #2 #3] │
│ ┌────────────────────────────────────────────────────┐    │
│ │ [Food] Automercado #1          15/01    ₡45,678    │    │
│ │        └─ 23x este mes • Total: ₡234,567           │    │
│ │                                                      │    │
│ │ [Transport] Uber #5             15/01    ₡3,456     │    │
│ │             └─ 67x este mes • Total: ₡98,765       │    │
│ │                                                      │    │
│ │ [Shopping] Walmart #2           14/01    ₡67,890    │    │
│ │            └─ 18x este mes • Total: ₡189,234       │    │
│ └────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────┘
```

### ERB Implementation
```erb
<!-- app/views/expenses/_consolidated_expenses.html.erb -->
<div class="bg-white rounded-xl shadow-sm">
  <!-- Header with Quick Filters -->
  <div class="px-6 py-4 border-b border-slate-200">
    <div class="flex items-center justify-between">
      <h2 class="text-lg font-semibold text-slate-900">Actividad Reciente</h2>
      
      <!-- Top Merchant Quick Filters -->
      <div class="flex items-center space-x-2">
        <span class="text-xs text-slate-500 mr-2">Filtros rápidos:</span>
        <% @top_merchants.first(3).each_with_index do |(merchant, data), index| %>
          <button class="inline-flex items-center px-2.5 py-1 text-xs font-medium rounded-full
                         transition-all duration-200 border
                         <%= index == 0 ? 'bg-amber-50 text-amber-700 border-amber-200' : 
                             index == 1 ? 'bg-slate-50 text-slate-700 border-slate-200' :
                             'bg-orange-50 text-orange-700 border-orange-200' %>"
                  data-action="click->expense-filter#toggleMerchant"
                  data-merchant="<%= merchant %>">
            <span class="font-bold mr-1">#<%= index + 1 %></span>
            <%= merchant.truncate(12) %>
            <span class="ml-1 text-[10px] opacity-75">(<%= data[:count] %>)</span>
          </button>
        <% end %>
        
        <%= link_to expenses_path, class: "text-teal-700 hover:text-teal-800 text-sm font-medium ml-3" do %>
          Ver todos →
        <% end %>
      </div>
    </div>
  </div>
  
  <!-- Expense List with Integrated Merchant Info -->
  <div class="divide-y divide-slate-100" data-controller="consolidated-expenses">
    <% @enhanced_expenses.each do |expense_data| %>
      <% expense = expense_data[:expense] %>
      <% merchant_info = expense_data[:merchant_info] %>
      
      <div class="group hover:bg-slate-50 transition-colors duration-150"
           data-expense-id="<%= expense.id %>"
           data-merchant-rank="<%= merchant_info[:rank] %>">
        
        <div class="px-6 py-4">
          <!-- Main Row -->
          <div class="flex items-start justify-between">
            <!-- Left Section: Category + Merchant + Details -->
            <div class="flex items-start space-x-4 flex-1">
              <!-- Category Badge -->
              <div class="flex-shrink-0 mt-0.5">
                <div class="w-10 h-10 rounded-lg flex items-center justify-center
                            bg-<%= expense.category.color %>-100">
                  <span class="text-<%= expense.category.color %>-700 text-sm font-medium">
                    <%= expense.category.icon %>
                  </span>
                </div>
              </div>
              
              <!-- Merchant and Transaction Details -->
              <div class="flex-1">
                <!-- Merchant Name with Rank Badge -->
                <div class="flex items-center space-x-2 mb-1">
                  <span class="font-medium text-slate-900">
                    <%= expense.merchant %>
                  </span>
                  
                  <!-- Merchant Rank Badge (if top 5) -->
                  <% if merchant_info[:rank] <= 5 %>
                    <span class="inline-flex items-center px-2 py-0.5 text-[10px] font-bold rounded-full
                                 <%= merchant_info[:rank] == 1 ? 'bg-amber-100 text-amber-700' :
                                     merchant_info[:rank] == 2 ? 'bg-slate-100 text-slate-700' :
                                     merchant_info[:rank] == 3 ? 'bg-orange-100 text-orange-700' :
                                     'bg-teal-50 text-teal-700' %>"
                          data-controller="merchant-stats"
                          data-merchant-stats-total-value="<%= merchant_info[:total_spent] %>"
                          data-merchant-stats-frequency-value="<%= merchant_info[:frequency] %>">
                      #<%= merchant_info[:rank] %>
                    </span>
                  <% end %>
                  
                  <!-- High Frequency Indicator -->
                  <% if merchant_info[:frequency] > 10 %>
                    <span class="text-[11px] text-slate-500">
                      <%= merchant_info[:frequency] %>x
                    </span>
                  <% end %>
                </div>
                
                <!-- Transaction Meta Info -->
                <div class="flex items-center space-x-3 text-sm text-slate-600">
                  <span><%= expense.date.strftime("%d/%m") %></span>
                  <span>•</span>
                  <span><%= expense.category.name %></span>
                  <span>•</span>
                  <span class="text-xs"><%= expense.email_account.name %></span>
                </div>
                
                <!-- Merchant Summary (Visible on Hover) -->
                <% if merchant_info[:is_top_merchant] %>
                  <div class="mt-1 text-xs text-slate-500 opacity-0 group-hover:opacity-100 
                              transition-opacity duration-200">
                    Total en <%= expense.merchant %>: 
                    <span class="font-medium text-slate-700">
                      ₡<%= number_with_delimiter(merchant_info[:total_spent]) %>
                    </span>
                    (<%= merchant_info[:frequency] %> compras)
                  </div>
                <% end %>
              </div>
            </div>
            
            <!-- Right Section: Amount -->
            <div class="text-right ml-4">
              <div class="font-semibold text-slate-900">
                ₡<%= number_with_delimiter(expense.amount) %>
              </div>
              
              <!-- Percentage of Total (for top merchants) -->
              <% if merchant_info[:is_top_merchant] %>
                <div class="text-xs text-slate-500 mt-1">
                  <%= ((expense.amount / merchant_info[:total_spent]) * 100).round %>% del total
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    <% end %>
  </div>
  
  <!-- Footer Summary -->
  <div class="px-6 py-3 bg-slate-50 rounded-b-xl">
    <div class="flex items-center justify-between text-xs text-slate-600">
      <div>
        <%= @enhanced_expenses.count %> transacciones • 
        <%= @unique_merchants_count %> comercios distintos
      </div>
      <%= link_to "Análisis detallado de comercios →", 
                  merchants_path, 
                  class: "text-teal-700 hover:text-teal-800 font-medium" %>
    </div>
  </div>
</div>
```

## Story 6: Clean Visual Hierarchy

### Complete Dashboard Layout
```erb
<!-- app/views/expenses/dashboard.html.erb (Final Simplified Version) -->
<div class="min-h-screen bg-slate-50">
  <!-- Simplified Header -->
  <div class="bg-white border-b border-slate-200">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-slate-900">Dashboard</h1>
        <div class="text-sm text-slate-600">
          <%= l(Date.current, format: :long) %>
        </div>
      </div>
    </div>
  </div>
  
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <!-- Level 1: Hero Metric (Maximum Prominence) -->
    <section class="mb-10" data-hierarchy="primary">
      <%= render 'expenses/primary_metric' %>
    </section>
    
    <!-- Level 2: Period Metrics (Moderate Prominence) -->
    <section class="mb-8" data-hierarchy="secondary">
      <%= render 'expenses/secondary_metrics' %>
    </section>
    
    <!-- Unified Sync Widget (Contextual) -->
    <section class="mb-8" data-hierarchy="contextual">
      <%= render 'expenses/unified_sync_widget' %>
    </section>
    
    <!-- Level 3: Supporting Information (Minimal Prominence) -->
    <section data-hierarchy="tertiary">
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
        <!-- Simplified Chart -->
        <div class="bg-white rounded-xl p-6">
          <h3 class="text-base font-semibold text-slate-900 mb-4">
            Tendencia Mensual
          </h3>
          <div class="h-64">
            <%= line_chart @monthly_trend, 
                colors: ["#0F766E"],
                library: { 
                  animation: { duration: 1000 },
                  scales: {
                    y: { grid: { display: false } },
                    x: { grid: { display: false } }
                  }
                } %>
          </div>
        </div>
        
        <!-- Consolidated Expenses -->
        <div>
          <%= render 'expenses/consolidated_expenses' %>
        </div>
      </div>
    </section>
  </div>
</div>
```

### Spacing and Typography System
```scss
// app/assets/stylesheets/dashboard_hierarchy.scss
.dashboard {
  // Typography Scale
  --text-xs: 0.75rem;    // 12px
  --text-sm: 0.875rem;   // 14px
  --text-base: 1rem;     // 16px
  --text-lg: 1.125rem;   // 18px
  --text-xl: 1.25rem;    // 20px
  --text-2xl: 1.5rem;    // 24px
  --text-3xl: 1.875rem;  // 30px
  --text-4xl: 2.25rem;   // 36px
  --text-5xl: 3rem;      // 48px
  --text-6xl: 3.75rem;   // 60px
  
  // Hierarchy Levels
  [data-hierarchy="primary"] {
    margin-bottom: var(--space-3xl);
    
    h1, h2 { 
      font-size: var(--text-5xl);
      font-weight: 700;
      line-height: 1;
    }
  }
  
  [data-hierarchy="secondary"] {
    margin-bottom: var(--space-2xl);
    
    h2, h3 {
      font-size: var(--text-2xl);
      font-weight: 600;
      line-height: 1.2;
    }
  }
  
  [data-hierarchy="tertiary"] {
    margin-bottom: var(--space-xl);
    
    h3, h4 {
      font-size: var(--text-base);
      font-weight: 600;
      line-height: 1.5;
    }
  }
  
  [data-hierarchy="contextual"] {
    margin-bottom: var(--space-xl);
    opacity: 0.95;
  }
}
```

## Mobile Responsive Specifications

### Breakpoint Strategy
```css
/* Mobile First Approach */
/* Base (Mobile): 320px - 639px */
/* Tablet: 640px - 1023px */
/* Desktop: 1024px+ */
/* Wide: 1280px+ */
```

### Mobile Layout Adaptations
```erb
<!-- Mobile-Optimized Primary Metric -->
<div class="bg-gradient-to-br from-teal-700 to-teal-800 rounded-2xl shadow-xl 
            p-6 sm:p-8 lg:p-10">
  <div class="text-center">
    <h2 class="text-xs sm:text-sm font-medium text-teal-100 uppercase tracking-wider mb-2 sm:mb-3">
      Total Anual
    </h2>
    <div class="mb-3 sm:mb-4">
      <span class="text-3xl sm:text-5xl lg:text-6xl font-bold text-white">
        ₡<%= number_with_delimiter(@total_amount) %>
      </span>
    </div>
  </div>
</div>

<!-- Mobile-Optimized Secondary Metrics -->
<div class="grid grid-cols-1 sm:grid-cols-3 gap-3 sm:gap-4">
  <!-- Stack vertically on mobile, horizontal on tablet+ -->
</div>

<!-- Mobile-Optimized Expense List -->
<div class="divide-y divide-slate-100">
  <div class="px-4 sm:px-6 py-3 sm:py-4">
    <!-- Simplified layout for mobile -->
    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between">
      <div class="mb-2 sm:mb-0">
        <!-- Merchant and category -->
      </div>
      <div class="text-right">
        <!-- Amount -->
      </div>
    </div>
  </div>
</div>
```

## Accessibility Specifications

### ARIA Labels and Roles
```erb
<!-- Accessible Sync Widget -->
<div role="region" aria-label="Sincronización de correos">
  <div role="progressbar" 
       aria-valuenow="<%= @progress %>" 
       aria-valuemin="0" 
       aria-valuemax="100"
       aria-label="Progreso de sincronización">
    <!-- Progress bar -->
  </div>
</div>

<!-- Accessible Metric Cards -->
<article role="article" aria-label="Métricas del período">
  <h2 id="metric-label">Total Mensual</h2>
  <div aria-labelledby="metric-label" aria-describedby="metric-trend">
    <span class="sr-only">Cantidad:</span>
    ₡123,456
  </div>
  <div id="metric-trend" class="sr-only">
    Tendencia: Incremento respecto al período anterior
  </div>
</article>

<!-- Keyboard Navigation -->
<button tabindex="0" 
        aria-expanded="false"
        aria-controls="merchant-details"
        data-action="keydown.enter->merchant#toggleDetails 
                     keydown.space->merchant#toggleDetails">
  Ver detalles del comercio
</button>
```

### Color Contrast Requirements
```css
/* Ensure WCAG AA compliance */
.text-on-teal-700 { color: white; } /* 4.54:1 contrast ratio */
.text-on-white { color: #475569; }  /* slate-600, 7.07:1 ratio */
.text-muted { color: #64748b; }     /* slate-500, 4.6:1 ratio */

/* Never use these combinations */
/* .text-teal-700 on .bg-teal-100 - Insufficient contrast */
/* .text-slate-400 on .bg-white - Below AA standard */
```

### Screen Reader Optimizations
```erb
<!-- Provide context for dynamic content -->
<div aria-live="polite" aria-atomic="true">
  <span class="sr-only">
    Sincronización completada. <%= @detected_expenses %> gastos detectados.
  </span>
</div>

<!-- Hidden but accessible content -->
<span class="sr-only">Comercio frecuente, posición número <%= merchant_info[:rank] %></span>

<!-- Skip navigation -->
<a href="#main-content" class="sr-only focus:not-sr-only focus:absolute focus:top-4 focus:left-4 
                                bg-teal-700 text-white px-4 py-2 rounded">
  Saltar al contenido principal
</a>
```

## Animation and Transition Specifications

### Micro-Interactions
```javascript
// app/javascript/controllers/dashboard_animations_controller.js
export default class extends Controller {
  static values = { duration: Number }
  
  connect() {
    // Stagger animations for visual hierarchy
    this.animateHierarchy()
  }
  
  animateHierarchy() {
    // Primary elements appear first
    this.animateElements('[data-hierarchy="primary"]', 0)
    // Secondary elements follow
    this.animateElements('[data-hierarchy="secondary"]', 200)
    // Tertiary elements last
    this.animateElements('[data-hierarchy="tertiary"]', 400)
  }
  
  animateElements(selector, delay) {
    const elements = document.querySelectorAll(selector)
    elements.forEach((el, index) => {
      setTimeout(() => {
        el.style.opacity = '0'
        el.style.transform = 'translateY(20px)'
        
        requestAnimationFrame(() => {
          el.style.transition = 'opacity 0.6s ease-out, transform 0.6s ease-out'
          el.style.opacity = '1'
          el.style.transform = 'translateY(0)'
        })
      }, delay + (index * 100))
    })
  }
}
```

### CSS Transitions
```css
/* Smooth transitions for interactive elements */
.card {
  transition: box-shadow 0.2s ease-in-out, 
              transform 0.2s ease-in-out;
}

.card:hover {
  box-shadow: 0 10px 15px -3px rgb(0 0 0 / 0.1);
  transform: translateY(-2px);
}

/* Progress bar animations */
.progress-bar {
  transition: width 0.5s cubic-bezier(0.4, 0, 0.2, 1);
}

/* Skeleton loading states */
@keyframes shimmer {
  0% { background-position: -1000px 0; }
  100% { background-position: 1000px 0; }
}

.skeleton {
  background: linear-gradient(
    90deg,
    #f0f0f0 25%,
    #e0e0e0 50%,
    #f0f0f0 75%
  );
  background-size: 1000px 100%;
  animation: shimmer 2s infinite;
}
```

## Performance Optimizations

### Lazy Loading Strategy
```erb
<!-- Lazy load non-critical sections -->
<%= turbo_frame_tag "recent_expenses", 
                    src: recent_expenses_path, 
                    loading: "lazy",
                    class: "min-h-[400px]" do %>
  <!-- Loading skeleton -->
  <div class="animate-pulse">
    <div class="h-4 bg-slate-200 rounded w-3/4 mb-4"></div>
    <div class="h-4 bg-slate-200 rounded w-1/2"></div>
  </div>
<% end %>
```

### Critical CSS Inlining
```erb
<!-- app/views/layouts/application.html.erb -->
<style>
  /* Critical above-the-fold styles */
  .dashboard { background: #f8fafc; }
  .hero-metric { 
    background: linear-gradient(135deg, #0F766E 0%, #115E59 100%);
    border-radius: 1rem;
    padding: 2rem;
  }
  /* Prevent layout shift */
  .metric-card { min-height: 120px; }
</style>
```

## Component States

### Loading States
```erb
<!-- Loading state for sync widget -->
<div class="bg-white rounded-xl shadow-sm p-6 animate-pulse">
  <div class="h-4 bg-slate-200 rounded w-1/4 mb-4"></div>
  <div class="h-2 bg-slate-200 rounded mb-2"></div>
  <div class="grid grid-cols-3 gap-2">
    <div class="h-10 bg-slate-200 rounded"></div>
    <div class="h-10 bg-slate-200 rounded"></div>
    <div class="h-10 bg-slate-200 rounded"></div>
  </div>
</div>
```

### Empty States
```erb
<!-- Empty state for expenses -->
<div class="bg-white rounded-xl shadow-sm p-12 text-center">
  <svg class="mx-auto h-12 w-12 text-slate-400" fill="none" stroke="currentColor">
    <!-- Icon -->
  </svg>
  <h3 class="mt-4 text-base font-semibold text-slate-900">
    No hay gastos recientes
  </h3>
  <p class="mt-2 text-sm text-slate-600">
    Sincroniza tus cuentas de correo para detectar gastos automáticamente.
  </p>
  <button class="mt-4 bg-teal-700 text-white px-4 py-2 rounded-lg">
    Sincronizar Ahora
  </button>
</div>
```

### Error States
```erb
<!-- Error state for metric cards -->
<div class="bg-rose-50 border border-rose-200 rounded-xl p-6">
  <div class="flex items-start">
    <svg class="h-5 w-5 text-rose-600 mt-0.5" fill="currentColor">
      <!-- Error icon -->
    </svg>
    <div class="ml-3">
      <h3 class="text-sm font-medium text-rose-800">
        Error al cargar métricas
      </h3>
      <p class="mt-1 text-sm text-rose-700">
        No se pudieron cargar los datos. Por favor, intenta de nuevo.
      </p>
      <button class="mt-2 text-sm font-medium text-rose-800 hover:text-rose-900">
        Reintentar →
      </button>
    </div>
  </div>
</div>
```

## Implementation Checklist

### Phase 1: Foundation (Day 1-2)
- [ ] Implement spacing system variables
- [ ] Set up typography scale
- [ ] Configure Tailwind theme extensions
- [ ] Create base component structures

### Phase 2: Component Development (Day 3-4)
- [ ] Build unified sync widget
- [ ] Simplify metric cards
- [ ] Consolidate merchant displays
- [ ] Implement visual hierarchy

### Phase 3: Interactivity (Day 5-6)
- [ ] Add Stimulus controllers
- [ ] Implement tooltips
- [ ] Add animation sequences
- [ ] Set up lazy loading

### Phase 4: Polish (Day 7-8)
- [ ] Mobile optimization
- [ ] Accessibility audit
- [ ] Performance testing
- [ ] Cross-browser testing

### Phase 5: Deployment (Day 9-10)
- [ ] Feature flag setup
- [ ] A/B testing configuration
- [ ] Monitoring setup
- [ ] Documentation completion