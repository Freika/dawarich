# frozen_string_literal: true

class CreatePosters < ActiveRecord::Migration[8.0]
  def change
    create_table :posters, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end
  end
end
