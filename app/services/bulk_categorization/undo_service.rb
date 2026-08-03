# frozen_string_literal: true

module Services::BulkCategorization
  # Service to undo bulk categorization operations
  class UndoService
    include ActiveModel::Model

    attr_accessor :bulk_operation, :undone_by

    validates :bulk_operation, presence: true

    def initialize(bulk_operation:, undone_by: nil)
      @bulk_operation = bulk_operation
      @undone_by = undone_by
    end

    def call
      return failure_result("Operation cannot be undone") unless bulk_operation&.undoable?

      ActiveRecord::Base.transaction do
        if bulk_operation.undo!(undone_by: undone_by)
          success_result
        else
          failure_result("Failed to undo operation")
        end
      end
    rescue StandardError => e
      Rails.logger.error "BulkCategorization::UndoService error: #{e.message}"
      failure_result("An error occurred while undoing the operation")
    end

    private

    def success_result
      OpenStruct.new(
        success?: true,
        message: "Successfully undone categorization for #{bulk_operation.expense_count} expenses",
        operation: bulk_operation.reload
      )
    end

    def failure_result(message)
      OpenStruct.new(
        success?: false,
        message: message,
        operation: bulk_operation
      )
    end
  end
end
