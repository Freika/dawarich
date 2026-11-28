# frozen_string_literal: true

# One row per product-analytics fact that must be counted at most once
# (import_succeeded per upload, first_map_data_viewed per account). The unique
# dedup_key makes a retried job or a second device record nothing new.
class CreateAnalyticsEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :analytics_events, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.integer :event, null: false
      t.string :dedup_key, null: false
      t.jsonb :properties, null: false, default: {}
      t.datetime :delivered_at
      t.timestamps
    end

    add_index :analytics_events, :dedup_key, unique: true, if_not_exists: true
  end

  def down
    drop_table :analytics_events, if_exists: true
  end
end
