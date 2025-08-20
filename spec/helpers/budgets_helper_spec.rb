# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BudgetsHelper, type: :helper, unit: true do
  describe '#progress_bar_color_class', unit: true do
    it 'returns correct color class for each status' do
      expect(helper.progress_bar_color_class(:exceeded)).to eq('bg-rose-600')
      expect(helper.progress_bar_color_class(:critical)).to eq('bg-rose-500')
      expect(helper.progress_bar_color_class(:warning)).to eq('bg-amber-600')
      expect(helper.progress_bar_color_class(:good)).to eq('bg-emerald-600')
    end
  end

  describe '#remaining_amount_color_class', unit: true do
    it 'returns correct color class for exceeded status' do
      expect(helper.remaining_amount_color_class(:exceeded)).to eq('text-rose-600')
    end

    it 'returns correct color class for critical status' do
      expect(helper.remaining_amount_color_class(:critical)).to eq('text-rose-600')
    end

    it 'returns correct color class for warning status' do
      expect(helper.remaining_amount_color_class(:warning)).to eq('text-amber-600')
    end

    it 'returns correct color class for good status' do
      expect(helper.remaining_amount_color_class(:good)).to eq('text-emerald-600')
    end
  end

  describe '#status_text_color_class', unit: true do
    it 'returns correct text color class for each status' do
      expect(helper.status_text_color_class(:exceeded)).to eq('text-rose-700')
      expect(helper.status_text_color_class(:critical)).to eq('text-rose-700')
      expect(helper.status_text_color_class(:warning)).to eq('text-amber-700')
      expect(helper.status_text_color_class(:good)).to eq('text-emerald-700')
    end
  end

  describe '#status_icon', unit: true do
    it 'generates SVG icon for exceeded status' do
      icon = helper.status_icon(:exceeded)
      expect(icon).to include('svg')
      expect(icon).to include('text-rose-600')
      expect(icon).to include('M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z')
    end

    it 'generates SVG icon for critical status' do
      icon = helper.status_icon(:critical)
      expect(icon).to include('svg')
      expect(icon).to include('text-rose-500')
      expect(icon).to include('M12 9v2m0 4h.01m-6.938 4h13.856')
    end

    it 'generates SVG icon for warning status' do
      icon = helper.status_icon(:warning)
      expect(icon).to include('svg')
      expect(icon).to include('text-amber-600')
      expect(icon).to include('M12 9v2m0 4h.01m-6.938 4h13.856')
    end

    it 'generates SVG icon for good status' do
      icon = helper.status_icon(:good)
      expect(icon).to include('svg')
      expect(icon).to include('text-emerald-600')
      expect(icon).to include('M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293')
    end
  end

  describe '#period_from_label', unit: true do
    it 'converts Spanish month label to monthly' do
      expect(helper.period_from_label('Este Mes')).to eq('monthly')
      expect(helper.period_from_label('mes actual')).to eq('monthly')
    end

    it 'converts Spanish week label to weekly' do
      expect(helper.period_from_label('Esta Semana')).to eq('weekly')
      expect(helper.period_from_label('semana actual')).to eq('weekly')
    end

    it 'converts Spanish day label to daily' do
      expect(helper.period_from_label('Hoy')).to eq('daily')
      expect(helper.period_from_label('Día actual')).to eq('daily')
    end

    it 'converts Spanish year label to yearly' do
      expect(helper.period_from_label('Este Año')).to eq('yearly')
      expect(helper.period_from_label('año actual')).to eq('yearly')
    end

    it 'defaults to monthly for unknown labels' do
      expect(helper.period_from_label('Unknown')).to eq('monthly')
      expect(helper.period_from_label('')).to eq('monthly')
    end
  end

  describe '#budget_period_options', unit: true do
    it 'returns array of period options for select dropdown' do
      options = helper.budget_period_options
      expect(options).to be_an(Array)
      expect(options).to include([ "Diario", "daily" ])
      expect(options).to include([ "Semanal", "weekly" ])
      expect(options).to include([ "Mensual", "monthly" ])
      expect(options).to include([ "Anual", "yearly" ])
      expect(options.length).to eq(4)
    end
  end

  describe '#budget_currency_options', unit: true do
    it 'returns array of currency options for select dropdown' do
      options = helper.budget_currency_options
      expect(options).to be_an(Array)
      expect(options).to include([ "Colones (₡)", "CRC" ])
      expect(options).to include([ "Dólares ($)", "USD" ])
      expect(options).to include([ "Euros (€)", "EUR" ])
      expect(options.length).to eq(3)
    end
  end

  describe '#budget_category_options', unit: true do
    let(:categories) do
      [
        double('Category', name: 'Alimentación', id: 1),
        double('Category', name: 'Transporte', id: 2)
      ]
    end

    it 'returns category options with general option by default' do
      options = helper.budget_category_options(categories)
      expect(options).to be_an(Array)
      expect(options).to include([ "General (todas las categorías)", nil ])
      expect(options).to include([ "Alimentación", 1 ])
      expect(options).to include([ "Transporte", 2 ])
      expect(options.length).to eq(3)
    end

    it 'returns category options without general option when specified' do
      options = helper.budget_category_options(categories, include_general: false)
      expect(options).to be_an(Array)
      expect(options).not_to include([ "General (todas las categorías)", nil ])
      expect(options).to include([ "Alimentación", 1 ])
      expect(options).to include([ "Transporte", 2 ])
      expect(options.length).to eq(2)
    end

    it 'handles empty categories array' do
      options = helper.budget_category_options([])
      expect(options).to eq([ [ "General (todas las categorías)", nil ] ])
    end
  end
end
