# frozen_string_literal: true

class CreateInstanceSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :instance_settings do |t|
      t.string :key, null: false
      t.jsonb :value
      t.text :encrypted_value

      t.timestamps
    end

    add_index :instance_settings, :key, unique: true
  end
end
