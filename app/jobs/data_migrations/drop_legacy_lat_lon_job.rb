# frozen_string_literal: true

class DataMigrations::DropLegacyLatLonJob < ApplicationJob
  queue_as :data_migrations

  LOCK_TIMEOUT = '5s'

  # Losing the lock race is the expected case on a busy instance, so back off
  # and keep trying rather than reporting a failure. Attempts are unlimited
  # because exhausting them re-raises into Sidekiq's own retries, turning a
  # quiet wait into weeks of reported failures ending in the dead set.
  # QueryAborted covers both LockWaitTimeout's sibling StatementTimeout and the
  # QueryCanceled that PostgreSQL raises when statement_timeout fires.
  retry_on ActiveRecord::LockWaitTimeout, wait: 5.minutes, attempts: :unlimited
  retry_on ActiveRecord::QueryAborted, wait: 5.minutes, attempts: :unlimited

  def perform
    connection = ActiveRecord::Base.connection
    return unless legacy_columns?(connection)

    # A pooled connection can carry a statement_timeout set by another job; the
    # drop must be bounded by lock_timeout alone or every retry is cancelled.
    connection.execute('SET statement_timeout = 0')
    connection.execute("SET lock_timeout = '#{LOCK_TIMEOUT}'")
    connection.execute('ALTER TABLE points DROP COLUMN IF EXISTS latitude, DROP COLUMN IF EXISTS longitude')

    Rails.logger.info('[DataMigrations::DropLegacyLatLon] dropped legacy points.latitude / points.longitude')
  ensure
    connection&.execute('RESET lock_timeout')
    connection&.execute('RESET statement_timeout')
  end

  private

  def legacy_columns?(connection)
    connection.column_exists?(:points, :latitude) || connection.column_exists?(:points, :longitude)
  end
end
