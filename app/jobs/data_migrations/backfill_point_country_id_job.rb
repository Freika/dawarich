# frozen_string_literal: true

# Resolves points.country_name (and the legacy points.country string) against
# countries.id, one id-range batch per invocation. Prerequisite for dropping
# country_name in the table rewrite; unmatched names stay NULL and keep
# resolving through Point#country_name's fallback chain.
class DataMigrations::BackfillPointCountryIdJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 50_000
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

  def self.log_exhaustion(job, error)
    cursor = job.arguments.first
    Rails.logger.error(
      "[BackfillPointCountryId] gave up on the batch from id #{cursor.inspect} after #{MAX_ATTEMPTS} attempts " \
      "(#{error.class}: #{error.message}); the backfill has stopped and points behind that cursor are unresolved. " \
      "Resume with: DataMigrations::BackfillPointCountryIdJob.perform_later(#{cursor.inspect})"
    )
  end

  def perform(start_id = nil)
    start_id ||= Point.minimum(:id)
    return if start_id.nil?

    end_id = start_id + BATCH_SIZE - 1

    resolved = bounded { resolve_countries(start_id, end_id) }

    Rails.logger.info("[BackfillPointCountryId] resolved #{resolved} points in #{start_id}..#{end_id}")

    max_id = Point.maximum(:id)
    if max_id.nil? || end_id >= max_id
      Rails.logger.info("[BackfillPointCountryId] completed at id #{end_id}")
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

  # country_name wins when it is set and the legacy country column is the
  # fallback, which is exactly COALESCE — one pass instead of two, so a row is
  # never rewritten twice. A name that matches no country stays NULL rather
  # than falling through to the legacy value, matching how the columns were
  # written: country_name superseded country.
  def resolve_countries(start_id, end_id)
    execute_sanitized(<<~SQL.squish, start_id, end_id).cmd_tuples
      UPDATE points p
      SET country_id = c.id
      FROM countries c
      WHERE p.id BETWEEN ? AND ?
        AND p.country_id IS NULL
        AND c.name = COALESCE(p.country_name, p.country)
    SQL
  end
end
