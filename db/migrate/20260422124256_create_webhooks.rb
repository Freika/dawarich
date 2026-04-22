# frozen_string_literal: true

class CreateWebhooks < ActiveRecord::Migration[8.0]
  def change
    create_table :webhooks do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.string :url, null: false
      t.string :secret, null: false
      t.integer :event_types, array: true, default: [0, 1], null: false
      t.bigint :area_ids, array: true, default: [], null: false
      t.boolean :active, null: false, default: true
      t.datetime :last_delivery_at
      t.datetime :last_success_at
      t.integer :consecutive_failures, null: false, default: 0

      t.timestamps
    end
  end
end
