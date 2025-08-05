require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  describe '#currency_symbol' do
    it 'returns ₡ for CRC expenses' do
      expense = build(:expense, currency: 'crc')
      expect(helper.currency_symbol(expense)).to eq('₡')
    end

    it 'returns $ for USD expenses' do
      expense = build(:expense, currency: 'usd')
      expect(helper.currency_symbol(expense)).to eq('$')
    end

    it 'returns € for EUR expenses' do
      expense = build(:expense, currency: 'eur')
      expect(helper.currency_symbol(expense)).to eq('€')
    end

    it 'returns ₡ as default for unknown currency' do
      expense = build(:expense)
      allow(expense).to receive(:crc?).and_return(false)
      allow(expense).to receive(:usd?).and_return(false)
      allow(expense).to receive(:eur?).and_return(false)
      expect(helper.currency_symbol(expense)).to eq('₡')
    end
  end

  describe '#format_datetime' do
    it 'formats datetime correctly' do
      datetime = DateTime.new(2024, 8, 3, 14, 30, 0)
      expect(helper.format_datetime(datetime)).to eq('August 03, 2024 at 02:30 PM')
    end

    it 'returns N/A for nil datetime' do
      expect(helper.format_datetime(nil)).to eq('N/A')
    end

    it 'returns N/A for blank datetime' do
      expect(helper.format_datetime('')).to eq('N/A')
    end

    it 'handles midnight correctly' do
      datetime = DateTime.new(2024, 1, 1, 0, 0, 0)
      expect(helper.format_datetime(datetime)).to eq('January 01, 2024 at 12:00 AM')
    end

    it 'handles noon correctly' do
      datetime = DateTime.new(2024, 12, 25, 12, 0, 0)
      expect(helper.format_datetime(datetime)).to eq('December 25, 2024 at 12:00 PM')
    end
  end

  describe '#format_date' do
    it 'formats date correctly' do
      date = Date.new(2024, 8, 3)
      expect(helper.format_date(date)).to eq('August 03, 2024')
    end

    it 'returns N/A for nil date' do
      expect(helper.format_date(nil)).to eq('N/A')
    end

    it 'returns N/A for blank date' do
      expect(helper.format_date('')).to eq('N/A')
    end

    it 'handles leap year date' do
      date = Date.new(2024, 2, 29)
      expect(helper.format_date(date)).to eq('February 29, 2024')
    end

    it 'handles first day of year' do
      date = Date.new(2024, 1, 1)
      expect(helper.format_date(date)).to eq('January 01, 2024')
    end

    it 'handles last day of year' do
      date = Date.new(2024, 12, 31)
      expect(helper.format_date(date)).to eq('December 31, 2024')
    end
  end
end
