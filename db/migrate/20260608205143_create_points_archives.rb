# frozen_string_literal: true

class CreatePointsArchives < ActiveRecord::Migration[8.0]
  def change
    create_table :points_archives do |t|
      t.bigint :user_id, null: false
      t.integer :year, null: false
      t.integer :month, null: false
      t.integer :chunk_number, null: false, default: 1
      t.integer :point_count, null: false
      t.string :point_ids_checksum, null: false
      t.jsonb :metadata, default: {}, null: false
      t.datetime :archived_at, null: false
      t.datetime :verified_at
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :points_archives, :user_id
    add_index :points_archives, %i[user_id year month]
    add_index :points_archives, :verified_at
    add_index :points_archives, :deleted_at
    add_foreign_key :points_archives, :users, validate: false
  end
end
