class AddNotesToExpenses < ActiveRecord::Migration[8.1]
  def change
    add_column :expenses, :notes, :text
  end
end
