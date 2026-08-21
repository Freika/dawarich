# frozen_string_literal: true

# Seeds point_sources from existing points and stamps source_id, one id-range
# batch per invocation, re-enqueueing itself until the whole table is covered.
# Resumable from any cursor and idempotent: seeding upserts by digest, stamping
# only touches NULL FKs.
class DataMigrations::BackfillPointDimensionsJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 50_000
  PAUSE = 5.seconds
  # A batch blocked behind a long points transaction must give its worker and
  # its PgBouncer server connection back rather than wait indefinitely; Sidekiq
  # retries the batch from the same cursor, so a timeout costs one pause.
  LOCK_TIMEOUT = '2s'
  STATEMENT_TIMEOUT = '5min'
  MAX_ATTEMPTS = 10

  # Own the retry lifecycle. Without a retry_on, an unhandled error runs the
  # after_discard procs on EVERY attempt before re-raising to Sidekiq, so a
  # transient lock timeout would announce that the backfill had stopped and
  # hand out a resume cursor that starts a second chain over the same rows.
  # These blocks run once, when the attempts are actually spent — and that is
  # the moment worth reporting, because the tail enqueue below is the chain's
  # only link to the next batch.
  retry_on ActiveRecord::LockWaitTimeout, wait: 1.minute, attempts: MAX_ATTEMPTS do |job, error|
    log_exhaustion(job, error)
  end

  retry_on ActiveRecord::QueryAborted, wait: 1.minute, attempts: MAX_ATTEMPTS do |job, error|
    log_exhaustion(job, error)
  end

  def self.log_exhaustion(job, error)
    cursor = job.arguments.first
    Rails.logger.error(
      "[BackfillPointDimensions] gave up on the batch from id #{cursor.inspect} after #{MAX_ATTEMPTS} attempts " \
      "(#{error.class}: #{error.message}); the backfill has stopped and points behind that cursor are unstamped. " \
      "Resume with: DataMigrations::BackfillPointDimensionsJob.perform_later(#{cursor.inspect})"
    )
  end

  def perform(start_id = nil)
    start_id ||= Point.minimum(:id)
    return if start_id.nil?

    end_id = start_id + BATCH_SIZE - 1

    stamped = bounded do
      seed_sources(start_id, end_id)
      stamp_sources(start_id, end_id)
    end

    Rails.logger.info("[BackfillPointDimensions] stamped #{stamped} points in #{start_id}..#{end_id}")

    max_id = Point.maximum(:id)
    if max_id.nil? || end_id >= max_id
      Rails.logger.info("[BackfillPointDimensions] completed at id #{end_id}")
      # The country backfill runs after this one rather than alongside it: both
      # walk the same id ranges at the same batch size and pace, so in parallel
      # they contend for the same rows, and the bounded lock_timeout turns that
      # contention into aborted batches instead of waits.
      DataMigrations::BackfillPointCountryIdJob.perform_later
      return
    end

    self.class.set(wait: PAUSE).perform_later(end_id + 1)
  end

  private

  def bounded(&)
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
      ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = '#{STATEMENT_TIMEOUT}'")
      yield
    end
  end

  def execute_sanitized(sql, *binds)
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array([sql, *binds])
    )
  end

  def combo_column_list
    PointSource::COMBO_COLUMNS
      .map { |column| ActiveRecord::Base.connection.quote_column_name(column) }
      .join(', ')
  end

  # NOT EXISTS keeps the insert from evaluating nextval for combos that are
  # already stored: Postgres assigns the id before it checks the conflict, so
  # relying on ON CONFLICT alone burns a sequence value per repeat. ON CONFLICT
  # stays as the guard against a concurrent seeder between the check and the
  # insert.
  def seed_sources(start_id, end_id)
    execute_sanitized(<<~SQL.squish, start_id, end_id)
      INSERT INTO point_sources (digest, #{combo_column_list}, created_at, updated_at)
      SELECT t.digest, #{combo_column_list}, NOW(), NOW()
      FROM (
        SELECT DISTINCT #{PointSource.digest_sql('points')} AS digest, #{combo_column_list}
        FROM points
        WHERE id BETWEEN ? AND ?
      ) t
      WHERE NOT EXISTS (SELECT 1 FROM point_sources ps WHERE ps.digest = t.digest)
      ON CONFLICT (digest) DO NOTHING
    SQL
  end

  # Stamping rewrites the row, and on a fillfactor-100 table the rewrite
  # cannot be HOT, so each one re-adds the row to all of points' indexes. One
  # pass, touching only rows that are still NULL.
  #
  # Under READ COMMITTED each statement takes its own snapshot, so a point
  # committed into this id range after the seed ran is visible here but was
  # never seeded and matches no source row. The inner join skips it and it
  # stays NULL — which is why the backfill is documented as re-runnable rather
  # than one-shot. Only the tail batches can see this.
  def stamp_sources(start_id, end_id)
    execute_sanitized(<<~SQL.squish, start_id, end_id).cmd_tuples
      UPDATE points p
      SET source_id = ps.id
      FROM point_sources ps
      WHERE p.id BETWEEN ? AND ?
        AND p.source_id IS NULL
        AND ps.digest = #{PointSource.digest_sql('p')}
    SQL
  end
end
