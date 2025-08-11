# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Budget Indicators on Dashboard', type: :system do
  let!(:email_account) { create(:email_account) }
  let!(:category) { create(:category, name: 'Alimentación') }
  
  before do
    driven_by(:selenium_chrome_headless)
  end
  
  describe 'budget progress display' do
    context 'without budgets' do
      it 'shows "Set Budget" call to action' do
        visit expenses_dashboard_path
        
        within('.bg-white.rounded-xl', text: 'Este Mes') do
          expect(page).to have_content('Sin presupuesto definido')
          expect(page).to have_button('Establecer')
        end
      end
    end
    
    context 'with active budget' do
      let!(:budget) do
        create(:budget, 
          email_account: email_account,
          period: 'monthly',
          amount: 1000000,
          warning_threshold: 70,
          critical_threshold: 90
        )
      end
      
      context 'under warning threshold' do
        before do
          create(:expense, 
            email_account: email_account,
            amount: 500000,
            transaction_date: Date.current,
            currency: 'crc'
          )
        end
        
        it 'displays budget progress with good status' do
          visit expenses_dashboard_path
          
          within('.bg-white.rounded-xl', text: 'Este Mes') do
            expect(page).to have_content('50% usado')
            expect(page).to have_content('de ₡1.000.000')
            expect(page).to have_content('Queda: ₡500.000')
            expect(page).to have_content('Dentro del presupuesto')
            
            # Check progress bar is green
            progress_bar = find('[data-budget-progress-target="bar"]', visible: false)
            expect(progress_bar['style']).to include('width: 50%')
          end
        end
      end
      
      context 'at warning level' do
        before do
          create(:expense, 
            email_account: email_account,
            amount: 750000,
            transaction_date: Date.current,
            currency: 'crc'
          )
        end
        
        it 'displays warning status' do
          visit expenses_dashboard_path
          
          within('.bg-white.rounded-xl', text: 'Este Mes') do
            expect(page).to have_content('75% usado')
            expect(page).to have_content('Atención requerida')
            expect(page).to have_css('.text-amber-600')
          end
        end
      end
      
      context 'at critical level' do
        before do
          create(:expense, 
            email_account: email_account,
            amount: 920000,
            transaction_date: Date.current,
            currency: 'crc'
          )
        end
        
        it 'displays critical status' do
          visit expenses_dashboard_path
          
          within('.bg-white.rounded-xl', text: 'Este Mes') do
            expect(page).to have_content('92% usado')
            expect(page).to have_content('Cerca del límite')
            expect(page).to have_css('.text-rose-500')
          end
        end
      end
      
      context 'when budget is exceeded' do
        before do
          create(:expense, 
            email_account: email_account,
            amount: 1200000,
            transaction_date: Date.current,
            currency: 'crc'
          )
        end
        
        it 'displays exceeded status' do
          visit expenses_dashboard_path
          
          within('.bg-white.rounded-xl', text: 'Este Mes') do
            expect(page).to have_content('120% usado')
            expect(page).to have_content('Excedido: ₡200.000')
            expect(page).to have_content('Presupuesto excedido')
            expect(page).to have_css('.text-rose-600')
          end
        end
      end
    end
    
    context 'with category-specific budgets' do
      let!(:food_budget) do
        create(:budget,
          email_account: email_account,
          category: category,
          period: 'monthly',
          amount: 300000
        )
      end
      
      before do
        create(:expense,
          email_account: email_account,
          category: category,
          amount: 150000,
          transaction_date: Date.current,
          currency: 'crc'
        )
      end
      
      it 'tracks spending per category' do
        visit expenses_dashboard_path
        
        # The category budget should be reflected in the metrics
        within('.bg-white.rounded-xl', text: 'Este Mes') do
          # Category-specific budgets would show in detailed view
          expect(page).to have_content('₡150.000')
        end
      end
    end
  end
  
  describe 'budget period coverage' do
    it 'shows budget for weekly period' do
      create(:budget,
        email_account: email_account,
        period: 'weekly',
        amount: 200000
      )
      
      create(:expense,
        email_account: email_account,
        amount: 80000,
        transaction_date: Date.current,
        currency: 'crc'
      )
      
      visit expenses_dashboard_path
      
      within('.bg-white.rounded-xl', text: 'Esta Semana') do
        expect(page).to have_content('40% usado')
        expect(page).to have_content('de ₡200.000')
      end
    end
    
    it 'shows budget for daily period' do
      create(:budget,
        email_account: email_account,
        period: 'daily',
        amount: 30000
      )
      
      create(:expense,
        email_account: email_account,
        amount: 15000,
        transaction_date: Date.current,
        currency: 'crc'
      )
      
      visit expenses_dashboard_path
      
      within('.bg-white.rounded-xl', text: 'Hoy') do
        expect(page).to have_content('50% usado')
        expect(page).to have_content('de ₡30.000')
      end
    end
  end
  
  describe 'historical adherence indicator' do
    let!(:budget) do
      create(:budget,
        email_account: email_account,
        period: 'monthly',
        amount: 1000000,
        times_exceeded: 2
      )
    end
    
    it 'shows historical performance message' do
      visit expenses_dashboard_path
      
      within('.bg-white.rounded-xl', text: 'Este Mes') do
        expect(page).to have_content('Historial:')
        expect(page).to have_content('Generalmente dentro del presupuesto')
      end
    end
  end
  
  describe 'quick budget setting' do
    it 'opens budget setting form when clicking "Establecer"' do
      visit expenses_dashboard_path
      
      within('.bg-white.rounded-xl', text: 'Este Mes') do
        button = find('button', text: 'Establecer')
        expect(button['data-period']).to eq('monthly')
        
        # The button should have the correct data attributes for Stimulus
        expect(button['data-action']).to include('budget-progress#openQuickSet')
      end
    end
  end
  
  describe 'budget progress animation' do
    let!(:budget) do
      create(:budget,
        email_account: email_account,
        period: 'monthly',
        amount: 1000000
      )
    end
    
    before do
      create(:expense,
        email_account: email_account,
        amount: 600000,
        transaction_date: Date.current,
        currency: 'crc'
      )
    end
    
    it 'animates progress bar on page load', js: true do
      visit expenses_dashboard_path
      
      within('.bg-white.rounded-xl', text: 'Este Mes') do
        progress_bar = find('[data-budget-progress-target="bar"]', visible: false)
        
        # Check that the progress bar has transition styles
        expect(progress_bar['class']).to include('transition-all')
        expect(progress_bar['class']).to include('duration-500')
      end
    end
  end
end