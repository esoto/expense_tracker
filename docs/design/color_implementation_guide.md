# Financial Confidence Color Implementation Guide

## Color Palette

### Primary Colors
- **Primary (Teal)**: `teal-700` (#0F766E) - Main actions, navigation, primary buttons
- **Primary Light**: `teal-50` (#F0FDFA) - Backgrounds, hover states
- **Primary Medium**: `teal-100` (#CCFBF1) - Selected states, badges

### Secondary Colors
- **Secondary (Amber)**: `amber-600` (#D97706) - Important highlights, warnings
- **Secondary Light**: `amber-50` (#FFFBEB) - Warning backgrounds
- **Secondary Medium**: `amber-100` (#FEF3C7) - Category highlights

### Accent Colors
- **Accent (Rose)**: `rose-400` (#FB7185) - Attention, alerts, critical actions
- **Accent Light**: `rose-50` (#FFF1F2) - Error backgrounds
- **Accent Medium**: `rose-100` (#FFE4E6) - Soft alerts

### Neutral Colors
- **Text Primary**: `slate-900` (#0F172A)
- **Text Secondary**: `slate-600` (#475569)
- **Text Muted**: `slate-500` (#64748B)
- **Background**: `slate-50` (#F8FAFC)
- **Card Background**: `white` (#FFFFFF)
- **Borders**: `slate-200` (#E2E8F0)

## Implementation Steps

### 1. Update Navigation (app/views/layouts/application.html.erb)

```erb
<!-- Replace blue-600 with teal-700 -->
<div class="bg-teal-700 text-white p-2 rounded-lg shadow-sm">

<!-- Update active nav states -->
<%= link_to "Dashboard", dashboard_expenses_path, 
    class: "text-slate-600 hover:text-teal-700 px-3 py-2 rounded-md text-sm font-medium #{'bg-teal-50 text-teal-700' if request.path == dashboard_expenses_path}" %>

<!-- Primary button -->
<%= link_to "Nuevo Gasto", new_expense_path, 
    class: "bg-teal-700 hover:bg-teal-800 text-white px-4 py-2 rounded-lg text-sm font-medium shadow-sm" %>
```

### 2. Update Flash Messages

```erb
<!-- Success messages -->
<div class="bg-emerald-50 border border-emerald-200 text-emerald-700 px-4 py-3 rounded relative">

<!-- Error messages -->
<div class="bg-rose-50 border border-rose-200 text-rose-700 px-4 py-3 rounded relative">
```

### 3. Update Dashboard Cards

```erb
<!-- Card headers with icons -->
<div class="bg-teal-100 p-2 rounded-lg">
  <svg class="w-4 h-4 text-teal-700">

<!-- Metric increases -->
<p class="text-sm text-teal-600 font-medium mt-2">+12% vs mes anterior</p>

<!-- Metric decreases -->
<p class="text-sm text-rose-600 font-medium mt-2">-5% vs mes anterior</p>
```

### 4. Update Tables and Lists

```erb
<!-- Table headers -->
<thead class="bg-slate-50">

<!-- Hover states -->
<tr class="hover:bg-slate-50">

<!-- Category badges -->
<span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-teal-100 text-teal-800">
```

### 5. Update Form Elements

```erb
<!-- Input focus states -->
<%= form.text_field :amount, 
    class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500" %>

<!-- Primary submit button -->
<%= form.submit "Guardar", 
    class: "bg-teal-700 hover:bg-teal-800 text-white font-medium py-2 px-4 rounded-lg" %>

<!-- Secondary button -->
<%= link_to "Cancelar", expenses_path, 
    class: "bg-slate-200 hover:bg-slate-300 text-slate-700 font-medium py-2 px-4 rounded-lg" %>
```

### 6. Update Status Indicators

```erb
<!-- Success/Processed -->
<div class="bg-emerald-100 text-emerald-700">

<!-- Warning/Pending -->
<div class="bg-amber-100 text-amber-700">

<!-- Error/Failed -->
<div class="bg-rose-100 text-rose-700">

<!-- Info/Neutral -->
<div class="bg-slate-100 text-slate-700">
```

### 7. Category Color Updates

Update the Category model seeds to use colors that complement the new palette:

```ruby
# db/seeds.rb or migration
categories = [
  { name: "Supermercado", color: "#059669" },     # emerald-600
  { name: "Restaurantes", color: "#EA580C" },     # orange-600  
  { name: "Transporte", color: "#0891B2" },       # cyan-600
  { name: "Salud", color: "#DC2626" },            # red-600
  { name: "Entretenimiento", color: "#7C3AED" },  # violet-600
  { name: "Servicios", color: "#0F766E" },        # teal-700
  { name: "Educación", color: "#1E40AF" },        # blue-800
  { name: "Otros", color: "#64748B" }             # slate-500
]
```

## Component Examples

### Success Card
```erb
<div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
  <div class="flex items-center gap-2 mb-4">
    <div class="bg-emerald-100 p-2 rounded-lg">
      <svg class="w-5 h-5 text-emerald-600">...</svg>
    </div>
    <h3 class="font-semibold text-slate-900">Gastos Reducidos</h3>
  </div>
  <p class="text-2xl font-bold text-slate-900">-15%</p>
  <p class="text-sm text-emerald-600">Excelente progreso este mes</p>
</div>
```

### Warning Card
```erb
<div class="bg-amber-50 border border-amber-200 rounded-xl p-6">
  <div class="flex items-center gap-2 mb-4">
    <div class="bg-amber-100 p-2 rounded-lg">
      <svg class="w-5 h-5 text-amber-700">...</svg>
    </div>
    <h3 class="font-semibold text-amber-900">Presupuesto Cerca del Límite</h3>
  </div>
  <p class="text-sm text-amber-700">Has usado 85% de tu presupuesto mensual</p>
</div>
```

## Accessibility Checklist

- [ ] All text on teal-700 backgrounds uses white (contrast ratio: 4.52:1)
- [ ] All text on amber-600 backgrounds uses white (contrast ratio: 4.48:1)
- [ ] Rose-400 is only used for borders/icons, never text backgrounds
- [ ] Focus states have visible ring with sufficient contrast
- [ ] Error states use both color and icons
- [ ] Success states use both color and icons

## Testing the Implementation

1. Test all interactive elements for proper hover/focus states
2. Verify color contrast using browser dev tools
3. Check dark mode compatibility (future feature)
4. Test on different screen sizes for consistency
5. Get user feedback on the warmth/trust perception