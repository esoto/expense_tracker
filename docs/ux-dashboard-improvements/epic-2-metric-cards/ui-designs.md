# Epic 2: Enhanced Metric Cards - UI Designs

## Overview
Production-ready HTML/ERB mockups for enhanced metric cards with interactive features, budget indicators, and improved visual hierarchy.

---

## 1. Primary Metric Card (1.5x Size)

### Design Specifications
- **Size**: 1.5x larger than secondary cards
- **Background**: Gradient using teal colors
- **Animations**: Value changes with smooth transitions
- **Responsiveness**: Full width on mobile, prominent placement on desktop

### HTML/ERB Implementation

```erb
<!-- Primary Metric Card - Total de Gastos -->
<div class="col-span-1 md:col-span-2 lg:col-span-2">
  <div class="relative bg-gradient-to-br from-teal-700 to-teal-800 rounded-xl shadow-lg border border-teal-600 p-8 overflow-hidden group cursor-pointer"
       data-controller="metric-card"
       data-metric-card-url-value="<%= expenses_path(period: 'all') %>"
       data-metric-card-metric-type-value="total"
       data-action="click->metric-card#navigate">
    
    <!-- Background Pattern -->
    <div class="absolute inset-0 opacity-10">
      <svg class="w-full h-full" xmlns="http://www.w3.org/2000/svg">
        <pattern id="pattern-total" x="0" y="0" width="40" height="40" patternUnits="userSpaceOnUse">
          <circle cx="20" cy="20" r="2" fill="white" />
        </pattern>
        <rect x="0" y="0" width="100%" height="100%" fill="url(#pattern-total)" />
      </svg>
    </div>
    
    <!-- Content -->
    <div class="relative z-10">
      <!-- Header -->
      <div class="flex items-start justify-between mb-6">
        <div class="flex items-center">
          <div class="p-4 rounded-full bg-white/20 backdrop-blur-sm">
            <svg class="w-10 h-10 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                    d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1"></path>
            </svg>
          </div>
          <div class="ml-4">
            <h3 class="text-white/90 text-lg font-medium">Total de Gastos</h3>
            <p class="text-white/60 text-sm">Todos los tiempos</p>
          </div>
        </div>
        
        <!-- Interactive Tooltip Trigger -->
        <button class="p-2 rounded-lg bg-white/10 hover:bg-white/20 transition-colors"
                data-action="mouseenter->metric-card#showTooltip mouseleave->metric-card#hideTooltip"
                aria-label="Ver más información">
          <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                  d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
          </svg>
        </button>
      </div>
      
      <!-- Amount Display -->
      <div class="mb-6">
        <p class="text-5xl font-bold text-white mb-2"
           data-metric-card-target="value"
           data-action="animationend->metric-card#resetAnimation">
          ₡<%= number_with_delimiter(@total_expenses.to_i) %>
        </p>
        
        <!-- Comparison Indicator -->
        <div class="flex items-center space-x-2">
          <% change_percentage = calculate_change_percentage(@total_expenses, @previous_total) %>
          <% is_increase = change_percentage > 0 %>
          <div class="flex items-center px-3 py-1 rounded-full <%= is_increase ? 'bg-rose-500/20' : 'bg-emerald-500/20' %>">
            <svg class="w-4 h-4 <%= is_increase ? 'text-rose-300' : 'text-emerald-300' %> mr-1" 
                 fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                    d="<%= is_increase ? 'M5 15l7-7 7 7' : 'M19 9l-7 7-7-7' %>"></path>
            </svg>
            <span class="text-sm font-semibold <%= is_increase ? 'text-rose-300' : 'text-emerald-300' %>">
              <%= is_increase ? '+' : '' %><%= change_percentage %>%
            </span>
          </div>
          <span class="text-white/60 text-sm">vs. periodo anterior</span>
        </div>
      </div>
      
      <!-- Mini Sparkline Preview -->
      <div class="h-12 opacity-80" data-metric-card-target="sparkline">
        <svg class="w-full h-full" viewBox="0 0 200 40">
          <polyline
            fill="none"
            stroke="rgba(255,255,255,0.4)"
            stroke-width="2"
            points="<%= generate_sparkline_points(@weekly_totals) %>"
          />
          <polyline
            fill="url(#gradient-sparkline)"
            fill-opacity="0.2"
            stroke="none"
            points="<%= generate_sparkline_area(@weekly_totals) %>"
          />
          <defs>
            <linearGradient id="gradient-sparkline" x1="0%" y1="0%" x2="0%" y2="100%">
              <stop offset="0%" style="stop-color:white;stop-opacity:0.4" />
              <stop offset="100%" style="stop-color:white;stop-opacity:0" />
            </linearGradient>
          </defs>
        </svg>
      </div>
      
      <!-- Click Indicator -->
      <div class="absolute bottom-4 right-4 opacity-0 group-hover:opacity-100 transition-opacity">
        <svg class="w-5 h-5 text-white/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
        </svg>
      </div>
    </div>
    
    <!-- Loading State Overlay -->
    <div class="absolute inset-0 bg-teal-900/50 backdrop-blur-sm flex items-center justify-center rounded-xl hidden"
         data-metric-card-target="loadingOverlay">
      <svg class="animate-spin h-8 w-8 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
    </div>
  </div>
</div>
```

