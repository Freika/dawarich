# frozen_string_literal: true

# Fallback for the ALTER that adds points.source_id, enqueued by
# 20260816150200 when the boot-time migration lost the lock race. Since 1.20.2
# that migration fails instead, so 20260816150200 never sees the column
# missing, and 20261102000100 repairs instances left short before (#3972).
# ponytail: kept so jobs already queued drain; delete it (moving
# backfill_allowed? to BackfillPointDimensionsJob) a release after 1.20.2.
class DataMigrations::AddPointDimensionColumnsJob < ApplicationJob
  queue_as :data_migrations

  # Long enough to outlast a batched write holding RowExclusive on points, and
  # each attempt does stall points behind an ACCESS EXCLUSIVE request — at one
  # try per five minutes that is a fraction of a percent of the time.
  LOCK_TIMEOUT = '5s'
  MAX_ATTEMPTS = 288

  retry_on ActiveRecord::LockWaitTimeout, wait: 5.minutes, attempts: MAX_ATTEMPTS do |_job, error|
    log_exhaustion(error)
  end

  retry_on ActiveRecord::QueryAborted, wait: 5.minutes, attempts: MAX_ATTEMPTS do |_job, error|
    log_exhaustion(error)
  end

  # The gate lives here rather than in the migration that uses it: migration
  # files are not autoloaded, so a job referring back to one would NameError
  # whenever Sidekiq picked it up in a fresh process.
  def self.backfill_allowed?
    return false unless defined?(DawarichSettings) && DawarichSettings.self_hosted?

    ENV['SKIP_POINT_DIMENSION_BACKFILL'].blank?
  end

  # The ALTER alone is not enough: this job was also the chain's only starter
  # on the deferred path, so the message must carry both manual steps —
  # without the second one ingest self-heals but history stays unstamped.
  def self.log_exhaustion(error)
    Rails.logger.error(
      "[DataMigrations::AddPointDimensionColumns] gave up after #{MAX_ATTEMPTS} attempts " \
      "(#{error.class}: #{error.message}); points.source_id is still missing and the " \
      'dimension backfill cannot start. Add it once traffic is quiet with: ' \
      "BEGIN; SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'; " \
      'ALTER TABLE points ADD COLUMN IF NOT EXISTS source_id integer; COMMIT; ' \
      'then start the backfill with: DataMigrations::BackfillPointDimensionsJob.perform_later'
    )
  end

  # Reached only from 20260816150200, which enqueues this job instead of the
  # backfill when the columns are missing — so this is the sole starter of the
  # chain on that path and cannot race a second one. The gate is the migration's
  # own, applied here too so a deferred upgrade behaves like a direct one.
  def perform
    add_column unless column_present?

    return unless column_present?
    return unless self.class.backfill_allowed?

    DataMigrations::BackfillPointDimensionsJob.perform_later
  end

  private

  def column_present?
    ActiveRecord::Base.connection.column_exists?(:points, :source_id)
  end

  # SET LOCAL keeps the timeout on the same backend as the ALTER under PgBouncer
  # transaction pooling; a bare SET can land on another connection and leave the
  # ALTER unbounded.
  def add_column
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
      ActiveRecord::Base.connection.execute(
        'ALTER TABLE points ADD COLUMN IF NOT EXISTS source_id integer'
      )
    end
    # This process cached the pre-ALTER column set; without the reset the
    # column_present? re-check below reads that stale cache and skips the
    # backfill enqueue. Other processes re-check the catalog on their own
    # via Points::DimensionResolver.columns_available?.
    Point.reset_column_information
    Points::DimensionResolver.reset_column_availability!
    Rails.logger.info '[DataMigrations::AddPointDimensionColumns] source_id added'
  end
end
