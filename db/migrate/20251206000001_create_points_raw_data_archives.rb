# frozen_string_literal: true

class CreatePointsRawDataArchives < ActiveRecord::Migration[8.0]
  def change
    create_table :points_raw_data_archives do |t|
      t.bigint :user_id, null: false
      t.integer :year, null: false
      t.integer :month, null: false
      t.integer :chunk_number, null: false, default: 1
      t.integer :point_count, null: false
      t.string :point_ids_checksum, null: false
      t.jsonb :metadata, default: {}, null: false
      t.datetime :archived_at, null: false

      t.timestamps
    end

    add_index :points_raw_data_archives, :user_id
    add_index :points_raw_data_archives, [:user_id, :year, :month]
    add_index :points_raw_data_archives, :archived_at
    add_foreign_key :points_raw_data_archives, :users, validate: false
  end
end