---

## 2. Secondary Metric Cards

### Design Specifications
- **Size**: Standard grid size
- **Background**: White with subtle hover effects
- **Icons**: Colored backgrounds matching metric type
- **Responsiveness**: Stack on mobile, grid on desktop

### HTML/ERB Implementation

```erb
<!-- Secondary Metric Cards Grid -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
  
  <!-- Este Mes Card -->
  <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 hover:shadow-md transition-all duration-200 cursor-pointer group"
       data-controller="metric-card"
       data-metric-card-url-value="<%= expenses_path(period: 'month') %>"
       data-metric-card-metric-type-value="month"
       data-action="click->metric-card#navigate">
    
    <div class="flex items-start justify-between mb-4">
      <div class="flex items-center">
        <div class="p-3 rounded-full bg-amber-100 group-hover:bg-amber-200 transition-colors">
          <svg class="w-6 h-6 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                  d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
          </svg>
        </div>
        <div class="ml-3">
          <p class="text-sm font-medium text-slate-600">Este Mes</p>
          <p class="text-xs text-slate-500"><%= l(Date.current, format: '%B %Y') %></p>
        </div>
      </div>
      
      <!-- Info Button -->
      <button class="opacity-0 group-hover:opacity-100 transition-opacity p-1"
              data-action="mouseenter->metric-card#showTooltip mouseleave->metric-card#hideTooltip click->metric-card#preventNavigation"
              aria-label="Ver detalles">
        <svg class="w-4 h-4 text-slate-400 hover:text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
      </button>
    </div>
    
    <!-- Value Display -->
    <div class="mb-4">
      <p class="text-2xl font-bold text-slate-900" data-metric-card-target="value">
        ₡<%= number_with_delimiter(@current_month_total.to_i) %>
      </p>
      
      <!-- Change Indicator -->
      <% month_change = calculate_change_percentage(@current_month_total, @last_month_total) %>
      <div class="flex items-center mt-2">
        <% if month_change != 0 %>
          <span class="text-xs font-medium <%= month_change > 0 ? 'text-rose-600' : 'text-emerald-600' %>">
            <%= month_change > 0 ? '↑' : '↓' %> <%= month_change.abs %>%
          </span>
          <span class="text-xs text-slate-500 ml-1">vs. mes anterior</span>
        <% else %>
          <span class="text-xs text-slate-500">Sin cambios</span>
        <% end %>
      </div>
    </div>
    
    <!-- Budget Progress Bar (if budget exists) -->
    <% if @monthly_budget %>
      <div class="space-y-2">
        <div class="flex justify-between items-center">
          <span class="text-xs text-slate-600">Presupuesto</span>
          <span class="text-xs font-medium text-slate-700">
            <%= budget_percentage(@current_month_total, @monthly_budget) %>%
          </span>
        </div>
        <div class="w-full bg-slate-200 rounded-full h-2">
          <div class="h-2 rounded-full transition-all duration-300 <%= budget_color_class(@current_month_total, @monthly_budget) %>"
               style="width: <%= [budget_percentage(@current_month_total, @monthly_budget), 100].min %>%"></div>
        </div>
        <p class="text-xs text-slate-600">
          ₡<%= number_with_delimiter(@monthly_budget.to_i) %> presupuestado
        </p>
      </div>
    <% else %>
      <!-- No Budget Set -->
      <div class="border-t border-slate-100 pt-3">
        <button class="text-xs text-teal-700 hover:text-teal-800 font-medium"
                data-action="click->metric-card#setBudget">
          Establecer presupuesto →
        </button>
      </div>
    <% end %>
    
    <!-- Hover Arrow -->
    <div class="absolute bottom-4 right-4 opacity-0 group-hover:opacity-100 transition-opacity">
      <svg class="w-4 h-4 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
      </svg>
    </div>
  </div>
  
  <!-- Esta Semana Card -->
  <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 hover:shadow-md transition-all duration-200 cursor-pointer group"
       data-controller="metric-card"
       data-metric-card-url-value="<%= expenses_path(period: 'week') %>"
       data-metric-card-metric-type-value="week"
       data-action="click->metric-card#navigate">
    
    <div class="flex items-start justify-between mb-4">
      <div class="flex items-center">
        <div class="p-3 rounded-full bg-teal-100 group-hover:bg-teal-200 transition-colors">
          <svg class="w-6 h-6 text-teal-700" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                  d="M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 11h.01M12 11h.01M9 11h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z"></path>
          </svg>
        </div>
        <div class="ml-3">
          <p class="text-sm font-medium text-slate-600">Esta Semana</p>
          <p class="text-xs text-slate-500">Semana <%= Date.current.cweek %></p>
        </div>
      </div>
      
      <!-- Info Button -->
      <button class="opacity-0 group-hover:opacity-100 transition-opacity p-1"
              data-action="mouseenter->metric-card#showTooltip mouseleave->metric-card#hideTooltip click->metric-card#preventNavigation"
              aria-label="Ver detalles">
        <svg class="w-4 h-4 text-slate-400 hover:text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
      </button>
    </div>
    
    <!-- Value Display -->
    <div class="mb-4">
      <p class="text-2xl font-bold text-slate-900" data-metric-card-target="value">
        ₡<%= number_with_delimiter(@current_week_total.to_i) %>
      </p>
      
      <!-- Daily Average -->
      <div class="flex items-center mt-2">
        <span class="text-xs text-slate-500">
          Promedio diario: ₡<%= number_with_delimiter((@current_week_total / 7).to_i) %>
        </span>
      </div>
    </div>
    
    <!-- Weekly Budget Progress -->
    <% if @weekly_budget %>
      <div class="space-y-2">
        <div class="flex justify-between items-center">
          <span class="text-xs text-slate-600">Presupuesto semanal</span>
          <span class="text-xs font-medium text-slate-700">
            <%= budget_percentage(@current_week_total, @weekly_budget) %>%
          </span>
        </div>
        <div class="w-full bg-slate-200 rounded-full h-2">
          <div class="h-2 rounded-full transition-all duration-300 <%= budget_color_class(@current_week_total, @weekly_budget) %>"
               style="width: <%= [budget_percentage(@current_week_total, @weekly_budget), 100].min %>%"></div>
        </div>
      </div>
    <% end %>
  </div>
  
  <!-- Hoy Card -->
  <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 hover:shadow-md transition-all duration-200 cursor-pointer group"
       data-controller="metric-card"
       data-metric-card-url-value="<%= expenses_path(period: 'today') %>"
       data-metric-card-metric-type-value="today"
       data-action="click->metric-card#navigate">
    
    <div class="flex items-start justify-between mb-4">
      <div class="flex items-center">
        <div class="p-3 rounded-full bg-emerald-100 group-hover:bg-emerald-200 transition-colors">
          <svg class="w-6 h-6 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                  d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
          </svg>
        </div>
        <div class="ml-3">
          <p class="text-sm font-medium text-slate-600">Hoy</p>
          <p class="text-xs text-slate-500"><%= l(Date.current, format: '%d de %B') %></p>
        </div>
      </div>
      
      <!-- Info Button -->
      <button class="opacity-0 group-hover:opacity-100 transition-opacity p-1"
              data-action="mouseenter->metric-card#showTooltip mouseleave->metric-card#hideTooltip click->metric-card#preventNavigation"
              aria-label="Ver detalles">
        <svg class="w-4 h-4 text-slate-400 hover:text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
      </button>
    </div>
    
    <!-- Value Display -->
    <div class="mb-4">
      <p class="text-2xl font-bold text-slate-900" data-metric-card-target="value">
        ₡<%= number_with_delimiter(@today_total.to_i) %>
      </p>
      
      <!-- Transaction Count -->
      <div class="flex items-center mt-2">
        <span class="text-xs text-slate-500">
          <%= @today_count %> <%= @today_count == 1 ? 'transacción' : 'transacciones' %>
        </span>
      </div>
    </div>
    
    <!-- Daily Budget Progress -->
    <% if @daily_budget %>
      <div class="space-y-2">
        <div class="flex justify-between items-center">
          <span class="text-xs text-slate-600">Límite diario</span>
          <span class="text-xs font-medium <%= @today_total > @daily_budget ? 'text-rose-600' : 'text-slate-700' %>">
            <%= budget_percentage(@today_total, @daily_budget) %>%
          </span>
        </div>
        <div class="w-full bg-slate-200 rounded-full h-2">
          <div class="h-2 rounded-full transition-all duration-300 <%= budget_color_class(@today_total, @daily_budget) %>"
               style="width: <%= [budget_percentage(@today_total, @daily_budget), 100].min %>%"></div>
        </div>
      </div>
    <% end %>
  </div>
</div>
```

