# frozen_string_literal: true

class CreatePointDimensionTables < ActiveRecord::Migration[8.0]
  # The dimension tables are created outside a wrapping DDL transaction so a
  # blocked ALTER on points cannot hold them open. Each statement therefore
  # commits on its own, which is why every one of them is guarded by an
  # IF NOT EXISTS: a rerun after a lost lock race must skip straight to the
  # part that has not landed yet. The digest indexes are created separately
  # for the same reason — folding them into create_table would make a crash
  # between the table and its index unrecoverable on rerun, leaving
  # ON CONFLICT (digest) with no unique constraint to match.
  disable_ddl_transaction!

  # Adding a nullable column without a default is metadata-only, but it still
  # needs ACCESS EXCLUSIVE, and a queued request blocks every points reader and
  # writer behind it. Keep the wait short: the lock is either free almost
  # immediately or held by a long transaction a longer wait will not outlast.
  ADD_LOCK_TIMEOUT = '1s'
  ADD_MAX_ATTEMPTS = 5
  ADD_BACKOFF_SECONDS = 2

  def up
    create_table :point_sources, id: :serial, if_not_exists: true do |t|
      t.string :digest, limit: 32, null: false
      t.string :tracker_id
      t.string :topic
      t.string :ssid
      t.string :bssid
      t.integer :connection
      t.integer :trigger
      t.integer :battery_status
      t.text :inrids, array: true
      t.text :in_regions, array: true
      t.timestamps
    end
    add_index :point_sources, :digest, unique: true, if_not_exists: true

    create_table :point_motions, id: :serial, if_not_exists: true do |t|
      t.string :digest, limit: 32, null: false
      t.jsonb :motion_data, null: false
      t.timestamps
    end
    add_index :point_motions, :digest, unique: true, if_not_exists: true

    add_dimension_columns
  end

  def down
    execute 'ALTER TABLE points DROP COLUMN IF EXISTS source_id, DROP COLUMN IF EXISTS motion_id'
    drop_table :point_motions, if_exists: true
    drop_table :point_sources, if_exists: true
  end

  private

  # Both columns go in one ALTER so the lock is taken once instead of twice, and
  # so a rerun never sees only one of them present. SET LOCAL keeps the timeout
  # on the same backend as the ALTER under PgBouncer transaction pooling; a bare
  # SET can land on another connection and leave the ALTER unbounded.
  def add_dimension_columns
    attempts = 0

    begin
      attempts += 1
      transaction do
        execute "SET LOCAL lock_timeout = '#{ADD_LOCK_TIMEOUT}'"
        execute 'ALTER TABLE points ADD COLUMN IF NOT EXISTS source_id integer, ' \
                'ADD COLUMN IF NOT EXISTS motion_id integer'
      end
      Rails.logger.info '[CreatePointDimensionTables] source_id / motion_id added'
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::QueryAborted => e
      if attempts < ADD_MAX_ATTEMPTS
        Rails.logger.warn(
          "[CreatePointDimensionTables] could not acquire lock (attempt #{attempts}/#{ADD_MAX_ATTEMPTS}): #{e.message}"
        )
        sleep(ADD_BACKOFF_SECONDS * attempts)
        retry
      end

      # Deliberately no enqueue here. Aborting would fail the boot and replay
      # the migration on the next start, which is the crash loop the
      # mirror-image drop in 20260714090000_drop_legacy_lat_lon_from_points.rb
      # was rewritten to avoid — so boot continues either way. The handoff is
      # left to 20260816150200, which is the single place that decides what to
      # enqueue: if this migration and that one could both start work, the slow
      # DROP INDEX CONCURRENTLY between them gives a handoff job time to land
      # the columns first, and two backfill chains would then walk identical id
      # ranges at identical pace.
      Rails.logger.warn(
        "[CreatePointDimensionTables] could not acquire lock in #{ADD_MAX_ATTEMPTS} attempts; " \
        'leaving the columns to DataMigrations::AddPointDimensionColumnsJob'
      )
    end
  end
end
