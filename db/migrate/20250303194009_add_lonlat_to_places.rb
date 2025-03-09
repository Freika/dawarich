# frozen_string_literal: true

class AddLonlatToPlaces < ActiveRecord::Migration[8.0]
  def change
    add_column :places, :lonlat, :st_point, geographic: true
  end
end
