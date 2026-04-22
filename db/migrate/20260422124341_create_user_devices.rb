# frozen_string_literal: true

class CreateUserDevices < ActiveRecord::Migration[8.0]
  def change
    create_table :user_devices do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.integer :platform, null: false
      t.string :device_id, null: false
      t.string :device_name
      t.string :push_token
      t.string :app_version
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :user_devices, [:user_id, :device_id], unique: true
  end
end