---

## 3. Interactive Tooltip Component

### Design Specifications
- **Trigger**: Hover on info icon or long press on mobile
- **Content**: 7-day sparkline, category breakdown, statistics
- **Position**: Smart positioning to avoid viewport edges
- **Animation**: Smooth fade in/out

### HTML/ERB Implementation

```erb
<!-- Interactive Tooltip (rendered dynamically) -->
<div class="absolute z-50 hidden"
     data-metric-card-target="tooltip"
     data-controller="tooltip"
     data-tooltip-placement-value="top">
  
  <div class="bg-slate-900 text-white rounded-lg shadow-xl p-4 w-80 transform transition-all duration-200"
       data-tooltip-target="content">
    
    <!-- Arrow -->
    <div class="absolute -bottom-2 left-1/2 transform -translate-x-1/2">
      <div class="w-0 h-0 border-l-8 border-r-8 border-t-8 border-l-transparent border-r-transparent border-t-slate-900"></div>
    </div>
    
    <!-- Header -->
    <div class="flex items-center justify-between mb-3 pb-3 border-b border-slate-700">
      <h4 class="font-semibold text-sm">Últimos 7 días</h4>
      <button class="text-slate-400 hover:text-white transition-colors"
              data-action="click->tooltip#close">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
        </svg>
      </button>
    </div>
    
    <!-- Sparkline Chart -->
    <div class="mb-4">
      <div class="h-20 relative">
        <svg class="w-full h-full" viewBox="0 0 280 80">
          <!-- Grid Lines -->
          <g stroke="rgba(255,255,255,0.1)" stroke-width="0.5">
            <line x1="0" y1="20" x2="280" y2="20" />
            <line x1="0" y1="40" x2="280" y2="40" />
            <line x1="0" y1="60" x2="280" y2="60" />
          </g>
          
          <!-- Data Points and Line -->
          <polyline
            fill="none"
            stroke="#10B981"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            points="<%= @tooltip_sparkline_points %>"
          />
          
          <!-- Data Points Circles -->
          <% @tooltip_data_points.each do |point| %>
            <circle cx="<%= point[:x] %>" cy="<%= point[:y] %>" r="3" fill="#10B981" />
            <circle cx="<%= point[:x] %>" cy="<%= point[:y] %>" r="5" fill="rgba(16, 185, 129, 0.3)" />
          <% end %>
          
          <!-- Area Fill -->
          <polyline
            fill="url(#tooltip-gradient)"
            fill-opacity="0.3"
            points="<%= @tooltip_sparkline_area %>"
          />
          
          <defs>
            <linearGradient id="tooltip-gradient" x1="0%" y1="0%" x2="0%" y2="100%">
              <stop offset="0%" style="stop-color:#10B981;stop-opacity:0.3" />
              <stop offset="100%" style="stop-color:#10B981;stop-opacity:0" />
            </linearGradient>
          </defs>
        </svg>
      </div>
      
      <!-- Day Labels -->
      <div class="flex justify-between mt-2 text-xs text-slate-400">
        <% @last_7_days.each do |day| %>
          <span><%= day.strftime('%a') %></span>
        <% end %>
      </div>
    </div>
    
    <!-- Statistics Grid -->
    <div class="grid grid-cols-3 gap-3 mb-4">
      <div class="text-center">
        <p class="text-xs text-slate-400 mb-1">Mínimo</p>
        <p class="text-sm font-semibold">₡<%= number_with_delimiter(@min_daily.to_i) %></p>
      </div>
      <div class="text-center border-x border-slate-700">
        <p class="text-xs text-slate-400 mb-1">Promedio</p>
        <p class="text-sm font-semibold">₡<%= number_with_delimiter(@avg_daily.to_i) %></p>
      </div>
      <div class="text-center">
        <p class="text-xs text-slate-400 mb-1">Máximo</p>
        <p class="text-sm font-semibold">₡<%= number_with_delimiter(@max_daily.to_i) %></p>
      </div>
    </div>
    
    <!-- Category Breakdown -->
    <div class="space-y-2">
      <h5 class="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-2">Top Categorías</h5>
      <% @top_categories_week.first(3).each do |category, amount| %>
        <div class="flex items-center justify-between">
          <div class="flex items-center">
            <div class="w-3 h-3 rounded-full mr-2" style="background-color: <%= category.color %>"></div>
            <span class="text-xs text-slate-300"><%= category.name %></span>
          </div>
          <span class="text-xs font-medium">₡<%= number_with_delimiter(amount.to_i) %></span>
        </div>
      <% end %>
    </div>
    
    <!-- Footer Action -->
    <div class="mt-4 pt-3 border-t border-slate-700">
      <a href="<%= analytics_expenses_path %>" 
         class="text-xs text-teal-400 hover:text-teal-300 font-medium">
        Ver análisis completo →
      </a>
    </div>
  </div>
</div>
```

