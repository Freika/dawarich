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
  # writer behind it, so each wait stays bounded.
  ADD_LOCK_TIMEOUT = '5s'
  ADD_MAX_ATTEMPTS = 5

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

    add_dimension_column
  end

  def down
    execute 'ALTER TABLE points DROP COLUMN IF EXISTS source_id'
    drop_table :point_sources, if_exists: true
  end

  private

  # SET LOCAL keeps the timeout on the same backend as the ALTER under PgBouncer
  # transaction pooling; a bare SET can land on another connection and leave the
  # ALTER unbounded. Losing every attempt fails the migration so the next boot
  # retries it: recording it without the column left instances short of
  # source_id for good (#3972).
  def add_dimension_column
    attempts = 0

    begin
      attempts += 1
      transaction do
        execute "SET LOCAL lock_timeout = '#{ADD_LOCK_TIMEOUT}'"
        execute 'ALTER TABLE points ADD COLUMN IF NOT EXISTS source_id integer'
      end
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::QueryAborted
      raise if attempts >= ADD_MAX_ATTEMPTS

      sleep(attempts * 5)
      retry
    end
  end
end
