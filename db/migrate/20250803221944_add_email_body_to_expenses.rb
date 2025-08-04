class AddEmailBodyToExpenses < ActiveRecord::Migration[8.0]
  def change
    add_column :expenses, :email_body, :text
  end
end
