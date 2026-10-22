# frozen_string_literal: true

# Two anomaly passes were added after 1.12.0: visit reports delivered after
# departure, and coarse tower fixes carrying no motion data. Points flagged by
# neither pass sat in every history the 1.11.0 recalculation already swept, and
# its dispatcher trusts the per-user completion stamps it left behind — so
# without clearing those stamps the fleet would never see the new rules. Strip
# the stamps, then hand the fleet back to the same dispatcher; per-user
# ordering, concurrency and the track/stat rebuilds are unchanged.
#
# Every user is re-swept, including histories the new passes cannot touch:
# telling them apart up front would mean scanning each account's points inside
# the migration, which is exactly the work the staggered sweep exists to
# spread out. The repeat completion notification is accepted for the same
# reason — and the filter did change, so it is not even wrong.
#
# Enqueue only: the migration hands the work to Sidekiq and returns immediately.
# An instance whose queue is unreachable at upgrade time boots anyway and can
# start the job by hand afterwards. A NameError still aborts — that is a broken
# deploy, not an infrastructure hiccup, and must not be swallowed.
class EnqueueLeapedPointRecalculation < ActiveRecord::Migration[8.0]
  # Sidekiq receives the job the moment perform_later runs, and a worker from
  # the still-running old deployment can pop it before a wrapping migration
  # transaction commits the stamp-clearing UPDATE. The dispatcher would then
  # see every user still stamped, hand out nobody, and — having found no work
  # — never reschedule itself: the fleet sweep silently never happens. Without
  # the transaction the UPDATE is committed before the job exists.
  disable_ddl_transaction!

  def up
    clear_completion_stamps
    enqueue_recalculation
  end

  def down; end

  private

  def stamp_keys
    [
      DataMigrations::RecalculateAnomaliesUserJob::QUEUED_SETTINGS_KEY,
      DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY,
      DataMigrations::RecalculateAnomaliesUserJob::FAILED_SETTINGS_KEY
    ]
  end

  # Failed stamps are cleared too: those users never finished under the old
  # rules, and this sweep is their retry.
  def clear_completion_stamps
    quoted = stamp_keys.map { |key| connection.quote(key) }.join(', ')

    execute(<<~SQL.squish)
      UPDATE users
      SET settings = settings - ARRAY[#{quoted}]::text[]
      WHERE settings ?| ARRAY[#{quoted}]::text[]
    SQL
  end

  def enqueue_recalculation
    DataMigrations::RecalculateAnomaliesJob.perform_later
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.error(
      "[EnqueueLeapedPointRecalculation] could not enqueue the anomaly recalculation: #{e.class}: #{e.message}. " \
      'Start it later with: DataMigrations::RecalculateAnomaliesJob.perform_later'
    )
  end
end
