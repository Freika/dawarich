# frozen_string_literal: true

# Until 1.20.2, 20260816150000 recorded itself as applied when it lost the lock
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
  end

  def down; end

  private

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
                       'ALTER TABLE points ADD COLUMN IF NOT EXISTS source_id integer once it ends.'
      end

      sleep(attempts * 5)
      retry
    end
  end
end
