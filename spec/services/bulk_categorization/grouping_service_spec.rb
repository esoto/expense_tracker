# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkCategorization::GroupingService, integration: true do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category, name: "Food & Dining") }

  let!(:expense1) { create(:expense, email_account: email_account, merchant_name: "Starbucks", merchant_normalized: "starbucks", amount: 5000, category: nil) }
  let!(:expense2) { create(:expense, email_account: email_account, merchant_name: "Starbucks Coffee", merchant_normalized: "starbucks", amount: 4500, category: nil) }
  let!(:expense3) { create(:expense, email_account: email_account, merchant_name: "McDonalds", merchant_normalized: "mcdonalds", amount: 8000, category: nil) }
  let!(:expense4) { create(:expense, email_account: email_account, merchant_name: "McDonalds", merchant_normalized: "mcdonalds", amount: 7500, category: nil) }
  let!(:expense5) { create(:expense, email_account: email_account, merchant_name: "Amazon", merchant_normalized: "amazon", amount: 15000, category: nil) }

  let(:expenses) { [ expense1, expense2, expense3, expense4, expense5 ] }
  let(:service) { described_class.new(expenses) }

  describe '#group_by_similarity', integration: true do
    it 'groups expenses with the same merchant' do
      groups = service.group_by_similarity

      expect(groups).to be_an(Array)
      expect(groups.size).to be >= 2

      # Find Starbucks group
      starbucks_group = groups.find { |g| g[:grouping_key]&.downcase&.include?('starbucks') }
      expect(starbucks_group).to be_present
      expect(starbucks_group[:expenses]).to include(expense1, expense2)
      expect(starbucks_group[:count]).to eq(2)
      expect(starbucks_group[:total_amount]).to eq(9500)

      # Find McDonalds group
      mcdonalds_group = groups.find { |g| g[:grouping_key]&.downcase&.include?('mcdonalds') }
      expect(mcdonalds_group).to be_present
      expect(mcdonalds_group[:expenses]).to include(expense3, expense4)
    end

    it 'calculates confidence for groups' do
      groups = service.group_by_similarity

      groups.each do |group|
        expect(group[:confidence]).to be_a(Float)
        expect(group[:confidence]).to be_between(0, 1)
      end
    end

    it 'does not group single expenses below min_group_size' do
      groups = service.group_by_similarity

      # Amazon should not be in a group (only 1 expense)
      amazon_group = groups.find { |g| g[:expenses].include?(expense5) }
      expect(amazon_group).to be_nil
    end

    it 'sorts groups by confidence and size' do
      groups = service.group_by_similarity

      # Groups should be sorted by confidence (descending) and then by size
      confidences = groups.map { |g| g[:confidence] }
      expect(confidences).to eq(confidences.sort.reverse)
    end
  end

  describe '#group_by', integration: true do
    context 'when grouping by merchant' do
      it 'groups expenses by exact merchant match' do
        groups = service.group_by(:merchant)

        starbucks_group = groups.find { |g| g[:grouping_key] == 'starbucks' }
        expect(starbucks_group[:expenses]).to contain_exactly(expense1, expense2)
      end
    end

    context 'when grouping by amount' do
      it 'groups expenses by amount ranges' do
        groups = service.group_by(:amount)

        expect(groups).to be_an(Array)

        # Small amount group should include Starbucks expenses
        small_group = groups.find { |g| g[:grouping_key].include?('Small') }
        expect(small_group).to be_present
        expect(small_group[:expenses]).to include(expense1, expense2)
      end
    end

    context 'when grouping by date' do
      before do
        expense1.update!(transaction_date: Date.current)
        expense2.update!(transaction_date: Date.current)
        expense3.update!(transaction_date: 1.month.ago)
        expense4.update!(transaction_date: 1.month.ago)
        expense5.update!(transaction_date: 2.months.ago)
      end

      it 'groups expenses by month' do
        groups = service.group_by(:date)

        current_month_group = groups.find { |g| g[:grouping_key] == Date.current.strftime("%B %Y") }
        expect(current_month_group).to be_present
        expect(current_month_group[:expenses]).to include(expense1, expense2)
      end
    end
  end

  describe 'similarity calculation', integration: true do
    it 'calculates high similarity for similar merchants' do
      service_instance = described_class.new([])

      similar_expense1 = build(:expense, merchant_name: "Starbucks Coffee", description: "Coffee purchase")
      similar_expense2 = build(:expense, merchant_name: "Starbucks", description: "Coffee and snack")

      similarity = service_instance.send(:calculate_similarity, similar_expense1, similar_expense2)

      expect(similarity).to be > 0.7
    end

    it 'calculates low similarity for different merchants' do
      service_instance = described_class.new([])

      different_expense1 = build(:expense,
        merchant_name: "Starbucks",
        merchant_normalized: "starbucks",
        description: "Coffee",
        amount: 5000,
        transaction_date: Date.current
      )
      different_expense2 = build(:expense,
        merchant_name: "Gas Station",
        merchant_normalized: "gas_station",
        description: "Fuel",
        amount: 25000,
        transaction_date: 2.months.ago
      )

      similarity = service_instance.send(:calculate_similarity, different_expense1, different_expense2)

      expect(similarity).to be < 0.5  # Adjusted threshold for more realistic comparison
    end
  end
end
