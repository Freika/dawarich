class AddUniqueIndexToPointsWithDeviceId < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_index :points, [:lonlat, :timestamp, :user_id, :device_id],
              name: "index_points_on_lonlat_timestamp_user_id_device_id",
              unique: true,
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :points, name: "index_points_on_lonlat_timestamp_user_id_device_id", algorithm: :concurrently
  end
end