---

## 4. Budget Progress Indicators

### Design Specifications
- **Visual**: Progress bar with color coding
- **States**: Under budget (green), warning (yellow), over budget (red)
- **Interaction**: Click to set/edit budget

### HTML/ERB Implementation

```erb
<!-- Budget Progress Component -->
<div class="budget-progress" data-controller="budget-progress">
  
  <!-- Budget Set State -->
  <% if budget_amount > 0 %>
    <div class="space-y-3">
      <!-- Progress Header -->
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-2">
          <span class="text-sm font-medium text-slate-700">Presupuesto <%= period_label %></span>
          <button class="text-slate-400 hover:text-slate-600 transition-colors"
                  data-action="click->budget-progress#edit"
                  aria-label="Editar presupuesto">
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                    d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"></path>
            </svg>
          </button>
        </div>
        <div class="text-right">
          <span class="text-sm font-bold <%= budget_status_color(spent, budget_amount) %>">
            <%= budget_percentage(spent, budget_amount) %>%
          </span>
        </div>
      </div>
      
      <!-- Progress Bar -->
      <div class="relative">
        <div class="w-full bg-slate-200 rounded-full h-3 overflow-hidden">
          <div class="h-full rounded-full transition-all duration-500 ease-out relative <%= budget_bar_class(spent, budget_amount) %>"
               style="width: <%= [budget_percentage(spent, budget_amount), 100].min %>%"
               data-budget-progress-target="bar">
            
            <!-- Animated Stripes for Over Budget -->
            <% if spent > budget_amount %>
              <div class="absolute inset-0 opacity-30">
                <div class="h-full w-full bg-stripes animate-move-stripes"></div>
              </div>
            <% end %>
          </div>
        </div>
        
        <!-- Milestone Markers -->
        <div class="absolute top-0 left-0 w-full h-3 pointer-events-none">
          <div class="absolute top-0 bottom-0 w-px bg-amber-500 opacity-50" style="left: 70%"></div>
          <div class="absolute top-0 bottom-0 w-px bg-rose-500 opacity-50" style="left: 90%"></div>
        </div>
      </div>
      
      <!-- Budget Details -->
      <div class="flex items-center justify-between text-xs">
        <div class="flex items-center space-x-3">
          <span class="text-slate-600">
            Gastado: <span class="font-semibold text-slate-900">₡<%= number_with_delimiter(spent.to_i) %></span>
          </span>
          <span class="text-slate-400">•</span>
          <span class="text-slate-600">
            Presupuesto: <span class="font-semibold">₡<%= number_with_delimiter(budget_amount.to_i) %></span>
          </span>
        </div>
        <div>
          <% remaining = budget_amount - spent %>
          <% if remaining > 0 %>
            <span class="text-emerald-600 font-medium">
              ₡<%= number_with_delimiter(remaining.to_i) %> disponible
            </span>
          <% else %>
            <span class="text-rose-600 font-medium">
              ₡<%= number_with_delimiter(remaining.abs.to_i) %> excedido
            </span>
          <% end %>
        </div>
      </div>
      
      <!-- Status Message -->
      <div class="mt-2">
        <% if spent < budget_amount * 0.7 %>
          <p class="text-xs text-emerald-600 flex items-center">
            <svg class="w-3.5 h-3.5 mr-1" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"></path>
            </svg>
            Vas bien con tu presupuesto
          </p>
        <% elsif spent < budget_amount * 0.9 %>
          <p class="text-xs text-amber-600 flex items-center">
            <svg class="w-3.5 h-3.5 mr-1" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path>
            </svg>
            Te acercas al límite del presupuesto
          </p>
        <% else %>
          <p class="text-xs text-rose-600 flex items-center">
            <svg class="w-3.5 h-3.5 mr-1" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"></path>
            </svg>
            Has excedido tu presupuesto
          </p>
        <% end %>
      </div>
    </div>
    
  <% else %>
    <!-- No Budget Set State -->
    <div class="bg-slate-50 rounded-lg p-4 border border-slate-200">
      <div class="flex items-start space-x-3">
        <div class="flex-shrink-0">
          <svg class="w-5 h-5 text-amber-500 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path>
          </svg>
        </div>
        <div class="flex-1">
          <h4 class="text-sm font-medium text-slate-900 mb-1">
            Sin presupuesto definido
          </h4>
          <p class="text-xs text-slate-600 mb-3">
            Establece un presupuesto para controlar mejor tus gastos
          </p>
          <button class="inline-flex items-center px-3 py-1.5 bg-teal-700 hover:bg-teal-800 text-white text-xs font-medium rounded-lg transition-colors"
                  data-action="click->budget-progress#create">
            <svg class="w-3.5 h-3.5 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path>
            </svg>
            Establecer presupuesto
          </button>
        </div>
      </div>
    </div>
  <% end %>
</div>
```

