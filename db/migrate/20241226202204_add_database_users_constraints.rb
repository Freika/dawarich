# frozen_string_literal: true

class AddDatabaseUsersConstraints < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :users, 'email IS NOT NULL', name: 'users_email_null', validate: false
    add_check_constraint :users, 'admin IS NOT NULL', name: 'users_admin_null', validate: false
  end
end
