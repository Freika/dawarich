# frozen_string_literal: true

# Immutable derived rows inherit their generation's timestamps.
# rubocop:disable Rails/CreateTableWithTimestamps
class CreateExploration < ActiveRecord::Migration[8.1]
  def up
    create_table :exploration_datasets, if_not_exists: true do |t|
      t.string :version, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :completed_at
      t.timestamps
    end
    add_index :exploration_datasets, :version, unique: true, if_not_exists: true
    create_table :exploration_territories, if_not_exists: true do |t|
      t.references :dataset, null: false, foreign_key: { to_table: :exploration_datasets, on_delete: :cascade }
      t.string :code, null: false
      t.string :name, null: false
      t.multi_polygon :boundary, srid: 4326, null: false
      t.multi_polygon :land, srid: 4326, null: false
      t.float :land_area, null: false
    end
    add_index :exploration_territories, %i[dataset_id code], unique: true, if_not_exists: true
    add_index :exploration_territories, :land, using: :gist, if_not_exists: true
    add_index :exploration_territories, :boundary, using: :gist, if_not_exists: true
    create_table :exploration_snapshots, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :dataset, null: false, foreign_key: { to_table: :exploration_datasets }
      t.bigint :revision, null: false
      t.datetime :completed_at
      t.timestamps
    end
    create_table :exploration_states, if_not_exists: true do |t|
      t.references :user, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.bigint :revision, null: false, default: 1
      t.bigint :published_revision, null: false, default: 0
      t.references :snapshot, foreign_key: { to_table: :exploration_snapshots, on_delete: :nullify }
      t.datetime :requested_at
      t.datetime :failed_at
      t.timestamps
    end
    create_table :exploration_cells, id: :string, if_not_exists: true do |t|
      t.multi_polygon :geom, srid: 4326, null: false
    end
    create_table :exploration_cell_coverages, if_not_exists: true do |t|
      t.references :dataset, null: false, foreign_key: { to_table: :exploration_datasets, on_delete: :cascade }
      t.string :cell_id, null: false
      t.jsonb :areas, null: false, default: {}
    end
    add_index :exploration_cell_coverages, %i[dataset_id cell_id], unique: true, if_not_exists: true
    add_foreign_key :exploration_cell_coverages, :exploration_cells, column: :cell_id, if_not_exists: true
    create_table :exploration_openings, if_not_exists: true do |t|
      t.references :snapshot, null: false, foreign_key: { to_table: :exploration_snapshots, on_delete: :cascade }
      t.string :cell_id, null: false
      t.bigint :first_timestamp, null: false
      t.bigint :point_id, null: false
    end
    add_index :exploration_openings, %i[snapshot_id cell_id], unique: true, if_not_exists: true
    add_index :exploration_openings, %i[snapshot_id first_timestamp], if_not_exists: true
    create_table :exploration_country_totals, if_not_exists: true do |t|
      t.references :snapshot, null: false, foreign_key: { to_table: :exploration_snapshots, on_delete: :cascade }
      t.references :territory, null: false, foreign_key: { to_table: :exploration_territories }
      t.float :opened_area, null: false, default: 0
      t.boolean :visited, null: false, default: false
    end
    add_index :exploration_country_totals, %i[snapshot_id territory_id], unique: true, if_not_exists: true
    add_index :exploration_territories, :dataset_id, if_not_exists: true
    add_foreign_key :exploration_territories, :exploration_datasets, column: :dataset_id, on_delete: :cascade,
if_not_exists: true
    add_index :exploration_snapshots, :user_id, if_not_exists: true
    add_foreign_key :exploration_snapshots, :users, column: :user_id, on_delete: :cascade, if_not_exists: true
    add_index :exploration_snapshots, :dataset_id, if_not_exists: true
    add_foreign_key :exploration_snapshots, :exploration_datasets, column: :dataset_id, if_not_exists: true
    add_index :exploration_states, :user_id, unique: true, if_not_exists: true
    add_foreign_key :exploration_states, :users, column: :user_id, on_delete: :cascade, if_not_exists: true
    add_index :exploration_states, :snapshot_id, if_not_exists: true
    add_foreign_key :exploration_states, :exploration_snapshots, column: :snapshot_id, on_delete: :nullify,
if_not_exists: true
    add_index :exploration_cell_coverages, :dataset_id, if_not_exists: true
    add_foreign_key :exploration_cell_coverages, :exploration_datasets, column: :dataset_id, on_delete: :cascade,
if_not_exists: true
    add_index :exploration_openings, :snapshot_id, if_not_exists: true
    add_foreign_key :exploration_openings, :exploration_snapshots, column: :snapshot_id, on_delete: :cascade,
if_not_exists: true
    add_index :exploration_country_totals, :snapshot_id, if_not_exists: true
    add_foreign_key :exploration_country_totals, :exploration_snapshots, column: :snapshot_id, on_delete: :cascade,
if_not_exists: true
    add_index :exploration_country_totals, :territory_id, if_not_exists: true
    add_foreign_key :exploration_country_totals, :exploration_territories, column: :territory_id, if_not_exists: true
    execute File.read(Rails.root.join('db/exploration_invalidation.sql'))
  end

  def down
    %w[points tracks track_segments].each do |table|
      %w[insert update delete].each do |event|
        execute "DROP TRIGGER IF EXISTS exploration_#{table}_#{event} ON #{table}"
      end
    end
    execute 'DROP FUNCTION IF EXISTS invalidate_exploration()'
    %i[exploration_country_totals exploration_openings exploration_cell_coverages exploration_cells
       exploration_states exploration_snapshots exploration_territories exploration_datasets].each do |table|
      drop_table table, if_exists: true
    end
  end
end
# rubocop:enable Rails/CreateTableWithTimestamps
