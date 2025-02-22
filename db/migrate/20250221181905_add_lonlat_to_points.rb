# frozen_string_literal: true

class AddLonlatToPoints < ActiveRecord::Migration[8.0]
  def change
    add_column :points, :lonlat, :st_point, geographic: true
  end
end
