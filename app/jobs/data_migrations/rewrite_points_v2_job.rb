# frozen_string_literal: true

# Release D: the online rewrite of `points` into points_v2. Phases, all
# idempotent and resumable via the one-row points_v2_rewrite_state table:
#
#   stamp    — seed + stamp dimensions for rows the C backfill never reached
#   capture  — install the change-capture trigger (live ingest never pauses)
#   copy     — id-range walk through the transform upsert (NULL-ts skipped)
#   synthesize — ONE global NULL-timestamp synthesis pass
#   finalize — indexes + foreign keys, then drain captured changes
#
# The trigger and any remaining delta are consumed by the swap migration's
# ACCESS EXCLUSIVE transaction — this job never renames anything.
class DataMigrations::RewritePointsV2Job < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 50_000
  MIN_BATCH_SIZE = 5_000
  LOCK_TIMEOUT = '2s'
  STATEMENT_TIMEOUT = '5min'
  LOCK_WAIT_ATTEMPTS = 3

  def perform(batch_size = BATCH_SIZE)
    return unless rewrite_applicable?
    return if fast_path!

    run_phases_through_copy(batch_size)
    finish
  end

  # Split entry points so the swap migration (and specs) can interleave live
  # writes between the bulk copy and the finalize steps.
  def run_phases_through_copy(batch_size = BATCH_SIZE)
    return unless rewrite_applicable?

    ensure_state_table
    stamp_dimensions(batch_size)
    capture.install
    copy_range_walk(batch_size)
  end

  # Foreign keys go in NOT VALID and only after the drain: a parent deleted
  # during the copy is still referenced by v2 until its captured nullify is
  # replayed, and validation (a full scan) belongs after the swap, when v2 is
  # the FK-enforced table row for row.
  def finish
    return unless rewrite_applicable?

    unbounded { connection.execute(Points::Rewrite::Sql.synthesis_upsert) }
    unbounded { schema_steps.add_indexes }
    capture.drain_fully
    unbounded { schema_steps.add_foreign_keys }
  end

  private

  def connection = ActiveRecord::Base.connection

  def capture = @capture ||= Points::Rewrite::ChangeCapture.new(connection)

  def schema_steps = @schema_steps ||= Points::Rewrite::SchemaSteps.new(connection)

  def rewrite_applicable?
    connection.table_exists?('points_v2') && connection.column_exists?(:points, :country_name)
  end

  def fast_path!
    connection.select_value('SELECT COUNT(*) FROM (SELECT 1 FROM points LIMIT 1) t').to_i.zero?
  end

  def ensure_state_table
    connection.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS points_v2_rewrite_state (
        id smallint PRIMARY KEY CHECK (id = 1),
        copy_cursor bigint NOT NULL DEFAULT 0,
        started_at timestamptz NOT NULL DEFAULT NOW()
      );
      INSERT INTO points_v2_rewrite_state (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
    SQL
  end

  def stamp_dimensions(batch_size)
    bounds = connection.select_one(
      'SELECT MIN(id) AS min_id, MAX(id) AS max_id FROM points WHERE source_id IS NULL'
    )
    return if bounds['min_id'].nil?

    walk_ranges(bounds['min_id'].to_i, bounds['max_id'].to_i, batch_size) do |from, upto|
      connection.execute(Points::Rewrite::Sql.seed_sources(from, upto))
      connection.execute(Points::Rewrite::Sql.stamp_sources(from, upto))
    end
  end

  def copy_range_walk(batch_size)
    max_id = connection.select_value('SELECT MAX(id) FROM points').to_i
    cursor = connection.select_value('SELECT copy_cursor FROM points_v2_rewrite_state WHERE id = 1').to_i
    return if cursor >= max_id

    walk_ranges(cursor + 1, max_id, batch_size) do |from, upto|
      connection.execute(
        Points::Rewrite::Sql.transform_upsert(where: "p.id BETWEEN #{from} AND #{upto}")
      )
      connection.execute("UPDATE points_v2_rewrite_state SET copy_cursor = #{upto} WHERE id = 1")
      log_progress(upto, max_id)
    end
  end

  # Shared id-range walker with the C backfills' halve-on-timeout behaviour:
  # a batch aborted by statement_timeout retries at half size down to the
  # floor instead of failing the run.
  def walk_ranges(from, upto, batch_size)
    size = batch_size
    cursor = from
    lock_waits = 0

    while cursor <= upto
      batch_end = [cursor + size - 1, upto].min
      begin
        bounded { yield(cursor, batch_end) }
        cursor = batch_end + 1
        lock_waits = 0
      rescue ActiveRecord::LockWaitTimeout
        lock_waits += 1
        raise if lock_waits > LOCK_WAIT_ATTEMPTS

        Rails.logger.warn("[RewritePointsV2] batch #{cursor}..#{batch_end} waited on a lock, retry #{lock_waits}")
        sleep(lock_waits)
      rescue ActiveRecord::QueryAborted
        raise if size <= MIN_BATCH_SIZE

        size = [size / 2, MIN_BATCH_SIZE].max
        Rails.logger.warn("[RewritePointsV2] batch aborted, retrying at #{size}")
      end
    end
  end

  # One batch = one transaction with the C backfills' timeout discipline, so
  # a stuck statement halves the batch instead of hanging boot, and the copy
  # cursor only advances together with the rows it covers.
  def bounded
    connection.transaction do
      connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
      connection.execute("SET LOCAL statement_timeout = '#{STATEMENT_TIMEOUT}'")
      yield
    end
  end

  # Synthesis and index builds must be allowed to run for as long as they
  # take: a role- or server-level statement_timeout would cancel them on
  # every boot with nothing to halve.
  def unbounded
    connection.transaction do
      connection.execute('SET LOCAL statement_timeout = 0')
      yield
    end
  end

  def log_progress(current, max_id)
    percent = max_id.zero? ? 100 : (current * 100.0 / max_id).round(1)
    Rails.logger.info("[RewritePointsV2] copied through id #{current} (~#{percent}% of id range)")
  end
end
