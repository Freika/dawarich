# frozen_string_literal: true

class CreateAchievementUnlockEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :achievement_unlock_events do |table|
      table.references :user, null: false, foreign_key: { on_delete: :cascade }
      table.string :kind, null: false
      table.string :key, null: false
      table.datetime :claimed_at
      table.string :claim_token
      table.datetime :seen_at
      table.timestamps
    end

    add_index :achievement_unlock_events, %i[user_id kind key], unique: true,
              name: 'index_achievement_unlock_events_on_user_kind_key'
    add_index :achievement_unlock_events, %i[user_id id],
              where: 'seen_at IS NULL', name: 'index_achievement_unlock_events_pending'
  end
end
