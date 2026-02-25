# frozen_string_literal: true

class AddArchivalColumnsToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :points, :raw_data_archived, :boolean, default: false, null: false
    add_column :points, :raw_data_archive_id, :bigint, null: true

    add_index :points, :raw_data_archived,
              where: 'raw_data_archived = true',
              name: 'index_points_on_archived_true',
              algorithm: :concurrently
    add_index :points, :raw_data_archive_id,
              algorithm: :concurrently

    add_foreign_key :points, :points_raw_data_archives,
                    column: :raw_data_archive_id,
                    on_delete: :nullify, # Don't delete points if archive deleted
                    validate: false
  end
end
