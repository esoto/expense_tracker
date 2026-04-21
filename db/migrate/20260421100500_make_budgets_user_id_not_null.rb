# frozen_string_literal: true

class MakeBudgetsUserIdNotNull < ActiveRecord::Migration[8.1]
  def up
    change_column_null :budgets, :user_id, false
  end

  def down
    change_column_null :budgets, :user_id, true
  end
end
