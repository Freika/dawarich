# frozen_string_literal: true

class CreateNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :notifications do |t|
      t.string :title, null: false
      t.text :content, null: false
      t.references :user, null: false, foreign_key: true
      t.integer :kind, null: false, default: 0
      t.datetime :read_at

      t.timestamps
    end
    add_index :notifications, :kind
  end
end