---

## 5. Loading States

### Design Specifications
- **Skeleton**: Animated placeholders matching card layouts
- **Shimmer**: Subtle animation effect
- **Error States**: Clear messaging with retry options

### HTML/ERB Implementation

```erb
<!-- Loading State for Metric Cards -->
<div class="animate-pulse">
  <!-- Primary Card Skeleton -->
  <div class="col-span-1 md:col-span-2 lg:col-span-2">
    <div class="bg-slate-200 rounded-xl p-8 h-64">
      <div class="flex items-start justify-between mb-6">
        <div class="flex items-center">
          <div class="w-16 h-16 bg-slate-300 rounded-full"></div>
          <div class="ml-4 space-y-2">
            <div class="h-4 w-24 bg-slate-300 rounded"></div>
            <div class="h-3 w-16 bg-slate-300 rounded"></div>
          </div>
        </div>
      </div>
      <div class="space-y-3">
        <div class="h-10 w-48 bg-slate-300 rounded"></div>
        <div class="h-4 w-32 bg-slate-300 rounded"></div>
      </div>
    </div>
  </div>
  
  <!-- Secondary Cards Skeleton -->
  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
    <% 3.times do %>
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div class="flex items-start justify-between mb-4">
          <div class="flex items-center">
            <div class="w-12 h-12 bg-slate-200 rounded-full"></div>
            <div class="ml-3 space-y-2">
              <div class="h-3 w-16 bg-slate-200 rounded"></div>
              <div class="h-2 w-12 bg-slate-200 rounded"></div>
            </div>
          </div>
        </div>
        <div class="space-y-3">
          <div class="h-7 w-32 bg-slate-200 rounded"></div>
          <div class="h-2 w-full bg-slate-200 rounded-full"></div>
          <div class="h-2 w-20 bg-slate-200 rounded"></div>
        </div>
      </div>
    <% end %>
  </div>
</div>

<!-- Error State -->
<div class="bg-rose-50 border border-rose-200 rounded-xl p-6 hidden" data-metric-card-target="errorState">
  <div class="flex items-start space-x-3">
    <div class="flex-shrink-0">
      <svg class="w-6 h-6 text-rose-600" fill="currentColor" viewBox="0 0 20 20">
        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"></path>
      </svg>
    </div>
    <div class="flex-1">
      <h3 class="text-sm font-medium text-rose-900">
        Error al cargar las métricas
      </h3>
      <p class="text-sm text-rose-700 mt-1" data-metric-card-target="errorMessage">
        No se pudieron cargar los datos. Por favor, intenta nuevamente.
      </p>
      <button class="mt-3 text-sm font-medium text-rose-900 hover:text-rose-800"
              data-action="click->metric-card#retry">
        Reintentar →
      </button>
    </div>
  </div>
</div>

<!-- Empty State -->
<div class="text-center py-12 hidden" data-metric-card-target="emptyState">
  <svg class="mx-auto h-12 w-12 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
          d="M9 13h6m-3-3v6m5 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
  </svg>
  <h3 class="mt-4 text-sm font-medium text-slate-900">No hay datos disponibles</h3>
  <p class="mt-2 text-sm text-slate-600">
    Comienza agregando tus primeros gastos para ver las métricas.
  </p>
  <div class="mt-6">
    <%= link_to new_expense_path, 
        class: "inline-flex items-center px-4 py-2 bg-teal-700 hover:bg-teal-800 text-white text-sm font-medium rounded-lg transition-colors" do %>
      <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path>
      </svg>
      Agregar gasto
    <% end %>
  </div>
</div>
```

