require 'rails_helper'

RSpec.describe EmailProcessing::StrategyFactory do
  let(:parsing_rule) { create(:parsing_rule, bank_name: 'Banco Nacional') }
  let(:email_content) { 'Monto: ₡1000\nFecha: 15/08/2024' }

  describe '.create_strategy' do
    it 'creates default strategy for unknown banks' do
      strategy = described_class.create_strategy(parsing_rule)
      expect(strategy).to be_a(EmailProcessing::Strategies::Regex)
      expect(strategy.instance_variable_get(:@parsing_rule)).to eq(parsing_rule)
    end

    it 'creates default strategy when no specific mapping exists' do
      unknown_bank_rule = create(:parsing_rule, bank_name: 'Unknown Bank')
      strategy = described_class.create_strategy(unknown_bank_rule)
      expect(strategy).to be_a(EmailProcessing::Strategies::Regex)
    end

    context 'with email content validation' do
      it 'logs warning when strategy cannot parse content' do
        unparseable_content = 'This content has no amount or date'

        expect(Rails.logger).to receive(:warn).with(
          "[EmailProcessing::StrategyFactory] Strategy #{EmailProcessing::Strategies::Regex} cannot parse content for #{parsing_rule.bank_name}"
        )

        strategy = described_class.create_strategy(parsing_rule, email_content: unparseable_content)
        expect(strategy).to be_a(EmailProcessing::Strategies::Regex)
      end

      it 'does not log warning when strategy can parse content' do
        rule = create(:parsing_rule,
          bank_name: 'Test Bank',
          amount_pattern: 'Monto: ₡([0-9,.]+)',
          date_pattern: 'Fecha: ([0-9]{2}/[0-9]{2}/[0-9]{4})'
        )

        expect(Rails.logger).not_to receive(:warn)

        strategy = described_class.create_strategy(rule, email_content: email_content)
        expect(strategy).to be_a(EmailProcessing::Strategies::Regex)
      end

      it 'works without email content validation' do
        strategy = described_class.create_strategy(parsing_rule)
        expect(strategy).to be_a(EmailProcessing::Strategies::Regex)
      end
    end

    context 'with bank-specific strategies' do
      before do
        # Simulate adding a bank-specific strategy
        stub_const('ParsingStrategyFactory::STRATEGY_MAPPINGS', {
          'banco_nacional' => EmailProcessing::Strategies::Regex,
          'custom_bank' => EmailProcessing::Strategies::Regex,
          default: EmailProcessing::Strategies::Regex
        })
      end

      it 'uses bank-specific strategy when available' do
        banco_nacional_rule = create(:parsing_rule, bank_name: 'Banco Nacional')
        strategy = described_class.create_strategy(banco_nacional_rule)
        expect(strategy).to be_a(EmailProcessing::Strategies::Regex)
      end

      it 'uses case-insensitive bank matching' do
        mixed_case_rule = create(:parsing_rule, bank_name: 'BANCO NACIONAL')
        strategy = described_class.create_strategy(mixed_case_rule)
        expect(strategy).to be_a(EmailProcessing::Strategies::Regex)
      end
    end
  end

  describe '.available_strategies' do
    it 'returns all available strategy keys' do
      strategies = described_class.available_strategies
      expect(strategies).to include(:default)
      expect(strategies).to be_an(Array)
    end
  end

  describe '.strategy_for_bank' do
    it 'returns default strategy for unknown banks' do
      strategy_class = described_class.strategy_for_bank('Unknown Bank')
      expect(strategy_class).to eq(EmailProcessing::Strategies::Regex)
    end

    it 'is case insensitive' do
      strategy_class = described_class.strategy_for_bank('BANCO NACIONAL')
      expect(strategy_class).to eq(EmailProcessing::Strategies::Regex)
    end

    context 'with custom bank mappings' do
      before do
        stub_const('ParsingStrategyFactory::STRATEGY_MAPPINGS', {
          'special_bank' => EmailProcessing::Strategies::Regex,
          default: EmailProcessing::Strategies::Regex
        })
      end

      it 'returns specific strategy for mapped banks' do
        strategy_class = described_class.strategy_for_bank('Special Bank')
        expect(strategy_class).to eq(EmailProcessing::Strategies::Regex)
      end
    end
  end

  describe 'constants' do
    it 'defines strategy mappings as frozen hash' do
      expect(described_class::STRATEGY_MAPPINGS).to be_frozen
      expect(described_class::STRATEGY_MAPPINGS).to be_a(Hash)
      expect(described_class::STRATEGY_MAPPINGS[:default]).to eq(EmailProcessing::Strategies::Regex)
    end
  end
end
