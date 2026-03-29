# frozen_string_literal: true

class AddDeviseLockableToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :failed_attempts, :integer, default: 0, null: false
    add_column :users, :locked_at, :datetime
    add_column :users, :unlock_token, :string

    add_index :users, :unlock_token, unique: true
  end
end
