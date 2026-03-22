# frozen_string_literal: true

class AddArchivalPartialIndexesToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Speeds up archive_user query: find unarchived points with raw_data to archive
    add_index :points, %i[user_id id],
              where: "raw_data_archived = false AND raw_data != '{}'",
              name: 'index_points_on_unarchived',
              algorithm: :concurrently,
              if_not_exists: true

    # Speeds up clear_user query: find archived points with raw_data still to clear
    add_index :points, %i[user_id id],
              where: "raw_data_archived = true AND raw_data != '{}'",
              name: 'index_points_on_archived_uncleared',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
