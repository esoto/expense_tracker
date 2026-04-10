class AddI18nKeyToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :i18n_key, :string
    add_index :categories, :i18n_key, unique: true
  end
end
