# frozen_string_literal: true

# Resolves points.country_name (and the legacy points.country string) against
# countries.id, one id-range batch per invocation. Prerequisite for dropping
# country_name in the table rewrite; unmatched names stay NULL and keep
# resolving through Point#country_name's fallback chain.
class DataMigrations::BackfillPointCountryIdJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 50_000
  # Floor for the halving below, mirroring BackfillPointDimensionsJob: a batch
  # an eighth of the default that still cannot finish inside STATEMENT_TIMEOUT
  # is stuck, not slow, and belongs to the retry clock.
  MIN_BATCH_SIZE = 5_000
  PAUSE = 5.seconds
  LOCK_TIMEOUT = '2s'
  STATEMENT_TIMEOUT = '5min'
  MAX_ATTEMPTS = 10

  # See BackfillPointDimensionsJob: without a retry_on, after_discard procs run
  # on every attempt, so a transient timeout would falsely report the backfill
  # as stopped. These fire once, when the attempts are spent.
  retry_on ActiveRecord::LockWaitTimeout, wait: 1.minute, attempts: MAX_ATTEMPTS do |job, error|
    log_exhaustion(job, error)
  end

  retry_on ActiveRecord::QueryAborted, wait: 1.minute, attempts: MAX_ATTEMPTS do |job, error|
    log_exhaustion(job, error)
  end

  # The resume command carries the job's full arguments: a batch that
  # exhausted its retries at a halved size must not be resumed at the default
  # one, which would reproduce the very timeout the halving worked around.
  def self.log_exhaustion(job, error)
    args = job.arguments.map(&:inspect).join(', ')
    Rails.logger.error(
      "[BackfillPointCountryId] gave up on the batch from id #{job.arguments.first.inspect} " \
      "after #{MAX_ATTEMPTS} attempts " \
      "(#{error.class}: #{error.message}); the backfill has stopped and points behind that cursor are unresolved. " \
      "Resume with: DataMigrations::BackfillPointCountryIdJob.perform_later(#{args})"
    )
  end

  def perform(start_id = nil, batch_size = BATCH_SIZE)
    unless ActiveRecord::Base.connection.column_exists?(:points, :country_name)
      Rails.logger.info('[BackfillPointCountryId] points is already v2-shaped - nothing to backfill')
      return
    end

    start_id ||= Point.minimum(:id)
    return if start_id.nil?

    end_id = start_id + batch_size - 1

    resolved = bounded { resolve_countries(start_id, end_id) }

    max_id = Point.maximum(:id)
    log_progress(resolved, start_id, end_id, max_id)

    if max_id.nil? || end_id >= max_id
      Rails.logger.info("[BackfillPointCountryId] completed at id #{end_id}")
      return
    end

    self.class.set(wait: PAUSE).perform_later(end_id + 1)
  # Mirrors BackfillPointDimensionsJob: a statement_timeout is usually size,
  # not luck. Halve and retry from the same cursor; the successor batch
  # returns to the default size, and only the smallest batch reaches retry_on.
  rescue ActiveRecord::QueryAborted => e
    raise if batch_size / 2 < MIN_BATCH_SIZE

    Rails.logger.warn(
      "[BackfillPointCountryId] batch #{start_id}..#{end_id} aborted (#{e.class}: #{e.message}); " \
      "retrying from id #{start_id} at half size #{batch_size / 2}"
    )
    self.class.set(wait: PAUSE).perform_later(start_id, batch_size / 2)
  end

  private

  # The chain runs for hours on a large table; the position line is what lets
  # operators tell running from stalled.
  def log_progress(resolved, start_id, end_id, max_id)
    percent = max_id ? [end_id * 100.0 / max_id, 100].min.round(1) : 100
    Rails.logger.info(
      "[BackfillPointCountryId] resolved #{resolved} points in #{start_id}..#{end_id} " \
      "(~#{percent}% of id range)"
    )
  end

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

  # country_name wins when it is set and the legacy country column is the
  # fallback, which is exactly COALESCE — one pass instead of two, so a row is
  # never rewritten twice. A name that matches no country stays NULL rather
  # than falling through to the legacy value, matching how the columns were
  # written: country_name superseded country.
  # countries.name carries no unique index, so a duplicated name is resolved
  # to the lowest id — deterministic across batches and reruns.
  #
  # The names relation carries each country under its seeded Natural Earth
  # name AND its geocoder aliases ("United States" vs "United States of
  # America") — without the aliases a third of a real-world points table
  # stays unresolved.
  def resolve_countries(start_id, end_id)
    execute_sanitized(<<~SQL.squish, start_id, end_id).cmd_tuples
      UPDATE points p
      SET country_id = c.id
      FROM (
        SELECT MIN(id) AS id, name FROM (
          SELECT countries.id, countries.name FROM countries
          UNION ALL
          SELECT countries.id, aliases.alias AS name
          FROM countries
          JOIN #{Countries::NameAliases.values_sql} AS aliases(alias, canonical)
            ON countries.name = aliases.canonical
        ) named
        GROUP BY name
      ) c
      WHERE p.id BETWEEN ? AND ?
        AND p.country_id IS NULL
        AND c.name = COALESCE(p.country_name, p.country)
    SQL
  end
end
