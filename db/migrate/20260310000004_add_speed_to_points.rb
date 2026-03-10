# frozen_string_literal: true

class AddSpeedToPoints < ActiveRecord::Migration[8.0]
  def change
    add_column :points, :speed, :float, if_not_exists: true
  end
end
