# frozen_string_literal: true

class AddUniqueIndexToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    return if index_exists?(
      :points, %i[latitude longitude timestamp user_id],
      name: 'unique_points_lat_long_timestamp_user_id_index'
    )

    add_index :points, %i[latitude longitude timestamp user_id],
              unique: true,
              name: 'unique_points_lat_long_timestamp_user_id_index',
              algorithm: :concurrently
  end

  def down
    return unless index_exists?(
      :points, %i[latitude longitude timestamp user_id],
      name: 'unique_points_lat_long_timestamp_user_id_index'
    )

    remove_index :points, %i[latitude longitude timestamp user_id],
                 name: 'unique_points_lat_long_timestamp_user_id_index'
  end
end
