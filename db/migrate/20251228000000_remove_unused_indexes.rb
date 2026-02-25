# frozen_string_literal: true

class RemoveUnusedIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    remove_index :points, :geodata, algorithm: :concurrently, if_exists: true
    remove_index :points, %i[latitude longitude], algorithm: :concurrently, if_exists: true
    remove_index :points, :altitude, algorithm: :concurrently, if_exists: true
    remove_index :points, :city, algorithm: :concurrently, if_exists: true
    remove_index :points, :country_name, algorithm: :concurrently, if_exists: true
    remove_index :points, :battery_status, algorithm: :concurrently, if_exists: true
    remove_index :points, :connection, algorithm: :concurrently, if_exists: true
    remove_index :points, :trigger, algorithm: :concurrently, if_exists: true
    remove_index :points, :battery, algorithm: :concurrently, if_exists: true
    remove_index :points, :country, algorithm: :concurrently, if_exists: true
    remove_index :points, :external_track_id, algorithm: :concurrently, if_exists: true
  end
end
