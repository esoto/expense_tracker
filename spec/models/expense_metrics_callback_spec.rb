# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Expense metrics callbacks", type: :model do
  let(:email_account) { create(:email_account) }
  let(:expense) { create(:expense, email_account: email_account, amount: 100, transaction_date: Date.current) }
  
  before do
    Rails.cache.clear
  end
  
  describe 'after_commit callbacks' do
    describe '#trigger_metrics_refresh' do
      context 'on create' do
        it 'triggers metrics refresh job' do
          expect(MetricsRefreshJob).to receive(:enqueue_debounced).with(
            email_account.id,
            affected_date: Date.current,
            delay: 3.seconds
          )
          
          create(:expense, email_account: email_account, transaction_date: Date.current)
        end
      end
      
      context 'on update' do
        it 'triggers refresh when amount changes' do
          expense # Create the expense first
          
          expect(MetricsRefreshJob).to receive(:enqueue_debounced).with(
            email_account.id,
            affected_date: expense.transaction_date,
            delay: 3.seconds
          )
          
          expense.update!(amount: 200)
        end
        
        it 'triggers refresh when transaction_date changes' do
          expense # Create the expense first
          old_date = expense.transaction_date
          new_date = 1.day.ago
          
          # Should trigger for both old and new dates
          expect(MetricsRefreshJob).to receive(:enqueue_debounced).with(
            email_account.id,
            affected_date: old_date,
            delay: 3.seconds
          ).ordered
          
          expect(MetricsRefreshJob).to receive(:enqueue_debounced).with(
            email_account.id,
            affected_date: new_date,
            delay: 3.seconds
          ).ordered
          
          expense.update!(transaction_date: new_date)
        end
        
        it 'triggers refresh when category changes' do
          expense # Create the expense first
          new_category = create(:category)
          
          expect(MetricsRefreshJob).to receive(:enqueue_debounced).with(
            email_account.id,
            affected_date: expense.transaction_date,
            delay: 3.seconds
          )
          
          expense.update!(category: new_category)
        end
        
        it 'triggers refresh when status changes' do
          expense # Create the expense first
          
          expect(MetricsRefreshJob).to receive(:enqueue_debounced).with(
            email_account.id,
            affected_date: expense.transaction_date,
            delay: 3.seconds
          )
          
          expense.update!(status: 'processed')
        end
        
        it 'does not trigger refresh for insignificant changes' do
          expense # Create the expense first
          
          expect(MetricsRefreshJob).not_to receive(:enqueue_debounced)
          
          expense.update!(description: 'Updated description')
        end
      end
      
      context 'error handling' do
        it 'does not affect main transaction if job scheduling fails' do
          allow(MetricsRefreshJob).to receive(:enqueue_debounced).and_raise(StandardError, "Job error")
          
          expect(Rails.logger).to receive(:error).with(/Failed to trigger metrics refresh/)
          
          # Transaction should still succeed
          expect {
            create(:expense, email_account: email_account)
          }.to change(Expense, :count).by(1)
        end
      end
    end
    
    describe '#trigger_metrics_refresh_for_deletion' do
      it 'triggers metrics refresh when expense is deleted' do
        expense # Create the expense first
        
        expect(MetricsRefreshJob).to receive(:enqueue_debounced).with(
          email_account.id,
          affected_date: expense.transaction_date,
          delay: 3.seconds
        )
        
        expense.destroy
      end
      
      it 'handles errors gracefully during deletion' do
        expense # Create the expense first
        
        allow(MetricsRefreshJob).to receive(:enqueue_debounced).and_raise(StandardError, "Job error")
        
        expect(Rails.logger).to receive(:error).with(/Failed to trigger metrics refresh after deletion/)
        
        # Deletion should still succeed
        expect {
          expense.destroy
        }.to change(Expense, :count).by(-1)
      end
    end
  end
  
  describe 'bulk operations' do
    it 'uses debouncing to prevent job flooding on bulk creates' do
      # First expense triggers job
      expect(MetricsRefreshJob).to receive(:enqueue_debounced).once
      
      # Create multiple expenses rapidly
      5.times do
        create(:expense, email_account: email_account, transaction_date: Date.current)
      end
    end
    
    it 'batches affected dates for multiple updates' do
      expenses = create_list(:expense, 3, email_account: email_account)
      
      # Update all expenses - should use debouncing
      expect(MetricsRefreshJob).to receive(:enqueue_debounced).at_most(3).times
      
      expenses.each { |e| e.update!(amount: e.amount + 10) }
    end
  end
  
  describe 'integration with dashboard cache clearing' do
    it 'clears dashboard cache in addition to triggering metrics refresh' do
      expect(DashboardService).to receive(:clear_cache)
      expect(MetricsRefreshJob).to receive(:enqueue_debounced)
      
      create(:expense, email_account: email_account)
    end
  end
end