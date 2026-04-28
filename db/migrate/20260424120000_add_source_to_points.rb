# frozen_string_literal: true

class AddSourceToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :points, :source, :integer, default: 0, null: false, if_not_exists: true
    add_index :points, :source, algorithm: :concurrently, if_not_exists: true
  end
end
