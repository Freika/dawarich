# frozen_string_literal: true

# Until 1.21.0, 20260816150000 recorded itself as applied when it lost the lock
# race for points and left the column to a background job, which could fail
# for good (#3972). This adds the column on instances still missing it.
class EnsurePointsSourceId < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  LOCK_TIMEOUT = '5s'
  MAX_ATTEMPTS = 5

  def up
    return if column_exists?(:points, :source_id)

    backfill = DataMigrations::AddPointDimensionColumnsJob.backfill_allowed?
    # Once the ALTER commits, a rerun no longer knows the backfill is owed, so
    # an unreachable queue must fail the migration before the schema changes.
    # ponytail: Redis can still drop between this ping and the enqueue below.
    Sidekiq.redis(&:ping) if backfill

    add_source_id
    Point.reset_column_information
    DataMigrations::BackfillPointDimensionsJob.perform_later if backfill
    catch_up_tracks
  end

  def down; end

  private

  # Since 1.17.0 the track builder reads this column, so no tracks were built
  # without it. The 12-hour schedule would catch up as well; this only makes it
  # immediate, so a queue outage must not fail an already committed ALTER.
  def catch_up_tracks
    Tracks::DailyGenerationJob.perform_later
  rescue StandardError => e
    Rails.logger.warn("#{self.class.name}: track catch-up not queued (#{e.class}), the schedule will run it")
  end

  def add_source_id
    attempts = 0

    begin
      attempts += 1
      transaction do
        execute "SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'"
        execute 'ALTER TABLE points ADD COLUMN IF NOT EXISTS source_id integer'
      end
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::QueryAborted => e
      if attempts >= MAX_ATTEMPTS
        raise e.class, "points.source_id is still missing after #{MAX_ATTEMPTS} attempts (#{e.message}). " \
                       'A long transaction holds points: stop Sidekiq and restart, or run ' \
                       'ALTER TABLE points ADD COLUMN IF NOT EXISTS source_id integer once it ends, then start the ' \
                       'backfill with DataMigrations::BackfillPointDimensionsJob.perform_later.'
      end

      sleep(attempts * 5)
      retry
    end
  end
end
