# frozen_string_literal: true

class AddActiveUntilToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :active_until, :datetime
  end
end
