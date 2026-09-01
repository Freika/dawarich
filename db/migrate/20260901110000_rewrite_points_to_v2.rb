# frozen_string_literal: true

# Release D, stage 2: run the online rewrite and atomically swap points_v2
# in as `points`. The heavy copy happens before any lock is taken; the swap
# transaction drains the last captured changes under ACCESS EXCLUSIVE, so a
# write that raced the copy either lands in the drained delta or blocks on
# the lock and re-resolves to the new table after commit (Postgres
# invalidates cached plans on DDL).
#
# Cloud pre-runs the job + swap manually in a window; this migration then
# sees the v2 shape and no-ops. Self-hosted runs it unattended on boot: the
# copy is resumable, so a container restart mid-walk continues rather than
# starting over, and a lost lock race retries without wedging boot.
class RewritePointsToV2 < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  SWAP_LOCK_TIMEOUT = '2s'
  SWAP_MAX_ATTEMPTS = 3

  V1_FOREIGN_KEYS = [
    'ALTER TABLE points ADD CONSTRAINT fk_points_v1_user FOREIGN KEY (user_id) REFERENCES users(id) NOT VALID',
    'ALTER TABLE points ADD CONSTRAINT fk_points_v1_track FOREIGN KEY (track_id) REFERENCES tracks(id) NOT VALID',
    'ALTER TABLE points ADD CONSTRAINT fk_points_v1_visit FOREIGN KEY (visit_id) REFERENCES visits(id) NOT VALID',
    'ALTER TABLE points ADD CONSTRAINT fk_points_v1_raw_data_archive FOREIGN KEY (raw_data_archive_id) ' \
    'REFERENCES points_raw_data_archives(id) ON DELETE RESTRICT NOT VALID'
  ].freeze

  def up
    # A boot interrupted between the swap and the validation scans resumes here.
    return schema_steps.validate_foreign_keys unless v1_points?

    raise 'points_v2 is missing - CreatePointsV2 (20260901100000) must run first' unless table_exists?(:points_v2)

    log_preflight

    job = DataMigrations::RewritePointsV2Job.new
    job.run_phases_through_copy
    job.finish

    swap_with_retries
    schema_steps.validate_foreign_keys
    Rails.logger.info(
      '[RewritePointsToV2] swap complete. The old table is kept as points_legacy_d ' \
      'for rollback; it will be dropped in a follow-up release (or manually: ' \
      'DROP TABLE points_legacy_d;)'
    )
  end

  # The v2 table keeps no foreign keys while it sits idle (they would block
  # every parent deletion), and the restored v1 table gets its four back as
  # NOT VALID so the app runs with referential integrity again.
  def down
    unless table_exists?(:points_legacy_d)
      raise ActiveRecord::IrreversibleMigration, 'points_legacy_d is gone - cannot restore v1'
    end

    connection.transaction do
      execute("SET LOCAL lock_timeout = '#{SWAP_LOCK_TIMEOUT}'")
      execute('SET LOCAL statement_timeout = 0')
      execute('ALTER TABLE points RENAME TO points_v2')
      rename_indexes_of('points_v2') { |name| name.sub('points', 'points_v2')[0, 63] }
      drop_foreign_keys_of('points_v2')
      execute('ALTER TABLE points_legacy_d RENAME TO points')
      rename_indexes_of('points') { |name| name.sub('_legacy_d', '') }
      V1_FOREIGN_KEYS.each { |ddl| execute(ddl) }
      execute('ALTER SEQUENCE points_id_seq OWNED BY points.id')
    end
    clear_caches
  end

  private

  def v1_points?
    column_exists?(:points, :country_name)
  end

  def schema_steps
    @schema_steps ||= Points::Rewrite::SchemaSteps.new(connection)
  end

  ROWS_PER_MINUTE = 1_000_000

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

  def swap_with_retries
    attempts = 0
    begin
      attempts += 1
      swap!
    rescue ActiveRecord::LockWaitTimeout
      if attempts < SWAP_MAX_ATTEMPTS
        sleep(attempts)
        retry
      end
      raise ActiveRecord::LockWaitTimeout,
            '[RewritePointsToV2] could not win the ACCESS EXCLUSIVE race on points after ' \
            "#{SWAP_MAX_ATTEMPTS} attempts. Re-run the migration (the copy is already done; " \
            'only the instant swap remains).'
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
      drop_foreign_keys_of('points_legacy_d')

      execute('ALTER TABLE points_v2 RENAME TO points')
      rename_indexes_of('points') { |name| name.sub('_v2', '') }
      rename_constraints_of('points', from: '_v2', to: '')
      execute('ALTER SEQUENCE points_id_seq OWNED BY points.id')
    end
    clear_caches
  end

  def lock_points!
    execute('LOCK TABLE points IN ACCESS EXCLUSIVE MODE')
  end

  # The legacy table only exists for rollback; keeping its foreign keys would
  # block every track, visit, archive and user deletion for the retention window.
  def drop_foreign_keys_of(table)
    connection.select_values(<<~SQL).each do |constraint|
      SELECT conname FROM pg_constraint
      WHERE conrelid = #{connection.quote(table)}::regclass AND contype = 'f'
    SQL
      execute(%(ALTER TABLE #{table} DROP CONSTRAINT "#{constraint}"))
    end
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

  def rename_constraints_of(table, from:, to:)
    names = connection.select_values(<<~SQL)
      SELECT conname FROM pg_constraint
      WHERE conrelid = #{connection.quote(table)}::regclass AND conname LIKE 'fk\\_points%'
    SQL
    names.each do |constraint|
      target = from.empty? ? constraint.sub('fk_points_', "fk_points#{to}_") : constraint.sub(from, to)
      next if target == constraint || names.include?(target)

      execute(%(ALTER TABLE #{table} RENAME CONSTRAINT "#{constraint}" TO "#{target}"))
    end
  end

  # Only the connection-level cache: touching Point here would load the
  # model against whichever schema happens to be live, and each app process
  # refreshes its own column cache on restart anyway.
  def clear_caches
    connection.schema_cache.clear!
  end
end
