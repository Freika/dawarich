# frozen_string_literal: true

class AddPlanToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :plan, :integer, default: 1, null: false
    add_index :users, :plan
  end
end
