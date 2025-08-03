module EmailProcessing
  module Strategies
    class Base
      def initialize(parsing_rule)
        @parsing_rule = parsing_rule
      end

      def parse_email(email_content)
        raise NotImplementedError, "Subclasses must implement parse_email method"
      end

      def can_parse?(email_content)
        true # Base implementation accepts all content
      end

      protected

      attr_reader :parsing_rule
    end
  end
end