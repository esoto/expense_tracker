# frozen_string_literal: true

class AddUserToEmailAccounts < ActiveRecord::Migration[8.1]
  def change
    add_reference :email_accounts, :user, foreign_key: true, index: true, null: true
  end
end
