# frozen_string_literal: true

# GPS noise detection changed in 1.10.4, so every anomaly flag stored before the
# upgrade was decided by rules that no longer apply — and the tracks, stats and
# digests built on those flags with it. Re-evaluate each user's points and
# rebuild what depends on them, staggered so the queue is not flooded.
#
# Enqueue only: the migration hands the work to Sidekiq and returns immediately,
# and it never fails the migration run. An instance whose queue is unreachable
# at upgrade time boots anyway and can start the job by hand afterwards.
class EnqueueAnomalyRecalculation < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::RecalculateAnomaliesJob.perform_later
  rescue StandardError => e
    Rails.logger.error(
      "[EnqueueAnomalyRecalculation] could not enqueue the GPS noise recalculation: #{e.class}: #{e.message}. " \
      'Start it later with: DataMigrations::RecalculateAnomaliesJob.perform_later'
    )
  end

  def down; end
end
