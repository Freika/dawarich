# frozen_string_literal: true

class ChangePointsAltitudeToDecimal < ActiveRecord::Migration[8.0]
  def up
    change_column :points, :altitude, :decimal, precision: 10, scale: 2
  end

  def down
    change_column :points, :altitude, :integer
  end
end
