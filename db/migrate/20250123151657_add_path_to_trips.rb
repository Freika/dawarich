# frozen_string_literal: true

class AddPathToTrips < ActiveRecord::Migration[8.0]
  def change
    add_column :trips, :path, :line_string, srid: 3857
  end
end
