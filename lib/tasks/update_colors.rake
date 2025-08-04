namespace :design do
  desc "Update application to use Financial Confidence color palette"
  task update_colors: :environment do
    puts "Updating category colors to match new palette..."

    # Update category colors to complement the teal/amber/rose palette
    category_updates = {
      "Supermercado" => "#059669",      # emerald-600
      "Restaurantes" => "#EA580C",       # orange-600
      "Transporte" => "#0891B2",         # cyan-600
      "Salud" => "#DC2626",              # red-600
      "Entretenimiento" => "#7C3AED",    # violet-600
      "Servicios" => "#0F766E",          # teal-700
      "Educación" => "#1E40AF",          # blue-800
      "Ropa y Accesorios" => "#DB2777",  # pink-600
      "Hogar" => "#CA8A04",              # amber-600
      "Tecnología" => "#4F46E5",         # indigo-600
      "Viajes" => "#0EA5E9",             # sky-500
      "Otros" => "#64748B"               # slate-500
    }

    category_updates.each do |name, color|
      category = Category.find_by(name: name)
      if category
        category.update!(color: color)
        puts "  ✓ Updated #{name} to #{color}"
      else
        puts "  ⚠ Category '#{name}' not found"
      end
    end

    puts "\nCategory colors updated successfully!"
    puts "\nNext steps:"
    puts "1. Update views with the new color classes (see docs/design/color_implementation_guide.md)"
    puts "2. Run 'bin/rails tailwindcss:build' to ensure all color classes are included"
    puts "3. Test the application to verify the new colors look good"
  end
end
