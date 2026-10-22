# frozen_string_literal: true

class AddUniqueIndexToVisits < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = 'idx_visits_user_started_at_place_unique'
  STRAGGLER_TABLE = 'visit_straggler_losers'

  def up
    drop_invalid_index(:visits, INDEX_NAME)
    return if index_name_exists?(:visits, INDEX_NAME)

    build_index
  rescue ActiveRecord::RecordNotUnique
    # A visit written between the dedupe migration and this build — by a worker
    # still running the previous release — fails the build. The dedupe is
    # already recorded in schema_migrations and will never run again, so
    # without this every later boot would fail on the same rows forever.
    drop_invalid_index(:visits, INDEX_NAME)
    collapse_stragglers
    build_index
  end

  def down
    return unless index_name_exists?(:visits, INDEX_NAME)

    remove_index :visits, name: INDEX_NAME, algorithm: :concurrently
  end

  private

  def build_index
    add_index :visits, %i[user_id started_at place_id],
              unique: true,
              algorithm: :concurrently,
              name: INDEX_NAME
  end

  # Set-based rather than batched: this only ever runs for the handful of rows
  # written during the race, not for the instance's whole history.
  #
  # The losers are materialised ONCE. Re-deriving them per statement re-reads
  # live table state, so a duplicate written between the point reassignment and
  # the deletes — the very race this rescue exists for — would be deleted
  # without its points ever being moved, orphaning them or failing the FK.
  def collapse_stragglers
    execute("DROP TABLE IF EXISTS #{STRAGGLER_TABLE}")
    execute("CREATE UNLOGGED TABLE #{STRAGGLER_TABLE} AS #{losers_sql}")

    execute(<<~SQL.squish)
      UPDATE points SET visit_id = #{STRAGGLER_TABLE}.keeper
      FROM #{STRAGGLER_TABLE} WHERE points.visit_id = #{STRAGGLER_TABLE}.id
    SQL
    execute("DELETE FROM place_visits WHERE visit_id IN (SELECT id FROM #{STRAGGLER_TABLE})")
    execute("DELETE FROM visits WHERE id IN (SELECT id FROM #{STRAGGLER_TABLE})")
  ensure
    execute("DROP TABLE IF EXISTS #{STRAGGLER_TABLE}")
  end

  def losers_sql
    <<~SQL.squish
      SELECT v.id, g.keeper
      FROM visits v
      JOIN (
        SELECT user_id, started_at, place_id, min(id) AS keeper
        FROM visits
        WHERE place_id IS NOT NULL
        GROUP BY user_id, started_at, place_id
        HAVING count(*) > 1
      ) g
        ON v.user_id = g.user_id
       AND v.started_at = g.started_at
       AND v.place_id = g.place_id
      WHERE v.id <> g.keeper
    SQL
  end

  def drop_invalid_index(table, name)
    invalid = select_value(<<~SQL.squish)
      SELECT 1 FROM pg_class c
      JOIN pg_index i ON i.indexrelid = c.oid
      WHERE c.relname = '#{name}' AND i.indisvalid = false
    SQL
    return if invalid.nil?

    remove_index table, name: name, algorithm: :concurrently
  end
end
