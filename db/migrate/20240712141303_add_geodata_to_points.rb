# frozen_string_literal: true

class AddGeodataToPoints < ActiveRecord::Migration[7.1]
  def change
    add_column :points, :geodata, :jsonb, null: false, default: {}
    add_index :points, :geodata, using: :gin
  end
end
