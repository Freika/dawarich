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
  SWAP_MAX_ATTEMPTS = 3
  ROWS_PER_MINUTE = 1_000_000
  V1_FOREIGN_KEYS = [
    'ALTER TABLE points ADD CONSTRAINT fk_points_v1_user FOREIGN KEY (user_id) REFERENCES users(id) NOT VALID',
    'ALTER TABLE points ADD CONSTRAINT fk_points_v1_track FOREIGN KEY (track_id) REFERENCES tracks(id) NOT VALID',
    'ALTER TABLE points ADD CONSTRAINT fk_points_v1_visit FOREIGN KEY (visit_id) REFERENCES visits(id) NOT VALID',
    'ALTER TABLE points ADD CONSTRAINT fk_points_v1_raw_data_archive FOREIGN KEY (raw_data_archive_id) ' \
    'REFERENCES points_raw_data_archives(id) ON DELETE RESTRICT NOT VALID'
  ].freeze

  def up
    # A boot interrupted after the swap resumes here.
    return finish_after_swap unless v1_points?

    raise 'points_v2 is missing - CreatePointsV2 (20260901100000) must run first' unless table_exists?(:points_v2)

    log_preflight

    job = DataMigrations::RewritePointsV2Job.new
    job.run_phases_through_copy
    job.finish

    swap_with_retries
    finish_after_swap
    Rails.logger.info(
      '[RewritePointsToV2] swap complete. The old table is kept as points_legacy_d ' \
      'for rollback; it will be dropped in a follow-up release (or manually: ' \
      'DROP TABLE points_legacy_d;)'
    )
  end

  # The idle v2 table keeps no foreign keys (they would block every parent
  # deletion) and no data or secondary indexes (the next migrate copies from
  # scratch, and a clean copy beats upserting through eight indexes); the
  # restored v1 table gets its four keys back as NOT VALID.
  def down
    unless table_exists?(:points_legacy_d)
      raise ActiveRecord::IrreversibleMigration, 'points_legacy_d is gone - cannot restore v1'
    end

    schema_steps.drop_foreign_keys('points')

    connection.transaction do
      execute("SET LOCAL lock_timeout = '#{SWAP_LOCK_TIMEOUT}'")
      execute('SET LOCAL statement_timeout = 0')
      execute('ALTER TABLE points RENAME TO points_v2')
      rename_indexes_of('points_v2') { |name| name.sub('points', 'points_v2')[0, 63] }
      drop_secondary_indexes_of('points_v2')
      execute('TRUNCATE points_v2')
      execute('ALTER TABLE points_legacy_d RENAME TO points')
      rename_indexes_of('points') { |name| name.sub('_legacy_d', '') }
      execute('ALTER SEQUENCE points_id_seq OWNED BY points.id')
    end
    clear_caches

    V1_FOREIGN_KEYS.each { |ddl| schema_steps.with_lock_timeout { execute(ddl) } }
    Rails.logger.info('[RewritePointsToV2] rolled back to the v1 table; the next migrate copies from scratch')
  end

  private

  def v1_points?
    column_exists?(:points, :country_name)
  end

  def schema_steps
    @schema_steps ||= Points::Rewrite::SchemaSteps.new(connection)
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

  # Both steps are idempotent, so a boot interrupted here just runs them again.
  def finish_after_swap
    schema_steps.drop_foreign_keys('points_legacy_d') if table_exists?(:points_legacy_d)
    schema_steps.validate_foreign_keys
  end

  # A lock wait or a deadlock (the in-swap ADD CONSTRAINT wants the parent
  # tables while visit or track creation holds one and wants points) is
  # transient: back off and try the whole swap again.
  def swap_with_retries
    attempts = 0
    begin
      attempts += 1
      swap!
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked => e
      if attempts < SWAP_MAX_ATTEMPTS
        sleep(attempts)
        retry
      end
      raise e.class,
            '[RewritePointsToV2] could not complete the swap on points after ' \
            "#{SWAP_MAX_ATTEMPTS} attempts (#{e.message.lines.first.strip}). Re-run the migration " \
            '(the copy is already done; only the instant swap remains).'
    end
  end

  def swap!
    capture = Points::Rewrite::ChangeCapture.new(connection)

    connection.transaction do
      execute("SET LOCAL lock_timeout = '#{SWAP_LOCK_TIMEOUT}'")
      execute('SET LOCAL statement_timeout = 0')
      lock_points!

      capture.drain_fully if capture.pending_count.positive? || capture.installed?
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

  def drop_secondary_indexes_of(table)
    connection.select_values(<<~SQL).each { |index| execute(%(DROP INDEX "#{index}")) }
      SELECT indexname FROM pg_indexes
      WHERE tablename = #{connection.quote(table)} AND indexname <> '#{table}_pkey'
    SQL
  end

  # Only the connection-level cache: touching Point here would load the
  # model against whichever schema happens to be live, and each app process
  # refreshes its own column cache on restart anyway.
  def clear_caches
    connection.schema_cache.clear!
  end
end
