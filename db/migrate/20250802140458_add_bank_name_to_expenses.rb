class AddBankNameToExpenses < ActiveRecord::Migration[8.0]
  def change
    add_column :expenses, :bank_name, :string
  end
end
