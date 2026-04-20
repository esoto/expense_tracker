# frozen_string_literal: true

class MakeEmailAccountsUserIdNotNull < ActiveRecord::Migration[8.1]
  def up
    change_column_null :email_accounts, :user_id, false
  end

  def down
    change_column_null :email_accounts, :user_id, true
  end
end
