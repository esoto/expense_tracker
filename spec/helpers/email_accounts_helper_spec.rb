require 'rails_helper'

RSpec.describe EmailAccountsHelper, type: :helper do
  describe "#bank_options" do
    it "returns an array of bank names" do
      expect(helper.bank_options).to be_an(Array)
    end

    it "includes all expected banks" do
      expected_banks = [ "BAC", "Banco Nacional", "BCR", "Scotiabank", "Banco Popular", "Davivienda" ]
      expect(helper.bank_options).to eq(expected_banks)
    end

    it "returns exactly 6 banks" do
      expect(helper.bank_options.size).to eq(6)
    end
  end

  describe "#email_provider_options" do
    it "returns an array of arrays" do
      expect(helper.email_provider_options).to be_an(Array)
      expect(helper.email_provider_options.first).to be_an(Array)
    end

    it "includes all expected email providers" do
      expected_providers = [
        [ "Gmail", "gmail" ],
        [ "Outlook/Hotmail", "outlook" ],
        [ "Yahoo", "yahoo" ],
        [ "Personalizado", "custom" ]
      ]
      expect(helper.email_provider_options).to eq(expected_providers)
    end

    it "returns exactly 4 provider options" do
      expect(helper.email_provider_options.size).to eq(4)
    end

    it "each provider option has a display name and value" do
      helper.email_provider_options.each do |option|
        expect(option.size).to eq(2)
        expect(option[0]).to be_a(String) # display name
        expect(option[1]).to be_a(String) # value
      end
    end
  end
end
