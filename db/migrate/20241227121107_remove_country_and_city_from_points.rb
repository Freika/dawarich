# frozen_string_literal: true

class RemoveCountryAndCityFromPoints < ActiveRecord::Migration[8.0]
  def up
    remove_column :points, :country
    remove_column :points, :city
  end

  def down
    add_column :points, :country, :string
    add_column :points, :city, :string
  end
end
