# frozen_string_literal: true

# Fallback for the ALTER that adds points.source_id / points.motion_id when the
# boot-time migration cannot win the lock race. Adding the columns from a job
# rather than aborting the migration keeps boot from crash-looping on a busy
# instance, which is the failure DataMigrations::DropLegacyLatLonJob exists to
# avoid for the mirror-image drop.
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

  def self.log_exhaustion(error)
    Rails.logger.error(
      "[DataMigrations::AddPointDimensionColumns] gave up after #{MAX_ATTEMPTS} attempts " \
      "(#{error.class}: #{error.message}); points.source_id / points.motion_id are still missing and the " \
      'dimension backfill cannot start. Add them once traffic is quiet with: ' \
      "BEGIN; SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'; " \
      'ALTER TABLE points ADD COLUMN IF NOT EXISTS source_id integer, ' \
      'ADD COLUMN IF NOT EXISTS motion_id integer; COMMIT;'
    )
  end

  # Reached only from 20260816150200, which enqueues this job instead of the
  # backfill when the columns are missing — so this is the sole starter of the
  # chain on that path and cannot race a second one. The gate is the migration's
  # own, applied here too so a deferred upgrade behaves like a direct one.
  def perform
    add_columns unless columns_present?

    return unless columns_present?
    return unless self.class.backfill_allowed?

    DataMigrations::BackfillPointDimensionsJob.perform_later
  end

  private

  def columns_present?
    connection = ActiveRecord::Base.connection
    connection.column_exists?(:points, :source_id) && connection.column_exists?(:points, :motion_id)
  end

  # SET LOCAL keeps the timeout on the same backend as the ALTER under PgBouncer
  # transaction pooling; a bare SET can land on another connection and leave the
  # ALTER unbounded.
  def add_columns
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
      ActiveRecord::Base.connection.execute(
        'ALTER TABLE points ADD COLUMN IF NOT EXISTS source_id integer, ' \
        'ADD COLUMN IF NOT EXISTS motion_id integer'
      )
    end
    Rails.logger.info '[DataMigrations::AddPointDimensionColumns] source_id / motion_id added'
  end
end