---

## 6. Stimulus Controller

### JavaScript Implementation

```javascript
// app/javascript/controllers/metric_card_controller.js
import { Controller } from "@hotwired/stimulus"
import { get } from "@rails/request.js"

export default class extends Controller {
  static targets = [ 
    "value", 
    "sparkline", 
    "tooltip", 
    "loadingOverlay",
    "progressBar",
    "errorState",
    "emptyState"
  ]
  
  static values = { 
    url: String,
    metricType: String,
    sessionId: Number
  }
  
  connect() {
    this.setupAnimations()
    this.loadSparklineData()
  }
  
  navigate(event) {
    // Don't navigate if clicking on tooltip trigger
    if (event.target.closest('[data-action*="showTooltip"]')) {
      return
    }
    
    this.showLoading()
    
    // Update URL with filters
    const url = new URL(this.urlValue, window.location.origin)
    Turbo.visit(url, { action: "replace" })
  }
  
  async showTooltip(event) {
    event.stopPropagation()
    
    if (!this.hasTooltipTarget) return
    
    // Load tooltip data
    const response = await get(`/api/metrics/${this.metricTypeValue}/tooltip`, {
      responseKind: "json"
    })
    
    if (response.ok) {
      const data = await response.json
      this.updateTooltipContent(data)
      this.positionTooltip(event.currentTarget)
      this.tooltipTarget.classList.remove("hidden")
    }
  }
  
  hideTooltip() {
    if (this.hasTooltipTarget) {
      this.tooltipTarget.classList.add("hidden")
    }
  }
  
  preventNavigation(event) {
    event.stopPropagation()
  }
  
  setBudget(event) {
    event.stopPropagation()
    // Open budget modal
    this.dispatch("openBudgetModal", { 
      detail: { metricType: this.metricTypeValue } 
    })
  }
  
  async loadSparklineData() {
    if (!this.hasSparklineTarget) return
    
    try {
      const response = await get(`/api/metrics/${this.metricTypeValue}/sparkline`, {
        responseKind: "json"
      })
      
      if (response.ok) {
        const data = await response.json
        this.updateSparkline(data.points)
      }
    } catch (error) {
      console.error("Failed to load sparkline:", error)
    }
  }
  
  updateSparkline(points) {
    if (!this.hasSparklineTarget) return
    
    // Animate sparkline drawing
    const polyline = this.sparklineTarget.querySelector("polyline")
    if (polyline) {
      polyline.style.strokeDasharray = polyline.getTotalLength()
      polyline.style.strokeDashoffset = polyline.getTotalLength()
      
      requestAnimationFrame(() => {
        polyline.style.transition = "stroke-dashoffset 1s ease-out"
        polyline.style.strokeDashoffset = "0"
      })
    }
  }
  
  positionTooltip(trigger) {
    const rect = trigger.getBoundingClientRect()
    const tooltip = this.tooltipTarget
    const tooltipRect = tooltip.getBoundingClientRect()
    
    // Calculate position
    let top = rect.top - tooltipRect.height - 10
    let left = rect.left + (rect.width / 2) - (tooltipRect.width / 2)
    
    // Adjust if tooltip goes off screen
    if (top < 10) {
      top = rect.bottom + 10
      tooltip.dataset.placement = "bottom"
    }
    
    if (left < 10) {
      left = 10
    } else if (left + tooltipRect.width > window.innerWidth - 10) {
      left = window.innerWidth - tooltipRect.width - 10
    }
    
    tooltip.style.top = `${top}px`
    tooltip.style.left = `${left}px`
  }
  
  setupAnimations() {
    // Animate value changes
    if (this.hasValueTarget) {
      this.observeValueChanges()
    }
    
    // Animate progress bars
    if (this.hasProgressBarTarget) {
      this.animateProgressBar()
    }
  }
  
  observeValueChanges() {
    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.type === 'childList' || mutation.type === 'characterData') {
          this.animateValueChange()
        }
      })
    })
    
    observer.observe(this.valueTarget, {
      childList: true,
      characterData: true,
      subtree: true
    })
  }
  
  animateValueChange() {
    this.valueTarget.classList.add("animate-pulse-once")
  }
  
  resetAnimation(event) {
    event.target.classList.remove("animate-pulse-once")
  }
  
  animateProgressBar() {
    const width = this.progressBarTarget.style.width
    this.progressBarTarget.style.width = "0%"
    
    requestAnimationFrame(() => {
      this.progressBarTarget.style.transition = "width 1s ease-out"
      this.progressBarTarget.style.width = width
    })
  }
  
  showLoading() {
    if (this.hasLoadingOverlayTarget) {
      this.loadingOverlayTarget.classList.remove("hidden")
    }
  }
  
  hideLoading() {
    if (this.hasLoadingOverlayTarget) {
      this.loadingOverlayTarget.classList.add("hidden")
    }
  }
  
  async retry() {
    this.hideError()
    await this.loadSparklineData()
  }
  
  showError(message) {
    if (this.hasErrorStateTarget) {
      this.errorStateTarget.querySelector('[data-metric-card-target="errorMessage"]').textContent = message
      this.errorStateTarget.classList.remove("hidden")
    }
  }
  
  hideError() {
    if (this.hasErrorStateTarget) {
      this.errorStateTarget.classList.add("hidden")
    }
  }
}
```

