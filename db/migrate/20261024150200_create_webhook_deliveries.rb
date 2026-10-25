# frozen_string_literal: true

class CreateWebhookDeliveries < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:webhook_deliveries)

    create_table :webhook_deliveries do |t|
      t.references :webhook, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :geofence_event, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.integer :status, null: false, default: 0
      t.integer :attempt_count, null: false, default: 0
      t.integer :response_status
      t.text :response_body
      t.string :error_message
      t.datetime :delivered_at

      t.timestamps
    end

    add_index :webhook_deliveries, %i[webhook_id created_at], order: { created_at: :desc }
    add_index :webhook_deliveries, :created_at
  end

  def down
    drop_table :webhook_deliveries, if_exists: true
  end
end
