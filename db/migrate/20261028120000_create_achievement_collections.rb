# frozen_string_literal: true

class CreateAchievementCollections < ActiveRecord::Migration[8.1]
  def up
    create_table :achievement_selections, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :place, null: false, foreign_key: { on_delete: :cascade }
      t.string :timezone
      t.string :timezone_source
      t.decimal :timezone_latitude, precision: 10, scale: 7
      t.decimal :timezone_longitude, precision: 10, scale: 7
      t.timestamps
    end
    add_index :achievement_selections, %i[user_id place_id], unique: true, if_not_exists: true

    create_table :achievement_collection_states, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.bigint :revision, null: false, default: 1
      t.bigint :published_revision, null: false, default: 0
      t.datetime :requested_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.timestamps
    end

    create_table :achievement_collectibles, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :selection, foreign_key: { to_table: :achievement_selections, on_delete: :nullify }
      t.string :series, null: false
      t.string :subject_key, null: false
      t.integer :rule_version, null: false, default: 1
      t.integer :level, null: false, default: 0
      t.jsonb :data, null: false, default: {}
      t.datetime :earned_at
      t.datetime :revoked_at
      t.boolean :sharing_enabled, null: false, default: false
      t.uuid :sharing_uuid
      t.timestamps
    end
    add_index :achievement_collectibles, %i[user_id series subject_key], unique: true,
              name: 'index_achievement_collectibles_on_owner_series_subject', if_not_exists: true
    add_index :achievement_collectibles, :sharing_uuid, unique: true, if_not_exists: true

    create_table :achievement_collectible_events, if_not_exists: true do |t|
      t.references :collectible, null: false,
                    foreign_key: { to_table: :achievement_collectibles, on_delete: :cascade }
      t.string :kind, null: false
      t.integer :level, null: false
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :achievement_collectible_events, %i[collectible_id level], unique: true,
              where: "kind = 'earned'", name: 'index_achievement_collectible_first_earn', if_not_exists: true
    add_index :achievement_selections, :user_id, if_not_exists: true
    add_foreign_key :achievement_selections, :users, column: :user_id, on_delete: :cascade, if_not_exists: true
    add_index :achievement_selections, :place_id, if_not_exists: true
    add_foreign_key :achievement_selections, :places, column: :place_id, on_delete: :cascade, if_not_exists: true
    add_index :achievement_collection_states, :user_id, unique: true, if_not_exists: true
    add_foreign_key :achievement_collection_states, :users, column: :user_id, on_delete: :cascade, if_not_exists: true
    add_index :achievement_collectibles, :user_id, if_not_exists: true
    add_foreign_key :achievement_collectibles, :users, column: :user_id, on_delete: :cascade, if_not_exists: true
    add_index :achievement_collectibles, :selection_id, if_not_exists: true
    add_foreign_key :achievement_collectibles, :achievement_selections, column: :selection_id, on_delete: :nullify,
if_not_exists: true
    add_index :achievement_collectible_events, :collectible_id, if_not_exists: true
    add_foreign_key :achievement_collectible_events, :achievement_collectibles, column: :collectible_id,
on_delete: :cascade, if_not_exists: true
    execute File.read(Rails.root.join('db/achievement_collections_invalidation.sql'))
  end

  def down
    %w[visits places achievement_selections points tracks track_segments tags taggings
       achievement_city_selections].each do |table|
      next unless table_exists?(table)

      %w[insert update delete].each do |event|
        execute "DROP TRIGGER IF EXISTS achievement_collections_#{event} ON #{table}"
      end
    end
    execute 'DROP FUNCTION IF EXISTS invalidate_achievement_collections()'
    %i[achievement_collectible_events achievement_collectibles achievement_collection_states achievement_selections]
      .each { |table| drop_table table, if_exists: true }
  end
end
