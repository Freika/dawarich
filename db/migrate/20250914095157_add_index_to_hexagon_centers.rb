class AddIndexToHexagonCenters < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :stats, :hexagon_centers, using: :gin, where: "hexagon_centers IS NOT NULL", algorithm: :concurrently
  end
end
