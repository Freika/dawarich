# frozen_string_literal: true

class AddGeoForeignKeysToPoints < ActiveRecord::Migration[8.0]
  def change
    add_reference :points, :country, foreign_key: true
    add_reference :points, :state, foreign_key: true
    add_reference :points, :county, foreign_key: true
    add_reference :points, :city, foreign_key: true
  end
end
