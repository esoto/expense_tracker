# frozen_string_literal: true

class AddSpendTrackingToBudgets < ActiveRecord::Migration[8.1]
  def change
    add_column :budgets, :spend_tracking, :boolean, null: false, default: true
  end
end
