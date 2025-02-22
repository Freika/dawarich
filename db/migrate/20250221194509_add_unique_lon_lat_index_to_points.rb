# frozen_string_literal: true

class AddUniqueLonLatIndexToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    return if index_exists?(:points, %i[lonlat timestamp user_id], name: 'index_points_on_lonlat_timestamp_user_id')

    add_index :points, %i[lonlat timestamp user_id], unique: true,
      name: 'index_points_on_lonlat_timestamp_user_id',
      algorithm: :concurrently
  end
end
