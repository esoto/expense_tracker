# frozen_string_literal: true

module Categorization
  module Matchers
    # Dedicated service for extracting text from various object types
    # Provides a clean separation of concerns for text extraction logic
    class TextExtractor
      # Main extraction method - handles any type of input
      def extract_from(object)
        case object
        when String
          object
        when Hash
          extract_from_hash(object)
        else
          extract_from_object(object)
        end
      end

      # Batch extraction for performance
      def extract_from_many(objects)
        objects.map { |obj| extract_from(obj) }
      end

      private

      # Extract text from hash structures
      def extract_from_hash(hash)
        # Priority order for common hash keys
        hash[:text] ||
        hash["text"] ||
        hash[:name] ||
        hash["name"] ||
        hash[:value] ||
        hash["value"] ||
        hash[:merchant_name] ||
        hash["merchant_name"] ||
        hash[:description] ||
        hash["description"]
      end

      # Extract text from ActiveRecord models and other objects
      def extract_from_object(object)
        # Handle nil gracefully
        return nil if object.nil?

        # Get class name without loading the class (avoid dependencies)
        class_name = object.class.name

        case class_name
        when "CategorizationPattern"
          extract_from_pattern(object)
        when "Expense"
          extract_from_expense(object)
        when "CanonicalMerchant"
          extract_from_merchant(object)
        when "MerchantAlias"
          extract_from_alias(object)
        else
          extract_from_generic(object)
        end
      end

      # Extract from CategorizationPattern
      def extract_from_pattern(pattern)
        return nil unless pattern.respond_to?(:pattern_value)
        pattern.pattern_value
      end

      # Extract from Expense - use actual attributes, not computed values
      def extract_from_expense(expense)
        return nil unless expense

        # Use merchant_name method if available (which already safely reads the attribute)
        # This matches what the test expects - using expense.merchant_name
        if expense.respond_to?(:merchant_name) && expense.merchant_name?
          expense.merchant_name
        elsif expense.respond_to?(:merchant_normalized) && expense.merchant_normalized?
          expense.merchant_normalized
        elsif expense.respond_to?(:description) && expense.description?
          expense.description
        elsif expense.respond_to?(:read_attribute)
          # Safely read the actual database attribute
          expense.read_attribute(:merchant_name) ||
          expense.read_attribute(:merchant_normalized) ||
          expense.read_attribute(:description)
        else
          nil
        end
      end

      # Extract from CanonicalMerchant
      def extract_from_merchant(merchant)
        return nil unless merchant.respond_to?(:name)
        merchant.name
      end

      # Extract from MerchantAlias
      def extract_from_alias(alias_obj)
        return nil unless alias_obj

        if alias_obj.respond_to?(:normalized_name) && alias_obj.normalized_name.present?
          alias_obj.normalized_name
        elsif alias_obj.respond_to?(:raw_name)
          alias_obj.raw_name
        else
          nil
        end
      end

      # Generic extraction for objects with common methods
      def extract_from_generic(object)
        # Try common attribute methods in priority order
        if object.respond_to?(:name)
          object.name
        elsif object.respond_to?(:title)
          object.title
        elsif object.respond_to?(:value)
          object.value
        elsif object.respond_to?(:to_s)
          # Last resort - convert to string
          # But check if it's a meaningful string representation
          str = object.to_s
          # Avoid returning class inspection strings like "#<Object:0x...>"
          str.start_with?("#<") ? nil : str
        else
          nil
        end
      end
    end
  end
end
