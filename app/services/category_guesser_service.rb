class CategoryGuesserService
  # Category keyword mappings for automatic categorization
  CATEGORY_KEYWORDS = {
    "Alimentación" => %w[restaurant restaurante comida food super supermercado grocery mercado],
    "Transporte" => %w[gasolina gas combustible uber taxi transporte],
    "Servicios" => %w[electricidad agua telefono internet cable servicio],
    "Entretenimiento" => %w[cine movie teatro entertainment entretenimiento],
    "Salud" => %w[farmacia medicina doctor hospital clinica salud],
    "Compras" => %w[tienda store compra shopping mall centro comercial]
  }.freeze

  # Default category names to try if no match found
  DEFAULT_CATEGORIES = [ "Sin Categoría", "Other" ].freeze

  def initialize
    # Service is stateless, no initialization needed
  end

  def guess_category_for_expense(expense)
    text = build_search_text(expense)
    find_matching_category(text) || find_default_category
  end

  def guess_category_from_text(description: nil, merchant_name: nil)
    text = build_search_text_from_parts(description, merchant_name)
    find_matching_category(text) || find_default_category
  end

  def available_categories
    CATEGORY_KEYWORDS.keys
  end

  def keywords_for_category(category_name)
    CATEGORY_KEYWORDS[category_name] || []
  end

  private

  def build_search_text(expense)
    return "" if expense.nil?

    parts = [ expense.description, expense.merchant_name ].compact
    parts.join(" ").downcase
  end

  def build_search_text_from_parts(description, merchant_name)
    parts = [ description, merchant_name ].compact
    parts.join(" ").downcase
  end

  def find_matching_category(text)
    return nil if text.blank?

    CATEGORY_KEYWORDS.each do |category_name, keywords|
      if keywords.any? { |keyword| text.include?(keyword) }
        return Category.find_by(name: category_name)
      end
    end

    nil
  end

  def find_default_category
    DEFAULT_CATEGORIES.each do |category_name|
      category = Category.find_by(name: category_name)
      return category if category
    end

    nil
  end
end
