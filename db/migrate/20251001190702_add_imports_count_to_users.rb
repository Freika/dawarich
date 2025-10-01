# frozen_string_literal: true

class AddImportsCountToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :imports_count, :integer, default: 0, null: false
  end
end
