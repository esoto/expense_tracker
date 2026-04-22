class AddUserIdToCategories < ActiveRecord::Migration[8.1]
  def change
    add_reference :categories, :user, foreign_key: true, null: true, index: true

    # Lookup index for tree rendering per user.
    add_index :categories, [ :user_id, :parent_id ]

    # Partial unique index: a given user cannot have two personal categories
    # with the same name. Shared categories (user_id IS NULL) are unaffected,
    # so the current seeded set is not constrained.
    add_index :categories,
              [ :user_id, :name ],
              unique: true,
              where: "user_id IS NOT NULL",
              name: "index_categories_on_user_id_and_name_personal"
  end
end
