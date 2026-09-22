# frozen_string_literal: true

class CreateAchievementTables < ActiveRecord::Migration[8.0]
  def up
    unless table_exists?(:achievement_progresses)
      create_table :achievement_progresses do |t|
        t.references :user, null: false, foreign_key: true, index: false
        t.string :achievement_key, null: false
        t.jsonb :state, null: false, default: {}
        t.boolean :sharing_enabled, null: false, default: false
        t.string :sharing_uuid
        t.timestamps
      end

      add_index :achievement_progresses, %i[user_id achievement_key], unique: true
      add_index :achievement_progresses, :sharing_uuid, unique: true
    end

    return if table_exists?(:user_achievements)

    create_table :user_achievements do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :achievement_key, null: false
      t.datetime :earned_at, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :user_achievements, %i[user_id achievement_key], unique: true
  end

  def down
    drop_table :achievement_progresses, if_exists: true
    drop_table :user_achievements, if_exists: true
  end
end
