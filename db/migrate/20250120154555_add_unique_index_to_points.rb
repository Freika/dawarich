# frozen_string_literal: true

class AddUniqueIndexToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_index :points, %i[latitude longitude timestamp user_id],
              unique: true,
              name: 'unique_points_lat_long_timestamp_user_id_index',
              algorithm: :concurrently
  end

  def down
    remove_index :points, name: 'unique_points_lat_long_timestamp_user_id_index'
  end
end
