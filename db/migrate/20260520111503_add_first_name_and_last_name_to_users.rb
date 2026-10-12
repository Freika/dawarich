# frozen_string_literal: true

class AddFirstNameAndLastNameToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :first_name, :string, if_not_exists: true
    add_column :users, :last_name, :string, if_not_exists: true
  end
end
