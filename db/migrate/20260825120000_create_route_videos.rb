# frozen_string_literal: true

class CreateRouteVideos < ActiveRecord::Migration[8.0]
  def change
    create_table :route_videos, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :settings, null: false, default: {}
      t.datetime :expired_at

      t.timestamps
    end

    add_index :route_videos, %i[user_id created_at], if_not_exists: true
  end
end
