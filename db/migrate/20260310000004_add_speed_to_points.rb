# frozen_string_literal: true

class AddSpeedToPoints < ActiveRecord::Migration[8.0]
  def change
    add_column :points, :speed, :float
  end
end
