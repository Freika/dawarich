# frozen_string_literal: true

class AddUserIdTimestampLonlatUniqueIndexToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :points, %i[user_id timestamp lonlat],
              unique: true,
              name: 'index_points_on_user_id_timestamp_lonlat',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
