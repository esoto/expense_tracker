require 'rails_helper'

RSpec.describe EmailParsingFailure, type: :model, unit: true do
  describe 'associations' do
    it { is_expected.to belong_to(:email_account) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:error_messages) }
  end

  describe 'defaults' do
    subject(:failure) { described_class.new }

    it 'defaults error_messages to empty array' do
      expect(failure.error_messages).to eq([])
    end

    it 'defaults truncated to false' do
      expect(failure.truncated).to eq(false)
    end
  end

  describe 'factory' do
    it 'creates a valid record' do
      failure = build(:email_parsing_failure)
      expect(failure).to be_valid
    end
  end

  describe 'dependent destroy from email_account' do
    it 'is destroyed when email_account is destroyed' do
      failure = create(:email_parsing_failure)
      email_account = failure.email_account

      expect { email_account.destroy }.to change(described_class, :count).by(-1)
    end
  end
end
