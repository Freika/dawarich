# frozen_string_literal: true

# Release D, stage 2: run the online rewrite and atomically swap points_v2
# in as `points`. The heavy copy happens before any lock is taken; the swap
# transaction drains the last captured changes under ACCESS EXCLUSIVE, so a
# write that raced the copy either lands in the drained delta or blocks on
# the lock and re-resolves to the new table after commit (Postgres
# invalidates cached plans on DDL). The foreign keys go in NOT VALID inside
# that same transaction, after the drain, and are validated once the new
# table is live; the legacy table loses its keys the same way.
#
# Cloud pre-runs the job manually in a window; this migration then sees the
# v2 shape and only finishes the post-swap steps. Self-hosted runs it
# unattended on boot: the copy is resumable, so a container restart mid-walk
# continues rather than starting over, and a lost lock race retries without
# wedging boot.
class RewritePointsToV2 < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  SWAP_LOCK_TIMEOUT = '2s'
  SWAP_STATEMENT_TIMEOUT = '30s'
  MAX_FINAL_CHANGES = 10_000
  SWAP_MAX_ATTEMPTS = 3
  ROWS_PER_MINUTE = 1_000_000

  def up
    # A boot interrupted after the swap resumes here.
    return finish_after_swap unless v1_points?

    raise 'points_v2 is missing - CreatePointsV2 (20260901100000) must run first' unless table_exists?(:points_v2)

    ensure_source_columns!
    log_preflight

    job = DataMigrations::RewritePointsV2Job.new
    job.run_phases_through_copy
    job.finish

    swap_with_retries
    finish_after_swap
    Rails.logger.info(
      '[RewritePointsToV2] swap complete. The old table is kept as points_legacy_d ' \
      'for supervised recovery. Compare row counts and required data before scheduling its cleanup.'
    )
  end

  def down
    unless v1_points?
      raise ActiveRecord::IrreversibleMigration,
            'points v2 may contain writes absent from points_legacy_d; restore requires supervised recovery'
    end

    Points::Rewrite::ChangeCapture.new(connection).drop
    execute('DROP TABLE IF EXISTS points_v2_rewrite_state')
  end

  private

  def v1_points?
    column_exists?(:points, :tracker_id)
  end

  def schema_steps
    @schema_steps ||= Points::Rewrite::SchemaSteps.new(connection)
  end

  # CreatePointDimensionTables (20260816150000) is allowed to lose the race for
  # points' ACCESS EXCLUSIVE lock and leave the column to
  # DataMigrations::AddPointDimensionColumnsJob — autovacuum on a freshly
  # written points table is enough to take that branch. That job runs on
  # Sidekiq, a different container on a self-hosted install and not
  # necessarily up, while this migration runs inline in the same boot: without
  # the column the rewrite dies on PG::UndefinedColumn and cancels every later
  # migration, so the web container never starts. Take the lock here instead,
  # under the same retried discipline the rest of the swap uses.
  def ensure_source_columns!
    schema_steps.with_lock_timeout do
      execute('ALTER TABLE points ADD COLUMN source_id integer') unless column_exists?(:points, :source_id)
      unless column_exists?(:points, :lock_version)
        execute('ALTER TABLE points ADD COLUMN lock_version integer NOT NULL DEFAULT 0')
      end
      {
        country: 'character varying', country_name: 'character varying',
        lock_version: 'integer NOT NULL DEFAULT 0', mode: 'integer',
        ping: 'character varying', external_track_id: 'character varying'
      }.each do |column, type|
        execute("ALTER TABLE points_v2 ADD COLUMN #{column} #{type}") unless column_exists?(:points_v2, column)
      end
    end
    connection.schema_cache.clear!
  rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked => e
    raise e.class,
          '[RewritePointsToV2] the lock to prepare points columns could not be ' \
          "acquired (#{e.message.lines.first.strip}). Re-run the migration when traffic is quiet."
  end

  def log_preflight
    size = connection.select_value("SELECT pg_size_pretty(pg_total_relation_size('points'))")
    rows = connection.select_value("SELECT reltuples::bigint FROM pg_class WHERE oid = 'points'::regclass").to_i
    minutes = rows.negative? ? 'unknown' : (rows.to_f / ROWS_PER_MINUTE).ceil
    Rails.logger.info(
      "[RewritePointsToV2] rewriting points: ~#{rows.negative? ? '?' : rows} rows, #{size} incl. indexes; " \
      "expect roughly #{minutes} min at ~1M rows/min (progress lines follow). The database volume " \
      "needs roughly #{size} free; Postgres usually runs in another container, so this cannot be " \
      'verified from here. If the copy fails on disk-full, free space and restart - the walk ' \
      'resumes from its cursor.'
    )
  end

  # Every step is idempotent, so a boot interrupted here just runs them
  # again; re-adding missing keys also repairs a rollback that failed after
  # dropping them.
  def finish_after_swap
    schema_steps.drop_foreign_keys('points_legacy_d') if table_exists?(:points_legacy_d)
    schema_steps.with_lock_timeout { schema_steps.add_foreign_keys(table: 'points') }
    schema_steps.validate_foreign_keys
  end

  def swap_with_retries
    with_lock_retries('complete the swap on points') { swap! }
  end

  # A lock wait or a deadlock (the in-swap ADD CONSTRAINT wants the parent
  # tables while visit or track creation holds one and wants points) is
  # transient: back off and try the whole step again.
  def with_lock_retries(label)
    attempts = 0
    begin
      attempts += 1
      yield
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked => e
      if attempts < SWAP_MAX_ATTEMPTS
        sleep(attempts)
        retry
      end
      raise e.class,
            "[RewritePointsToV2] could not #{label} after #{SWAP_MAX_ATTEMPTS} attempts " \
            "(#{e.message.lines.first.strip}). Re-run the migration; every step so far is kept."
    end
  end

  def swap!
    capture = Points::Rewrite::ChangeCapture.new(connection)

    connection.transaction do
      execute("SET LOCAL lock_timeout = '#{SWAP_LOCK_TIMEOUT}'")
      execute("SET LOCAL statement_timeout = '#{SWAP_STATEMENT_TIMEOUT}'")
      lock_points!

      pending = capture.pending_count
      if pending > MAX_FINAL_CHANGES
        raise ActiveRecord::MigrationError,
              "#{pending} point changes accumulated before the swap; retry the migration to drain them without " \
              'holding the points write lock'
      end
      capture.drain_fully if pending.positive? || capture.installed?
      capture.drop
      execute('DROP TABLE IF EXISTS points_v2_rewrite_state')

      execute('ALTER TABLE points RENAME TO points_legacy_d')
      rename_indexes_of('points_legacy_d') { |name| "#{name}_legacy_d"[0, 63] }

      execute('ALTER TABLE points_v2 RENAME TO points')
      rename_indexes_of('points') { |name| name.sub('_v2', '') }
      schema_steps.add_foreign_keys(table: 'points')
      execute('ALTER SEQUENCE points_id_seq OWNED BY points.id')
    end
    clear_caches
  end

  def lock_points!
    execute('LOCK TABLE points IN ACCESS EXCLUSIVE MODE')
  end

  def rename_indexes_of(table)
    connection.select_values(
      "SELECT indexname FROM pg_indexes WHERE tablename = #{connection.quote(table)}"
    ).each do |index|
      new_name = yield(index)
      next if new_name == index

      execute(%(ALTER INDEX "#{index}" RENAME TO "#{new_name}"))
    end
  end

  # Only the connection-level cache: touching Point here would load the
  # model against whichever schema happens to be live, and each app process
  # refreshes its own column cache on restart anyway.
  def clear_caches
    connection.schema_cache.clear!
  end
end
