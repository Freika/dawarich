# frozen_string_literal: true

class CreatePointsPostIngestBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :points_post_ingest_batches do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :start_at, null: false
      t.bigint :end_at, null: false

      t.timestamps
    end

    add_index :points_post_ingest_batches, %i[user_id start_at end_at], unique: true
  end
end
