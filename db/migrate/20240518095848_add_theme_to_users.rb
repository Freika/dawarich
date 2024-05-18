# frozen_string_literal: true

class AddThemeToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :theme, :string, default: 'dark', null: false
  end
end
