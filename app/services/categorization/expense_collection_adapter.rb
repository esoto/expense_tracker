# frozen_string_literal: true

module Services
  module Categorization
    class ExpenseCollectionAdapter
      def initialize(collection)
        @collection = collection
      end

      def find_each(&block)
        if activerecord_relation?
          @collection.find_each(&block)
        else
          @collection.each(&block)
        end
      end

      def in_batches(batch_size: 100)
        if activerecord_relation?
          @collection.in_batches(of: batch_size) do |batch|
            yield batch
          end
        else
          @collection.each_slice(batch_size) do |batch|
            yield batch
          end
        end
      end

      def each(&block)
        @collection.each(&block)
      end

      def empty?
        @collection.empty?
      end

      def size
        @collection.size
      end

      def count
        @collection.count
      end

      def select(&block)
        @collection.select(&block)
      end

      def map(&block)
        @collection.map(&block)
      end

      def sum(&block)
        @collection.sum(&block)
      end

      def group_by(&block)
        @collection.group_by(&block)
      end

      def min_by(&block)
        @collection.min_by(&block)
      end

      def max_by(&block)
        @collection.max_by(&block)
      end

      def respond_to_missing?(method_name, include_private = false)
        @collection.respond_to?(method_name, include_private) || super
      end

      def method_missing(method_name, *args, &block)
        if @collection.respond_to?(method_name)
          @collection.public_send(method_name, *args, &block)
        else
          super
        end
      end

      private

      def activerecord_relation?
        @collection.is_a?(ActiveRecord::Relation)
      end
    end
  end
end
