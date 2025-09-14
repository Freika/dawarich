class AddHexagonCentersToStats < ActiveRecord::Migration[8.0]
  def change
    add_column :stats, :hexagon_centers, :jsonb
  end
end
