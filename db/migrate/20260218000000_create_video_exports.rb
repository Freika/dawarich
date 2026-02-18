# frozen_string_literal: true

class CreateVideoExports < ActiveRecord::Migration[8.0]
  def change
    create_table :video_exports do |t|
      t.references :user, null: false, foreign_key: true
      t.references :track, null: true, foreign_key: true
      t.datetime :start_at, null: false
      t.datetime :end_at, null: false
      t.integer :status, default: 0, null: false
      t.jsonb :config, default: {}, null: false
      t.string :error_message
      t.datetime :processing_started_at
      t.timestamps
    end

    add_index :video_exports, :status
    add_index :video_exports, %i[user_id status]
  end
end
