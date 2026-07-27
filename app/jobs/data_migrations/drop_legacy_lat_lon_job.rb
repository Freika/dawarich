# frozen_string_literal: true

class DataMigrations::DropLegacyLatLonJob < ApplicationJob
  queue_as :data_migrations

  # Long enough to catch the gap between two batched writes. The same release
  # backfills tracker ids and clears raw_data in 5k/10k-row batches that each
  # hold RowExclusive on points for seconds at a time, so a one-second wait
  # would expire inside a batch and lose every attempt. Each try does stall
  # points behind an ACCESS EXCLUSIVE request, but at one try per five minutes
  # that is a fraction of a percent of the time.
  LOCK_TIMEOUT = '5s'

  MAX_ATTEMPTS = 288

  # Losing the lock race is the expected case on a busy instance, so back off and
  # try again over the next day rather than reporting a failure. Attempts are
  # capped: each one stalls points writes for LOCK_TIMEOUT, so a drop that can
  # never win must stop and say so instead of retrying invisibly forever.
  # QueryAborted covers both LockWaitTimeout's sibling StatementTimeout and the
  # QueryCanceled that PostgreSQL raises when statement_timeout fires.
  retry_on ActiveRecord::LockWaitTimeout, wait: 5.minutes, attempts: MAX_ATTEMPTS do |_job, error|
    log_exhaustion(error)
  end

  retry_on ActiveRecord::QueryAborted, wait: 5.minutes, attempts: MAX_ATTEMPTS do |_job, error|
    log_exhaustion(error)
  end

  def self.log_exhaustion(error)
    Rails.logger.error(
      "[DataMigrations::DropLegacyLatLon] gave up after #{MAX_ATTEMPTS} attempts (#{error.class}: #{error.message}); " \
      'points.latitude / points.longitude are still present. Drop them once traffic is quiet with: ' \
      "BEGIN; SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'; " \
      'ALTER TABLE points DROP COLUMN IF EXISTS latitude, DROP COLUMN IF EXISTS longitude; COMMIT;'
    )
  end

  def perform
    connection = ActiveRecord::Base.connection
    return unless legacy_columns?(connection)

    # SET LOCAL binds both timeouts to this transaction's backend so they survive
    # PgBouncer transaction pooling — a bare SET + ALTER can otherwise land on
    # different servers, leaving the drop with no timeout at all and an unbounded
    # ACCESS EXCLUSIVE request queued ahead of every points read and write.
    # statement_timeout is pinned off so only lock_timeout bounds the wait; the
    # drop itself is metadata-only once the lock is held.
    connection.transaction do
      connection.execute('SET LOCAL statement_timeout = 0')
      connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
      connection.execute('ALTER TABLE points DROP COLUMN IF EXISTS latitude, DROP COLUMN IF EXISTS longitude')
    end

    Rails.logger.info('[DataMigrations::DropLegacyLatLon] dropped legacy points.latitude / points.longitude')
  end

  private

  def legacy_columns?(connection)
    connection.column_exists?(:points, :latitude) || connection.column_exists?(:points, :longitude)
  end
end
