# frozen_string_literal: true

module Services::Categorization
  module Strategies
    # Base interface for categorization strategies.
    #
    # Each strategy encapsulates one approach to categorizing an expense
    # (e.g. pattern matching, ML inference, rule-based). The Engine iterates
    # through its strategy chain until one returns a confident result.
    #
    # Subclasses MUST implement:
    #   #call(expense, options = {}) -> CategorizationResult
    #   #layer_name -> String
    class BaseStrategy
      # Categorize an expense using this strategy.
      #
      # @param expense [Expense] the expense to categorize
      # @param options [Hash] strategy-specific options
      # @return [CategorizationResult]
      def call(expense, options = {})
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end

      # A short identifier for this strategy layer (e.g. "pattern", "ml").
      #
      # @return [String]
      def layer_name
        raise NotImplementedError, "#{self.class}#layer_name must be implemented"
      end
    end
  end
end
