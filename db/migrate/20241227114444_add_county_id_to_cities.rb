# frozen_string_literal: true

class AddCountyIdToCities < ActiveRecord::Migration[8.0]
  def change
    add_reference :cities, :county, foreign_key: true
  end
end
