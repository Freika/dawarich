# frozen_string_literal: true

class AddHexagonDataToStats < ActiveRecord::Migration[8.0]
  def change
    add_column :stats, :hexagon_data, :jsonb
  end
end