---

## 7. Helper Methods

### Ruby Helper Methods

```ruby
# app/helpers/metrics_helper.rb
module MetricsHelper
  def calculate_change_percentage(current, previous)
    return 0 if previous.zero?
    ((current - previous) / previous * 100).round(1)
  end
  
  def budget_percentage(spent, budget)
    return 0 if budget.zero?
    ((spent / budget) * 100).round(1)
  end
  
  def budget_color_class(spent, budget)
    percentage = budget_percentage(spent, budget)
    
    case percentage
    when 0..70
      "bg-emerald-500"
    when 70..90
      "bg-amber-500"
    else
      "bg-rose-500"
    end
  end
  
  def budget_status_color(spent, budget)
    percentage = budget_percentage(spent, budget)
    
    case percentage
    when 0..70
      "text-emerald-600"
    when 70..90
      "text-amber-600"
    else
      "text-rose-600"
    end
  end
  
  def budget_bar_class(spent, budget)
    percentage = budget_percentage(spent, budget)
    
    case percentage
    when 0..70
      "bg-emerald-500"
    when 70..90
      "bg-amber-500 animate-pulse"
    else
      "bg-rose-500 animate-pulse"
    end
  end
  
  def generate_sparkline_points(data)
    return "" if data.empty?
    
    width = 200
    height = 40
    max_value = data.max || 1
    
    points = data.each_with_index.map do |value, index|
      x = (index.to_f / (data.length - 1)) * width
      y = height - ((value.to_f / max_value) * height)
      "#{x},#{y}"
    end
    
    points.join(" ")
  end
  
  def generate_sparkline_area(data)
    return "" if data.empty?
    
    points = generate_sparkline_points(data)
    "0,40 #{points} 200,40"
  end
end
```

