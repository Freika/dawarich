# frozen_string_literal: true

class CreateDevices < ActiveRecord::Migration[8.0]
  def change
    create_table :devices do |t|
      t.string :name, null: false
      t.references :user, null: false, foreign_key: true
      t.string :identifier, null: false

      t.timestamps
    end
    add_index :devices, :identifier
  end
end
