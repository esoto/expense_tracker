# frozen_string_literal: true

class MakeExpensesUserIdNotNull < ActiveRecord::Migration[8.1]
  def up
    change_column_null :expenses, :user_id, false
  end

  def down
    change_column_null :expenses, :user_id, true
  end
end
