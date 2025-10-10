module Services::EmailProcessing
  class StrategyFactory
    # Strategy mappings by bank name or parsing rule type
    STRATEGY_MAPPINGS = {
      # Default strategy for all banks currently
      default: Services::EmailProcessing::Strategies::Regex
    }.freeze

    def self.create_strategy(parsing_rule, email_content: nil)
      # Get strategy class based on bank name or use default
      strategy_class = STRATEGY_MAPPINGS[parsing_rule.bank_name.downcase.to_sym] ||
                       STRATEGY_MAPPINGS[:default]

      strategy = strategy_class.new(parsing_rule)

      # Validate that the strategy can parse the content if provided
      if email_content && !strategy.can_parse?(email_content)
        Rails.logger.warn "[Services::EmailProcessing::StrategyFactory] Strategy #{strategy_class} cannot parse content for #{parsing_rule.bank_name}"
      end

      strategy
    end

    def self.available_strategies
      STRATEGY_MAPPINGS.keys
    end

    def self.strategy_for_bank(bank_name)
      STRATEGY_MAPPINGS[bank_name.downcase.to_sym] || STRATEGY_MAPPINGS[:default]
    end
  end
end
