# frozen_string_literal: true

class EnqueuePointDimensionBackfills < ActiveRecord::Migration[8.0]
  # This is the only place that starts work, and it takes exactly one of the two
  # branches below, so there is no window in which two backfill chains can be
  # enqueued for the same rows.
  def up
    # The columns migration lets boot continue when it cannot win the lock, so
    # the columns may still be missing here. Adding them is not optional and is
    # not gated: the job keeps retrying and applies the gates below before it
    # starts any backfill of its own.
    unless columns_ready?
      enqueue(DataMigrations::AddPointDimensionColumnsJob)
      return
    end

    # Self-hosted instances backfill themselves on upgrade; Cloud is scheduled
    # by hand so the rewrite of a multi-hundred-million-row points table lands
    # in a chosen window instead of at deploy time.
    # The gate is defined on the job so both the direct and the deferred path
    # apply exactly the same rule. Escape hatch for constrained installs:
    # SKIP_POINT_DIMENSION_BACKFILL=1, then run
    # DataMigrations::BackfillPointDimensionsJob.perform_later by hand, which
    # chains DataMigrations::BackfillPointCountryIdJob when it finishes.
    return unless DataMigrations::AddPointDimensionColumnsJob.backfill_allowed?

    enqueue(DataMigrations::BackfillPointDimensionsJob)
  end

  def down; end

  private

  def columns_ready?
    column_exists?(:points, :source_id) && column_exists?(:points, :motion_id)
  end

  # Nothing retries this: the migration is recorded as applied either way and
  # this is the only place that enqueues the chain, so the log has to carry the
  # manual remedy. A NameError still aborts — that is a broken deploy, not an
  # infrastructure hiccup, and must not be swallowed.
  def enqueue(job_class)
    job_class.perform_later
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.error(
      "[EnqueuePointDimensionBackfills] could not enqueue #{job_class} (#{e.class}: #{e.message}). " \
      "Start it later with: #{job_class}.perform_later"
    )
  end
end
