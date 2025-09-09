require 'rails_helper'

RSpec.describe CategoryGuesserService, integration: true do
  let(:service) { described_class.new }
  let(:expense) { instance_double(Expense, description: nil, merchant_name: nil) }

  before do
    # Create test categories
    create(:category, name: 'Alimentación')
    create(:category, name: 'Transporte')
    create(:category, name: 'Servicios')
    create(:category, name: 'Entretenimiento')
    create(:category, name: 'Salud')
    create(:category, name: 'Compras')
    create(:category, name: 'Sin Categoría')
    create(:category, name: 'Other')
  end

  describe '#initialize', integration: true do
    it 'creates service instance' do
      expect(service).to be_a(described_class)
    end
  end

  describe '#guess_category_for_expense', integration: true do
    context 'with Alimentación keywords' do
      it 'categorizes restaurant expenses' do
        allow(expense).to receive(:description).and_return('Dinner at RESTAURANT LA COCINA')
        allow(expense).to receive(:merchant_name).and_return('RESTAURANT')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Alimentación')
      end

      it 'categorizes supermarket expenses' do
        allow(expense).to receive(:description).and_return('Groceries')
        allow(expense).to receive(:merchant_name).and_return('SUPER WALMART')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Alimentación')
      end

      it 'categorizes with Spanish keywords' do
        allow(expense).to receive(:description).and_return('Compra de comida')
        allow(expense).to receive(:merchant_name).and_return('MERCADO CENTRAL')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Alimentación')
      end
    end

    context 'with Transporte keywords' do
      it 'categorizes gas station expenses' do
        allow(expense).to receive(:description).and_return('Fuel purchase')
        allow(expense).to receive(:merchant_name).and_return('GASOLINA SHELL')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Transporte')
      end

      it 'categorizes ride-sharing expenses' do
        allow(expense).to receive(:description).and_return('Trip payment')
        allow(expense).to receive(:merchant_name).and_return('UBER TECHNOLOGIES')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Transporte')
      end
    end

    context 'with Servicios keywords' do
      it 'categorizes utility expenses' do
        allow(expense).to receive(:description).and_return('Monthly bill')
        allow(expense).to receive(:merchant_name).and_return('ELECTRICIDAD ICE')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Servicios')
      end

      it 'categorizes internet expenses' do
        allow(expense).to receive(:description).and_return('Internet service')
        allow(expense).to receive(:merchant_name).and_return('CABLE COMPANY')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Servicios')
      end
    end

    context 'with Entretenimiento keywords' do
      it 'categorizes cinema expenses' do
        allow(expense).to receive(:description).and_return('Movie tickets')
        allow(expense).to receive(:merchant_name).and_return('CINE MULTIPLEX')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Entretenimiento')
      end

      it 'categorizes theater expenses' do
        allow(expense).to receive(:description).and_return('Show tickets')
        allow(expense).to receive(:merchant_name).and_return('TEATRO NACIONAL')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Entretenimiento')
      end
    end

    context 'with Salud keywords' do
      it 'categorizes pharmacy expenses' do
        allow(expense).to receive(:description).and_return('farmacia purchase')
        allow(expense).to receive(:merchant_name).and_return('MEDICAL CENTER')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Salud')
      end

      it 'categorizes hospital expenses' do
        allow(expense).to receive(:description).and_return('Medical consultation')
        allow(expense).to receive(:merchant_name).and_return('HOSPITAL CALDERON')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Salud')
      end
    end

    context 'with Compras keywords' do
      it 'categorizes store expenses' do
        allow(expense).to receive(:description).and_return('Shopping')
        allow(expense).to receive(:merchant_name).and_return('TIENDA LA CURACAO')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Compras')
      end

      it 'categorizes mall expenses' do
        allow(expense).to receive(:description).and_return('Purchase')
        allow(expense).to receive(:merchant_name).and_return('CENTRO COMERCIAL')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Compras')
      end
    end

    context 'with no matching keywords' do
      it 'returns default Sin Categoría category' do
        allow(expense).to receive(:description).and_return('Unknown transaction')
        allow(expense).to receive(:merchant_name).and_return('UNKNOWN MERCHANT')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Sin Categoría')
      end

      it 'returns Other category if Sin Categoría not found' do
        Category.find_by(name: 'Sin Categoría').destroy

        allow(expense).to receive(:description).and_return('Unknown transaction')
        allow(expense).to receive(:merchant_name).and_return('UNKNOWN MERCHANT')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Other')
      end

      it 'returns nil if no default categories exist' do
        Category.where(name: [ 'Sin Categoría', 'Other' ]).destroy_all

        allow(expense).to receive(:description).and_return('Unknown transaction')
        allow(expense).to receive(:merchant_name).and_return('UNKNOWN MERCHANT')

        category = service.guess_category_for_expense(expense)
        expect(category).to be_nil
      end
    end

    context 'with nil expense' do
      it 'returns default category for nil expense' do
        category = service.guess_category_for_expense(nil)
        expect(category.name).to eq('Sin Categoría')
      end
    end

    context 'with nil description and merchant_name' do
      it 'returns default category' do
        allow(expense).to receive(:description).and_return(nil)
        allow(expense).to receive(:merchant_name).and_return(nil)

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Sin Categoría')
      end
    end

    context 'with empty strings' do
      it 'returns default category' do
        allow(expense).to receive(:description).and_return('')
        allow(expense).to receive(:merchant_name).and_return('')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Sin Categoría')
      end
    end

    context 'case insensitive matching' do
      it 'matches keywords regardless of case' do
        allow(expense).to receive(:description).and_return('RESTAURANT PURCHASE')
        allow(expense).to receive(:merchant_name).and_return('super mercado')

        category = service.guess_category_for_expense(expense)
        expect(category.name).to eq('Alimentación')
      end
    end

    context 'priority handling' do
      it 'returns first matching category' do
        # This text could match both Alimentación (super) and Compras (tienda)
        allow(expense).to receive(:description).and_return('tienda super store')
        allow(expense).to receive(:merchant_name).and_return('MIXED MERCHANT')

        category = service.guess_category_for_expense(expense)
        # Should return Alimentación since it comes first in the hash iteration
        expect(category.name).to eq('Alimentación')
      end
    end
  end

  describe '#guess_category_from_text', integration: true do
    it 'categorizes using description only' do
      category = service.guess_category_from_text(description: 'restaurant meal')
      expect(category.name).to eq('Alimentación')
    end

    it 'categorizes using merchant_name only' do
      category = service.guess_category_from_text(merchant_name: 'GASOLINA TEXACO')
      expect(category.name).to eq('Transporte')
    end

    it 'categorizes using both description and merchant_name' do
      category = service.guess_category_from_text(
        description: 'Medical consultation',
        merchant_name: 'CLINICA BIBLICA'
      )
      expect(category.name).to eq('Salud')
    end

    it 'handles nil values' do
      category = service.guess_category_from_text(description: nil, merchant_name: nil)
      expect(category.name).to eq('Sin Categoría')
    end

    it 'handles empty strings' do
      category = service.guess_category_from_text(description: '', merchant_name: '')
      expect(category.name).to eq('Sin Categoría')
    end
  end

  describe '#available_categories', integration: true do
    it 'returns list of available category names' do
      categories = service.available_categories
      expect(categories).to include('Alimentación', 'Transporte', 'Servicios', 'Entretenimiento', 'Salud', 'Compras')
      expect(categories.size).to eq(6)
    end
  end

  describe '#keywords_for_category', integration: true do
    it 'returns keywords for Alimentación' do
      keywords = service.keywords_for_category('Alimentación')
      expect(keywords).to include('restaurant', 'restaurante', 'comida', 'food', 'super', 'supermercado', 'grocery', 'mercado')
    end

    it 'returns keywords for Transporte' do
      keywords = service.keywords_for_category('Transporte')
      expect(keywords).to include('gasolina', 'gas', 'combustible', 'uber', 'taxi', 'transporte')
    end

    it 'returns empty array for unknown category' do
      keywords = service.keywords_for_category('Unknown Category')
      expect(keywords).to eq([])
    end
  end

  describe 'constants', integration: true do
    it 'defines category keywords mapping' do
      expect(described_class::CATEGORY_KEYWORDS).to be_a(Hash)
      expect(described_class::CATEGORY_KEYWORDS.keys).to include('Alimentación', 'Transporte')
    end

    it 'defines default categories' do
      expect(described_class::DEFAULT_CATEGORIES).to eq([ 'Sin Categoría', 'Other' ])
    end

    it 'freezes constants to prevent modification' do
      expect(described_class::CATEGORY_KEYWORDS).to be_frozen
      expect(described_class::DEFAULT_CATEGORIES).to be_frozen
    end
  end

  describe 'private methods', integration: true do
    describe '#build_search_text', integration: true do
      it 'combines description and merchant_name' do
        allow(expense).to receive(:description).and_return('Test description')
        allow(expense).to receive(:merchant_name).and_return('Test merchant')

        text = service.send(:build_search_text, expense)
        expect(text).to eq('test description test merchant')
      end

      it 'handles nil values' do
        allow(expense).to receive(:description).and_return(nil)
        allow(expense).to receive(:merchant_name).and_return('Test merchant')

        text = service.send(:build_search_text, expense)
        expect(text).to eq('test merchant')
      end

      it 'returns empty string for nil expense' do
        text = service.send(:build_search_text, nil)
        expect(text).to eq('')
      end
    end

    describe '#build_search_text_from_parts', integration: true do
      it 'combines parts correctly' do
        text = service.send(:build_search_text_from_parts, 'Description', 'Merchant')
        expect(text).to eq('description merchant')
      end

      it 'handles nil values' do
        text = service.send(:build_search_text_from_parts, nil, 'Merchant')
        expect(text).to eq('merchant')
      end
    end

    describe '#find_matching_category', integration: true do
      it 'finds category for matching text' do
        category = service.send(:find_matching_category, 'restaurant food')
        expect(category.name).to eq('Alimentación')
      end

      it 'returns nil for non-matching text' do
        category = service.send(:find_matching_category, 'unknown text')
        expect(category).to be_nil
      end

      it 'returns nil for blank text' do
        category = service.send(:find_matching_category, '')
        expect(category).to be_nil
      end
    end

    describe '#find_default_category', integration: true do
      it 'finds Sin Categoría first' do
        category = service.send(:find_default_category)
        expect(category.name).to eq('Sin Categoría')
      end

      it 'falls back to Other if Sin Categoría not found' do
        Category.find_by(name: 'Sin Categoría')&.destroy
        category = service.send(:find_default_category)
        expect(category.name).to eq('Other')
      end

      it 'returns nil if no default categories found' do
        Category.where(name: [ 'Sin Categoría', 'Other' ]).destroy_all
        category = service.send(:find_default_category)
        expect(category).to be_nil
      end
    end
  end
end
