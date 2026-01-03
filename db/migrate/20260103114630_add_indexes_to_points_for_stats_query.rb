class AddIndexesToPointsForStatsQuery < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Index for counting reverse geocoded points
    # This speeds up: COUNT(reverse_geocoded_at)
    add_index :points, [:user_id, :reverse_geocoded_at],
              where: "reverse_geocoded_at IS NOT NULL",
              algorithm: :concurrently,
              if_not_exists: true,
              name: 'index_points_on_user_id_and_reverse_geocoded_at'

    # Index for finding points with empty geodata
    # This speeds up: COUNT(CASE WHEN geodata = '{}'::jsonb THEN 1 END)
    add_index :points, [:user_id, :geodata],
              where: "geodata = '{}'::jsonb",
              algorithm: :concurrently,
              if_not_exists: true,
              name: 'index_points_on_user_id_and_empty_geodata'
  end
end
