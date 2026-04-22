# frozen_string_literal: true

class CreateWebhookDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_deliveries do |t|
      t.references :webhook, null: false, foreign_key: true, index: true
      t.references :geofence_event, null: false, foreign_key: true, index: true
      t.integer :status, null: false, default: 0
      t.integer :attempt_count, null: false, default: 0
      t.integer :response_status
      t.text :response_body
      t.string :error_message
      t.datetime :delivered_at

      t.timestamps
    end

    add_index :webhook_deliveries, [:webhook_id, :created_at], order: { created_at: :desc }
  end
end
