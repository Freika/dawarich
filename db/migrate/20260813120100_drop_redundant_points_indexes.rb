# frozen_string_literal: true

class DropRedundantPointsIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    remove_index :points, name: 'index_points_on_user_id', algorithm: :concurrently, if_exists: true
    remove_index :points, name: 'index_points_on_track_id', algorithm: :concurrently, if_exists: true
    remove_index :points, name: 'index_points_on_user_id_and_empty_geodata',
                 algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :points, :user_id, name: 'index_points_on_user_id',
                                 algorithm: :concurrently, if_not_exists: true
    add_index :points, :track_id, name: 'index_points_on_track_id',
                                  algorithm: :concurrently, if_not_exists: true
    add_index :points, %i[user_id geodata], name: 'index_points_on_user_id_and_empty_geodata',
                                            where: "geodata = '{}'::jsonb",
                                            algorithm: :concurrently, if_not_exists: true
  end
end