---

## 8. CSS Styles

### Tailwind CSS Extensions

```css
/* app/assets/stylesheets/application.tailwind.css */

/* Animated stripes for over-budget state */
@keyframes move-stripes {
  0% {
    background-position: 0 0;
  }
  100% {
    background-position: 40px 0;
  }
}

.bg-stripes {
  background-image: repeating-linear-gradient(
    -45deg,
    transparent,
    transparent 10px,
    rgba(255, 255, 255, 0.1) 10px,
    rgba(255, 255, 255, 0.1) 20px
  );
}

.animate-move-stripes {
  animation: move-stripes 1s linear infinite;
}

/* Pulse animation for value changes */
@keyframes pulse-once {
  0%, 100% {
    transform: scale(1);
  }
  50% {
    transform: scale(1.05);
  }
}

.animate-pulse-once {
  animation: pulse-once 0.3s ease-in-out;
}

/* Smooth number transitions */
.transition-number {
  transition: all 0.3s ease-out;
}

/* Card hover effects */
.metric-card-hover {
  transition: all 0.2s ease-out;
}

.metric-card-hover:hover {
  transform: translateY(-2px);
}

/* Tooltip animations */
.tooltip-enter {
  animation: tooltip-enter 0.2s ease-out;
}

@keyframes tooltip-enter {
  from {
    opacity: 0;
    transform: translateY(4px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
```

---

## 9. Mobile Responsive Considerations

### Touch Interactions

```erb
<!-- Mobile-optimized metric card -->
<div class="bg-white rounded-xl shadow-sm border border-slate-200 p-4 sm:p-6"
     data-controller="metric-card"
     data-action="click->metric-card#navigate touchstart->metric-card#handleTouch">
  
  <!-- Mobile-friendly touch targets (minimum 44x44px) -->
  <button class="min-h-[44px] min-w-[44px] p-2 -m-2"
          data-action="click->metric-card#showTooltip">
    <!-- Icon content -->
  </button>
  
  <!-- Responsive text sizes -->
  <p class="text-xl sm:text-2xl md:text-3xl font-bold">
    ₡<%= number_with_delimiter(amount) %>
  </p>
  
  <!-- Stacked layout on mobile -->
  <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between">
    <!-- Content -->
  </div>
</div>
```

---

## 10. Accessibility Features

### ARIA Labels and Keyboard Navigation

```erb
<!-- Accessible metric card -->
<article class="metric-card"
         role="region"
         aria-label="<%= metric_label %>"
         tabindex="0"
         data-controller="metric-card"
         data-action="keydown.enter->metric-card#navigate keydown.space->metric-card#navigate">
  
  <!-- Screen reader announcements -->
  <div class="sr-only" aria-live="polite" aria-atomic="true" data-metric-card-target="announcement">
    <%= metric_label %>: <%= formatted_amount %>
  </div>
  
  <!-- Accessible buttons -->
  <button aria-label="Ver información detallada de <%= metric_label %>"
          aria-describedby="tooltip-<%= metric_id %>"
          data-action="click->metric-card#showTooltip">
    <!-- Icon -->
  </button>
  
  <!-- Accessible progress indicators -->
  <div role="progressbar"
       aria-valuemin="0"
       aria-valuemax="100"
       aria-valuenow="<%= percentage %>"
       aria-label="<%= percentage %>% del presupuesto usado">
    <!-- Progress bar visual -->
  </div>
</article>
```

---

## Implementation Notes

1. **Data Loading**: Use Turbo Frames for partial updates and Turbo Streams for real-time updates
2. **Performance**: Implement lazy loading for sparklines and tooltips
3. **Caching**: Cache metric calculations with Russian doll caching
4. **Testing**: Include Capybara tests for all interactive features
5. **Analytics**: Track metric card interactions for usage insights

## Browser Support

- Modern browsers with ES6 support
- Fallback for older browsers using progressive enhancement
- Touch event support for mobile devices
- Reduced motion preferences respected

## Dependencies

- Stimulus.js for interactivity
- Turbo for navigation
- Tailwind CSS for styling
- Chart.js (optional) for advanced charts
- @rails/request.js for AJAX requests