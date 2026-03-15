# frozen_string_literal: true

class AddIndiciesToPointsLatitudeLongitude < ActiveRecord::Migration[7.1]
  def change
    add_index :points, %i[latitude longitude]
  end
end
