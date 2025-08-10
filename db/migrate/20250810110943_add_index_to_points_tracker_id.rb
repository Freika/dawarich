class AddIndexToPointsTrackerId < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_index :points, :tracker_id,
              name: "index_points_on_tracker_id",
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :points, name: "index_points_on_tracker_id", algorithm: :concurrently
  end
end
