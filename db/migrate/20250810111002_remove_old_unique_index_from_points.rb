class RemoveOldUniqueIndexFromPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    remove_index :points, name: "index_points_on_lonlat_timestamp_user_id", algorithm: :concurrently
  end

  def down
    add_index :points, [:lonlat, :timestamp, :user_id],
              name: "index_points_on_lonlat_timestamp_user_id",
              unique: true,
              algorithm: :concurrently,
              if_not_exists: true
  end
end
