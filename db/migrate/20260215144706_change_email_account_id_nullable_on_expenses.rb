class ChangeEmailAccountIdNullableOnExpenses < ActiveRecord::Migration[8.1]
  def change
    change_column_null :expenses, :email_account_id, true
  end
end
