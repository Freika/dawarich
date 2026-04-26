# frozen_string_literal: true

# Per-user anomaly backfill. Processes points in monthly chunks,
# guarded by an advisory lock so duplicate enqueues are harmless.
class Points::AnomalyBackfillUserJob < ApplicationJob
  queue_as :low_priority

  def perform(user_id, reset: false)
    user = User.find(user_id)
    lock_key = "anomaly_backfill:#{user.id}"

    lock_acquired = ActiveRecord::Base.with_advisory_lock(lock_key, timeout_seconds: 0) do
      reset_existing_flags(user) if reset
      run_filter_in_monthly_chunks(user)
      true
    end

    if lock_acquired
      # When we reset & re-evaluated anomalies, the tracks/stats/digests built
      # off the old anomaly state are stale. Rebuild them with the new flags.
      Users::RecalculateDataJob.perform_later(user.id) if reset
    else
      Rails.logger.info("Skipping anomaly backfill for user #{user.id} — already locked")
    end
  end

  private

  def reset_existing_flags(user)
    cleared = user.points.where(anomaly: true).update_all(anomaly: false)
    Rails.logger.info("[AnomalyBackfill] User #{user.id}: cleared #{cleared} anomaly flags before re-evaluation")
  end

  def run_filter_in_monthly_chunks(user)
    min_ts = user.points.minimum(:timestamp)
    max_ts = user.points.maximum(:timestamp)
    return unless min_ts && max_ts

    total_months = ((max_ts - min_ts) / 30.days.to_i) + 1
    month_count = 0

    current_start = min_ts
    while current_start <= max_ts
      current_end = current_start + 30.days.to_i
      marked = Points::AnomalyFilter.new(user.id, current_start, current_end).call
      month_count += 1
      Rails.logger.info(
        "[AnomalyBackfill] User #{user.id}: month #{month_count}/#{total_months}, marked #{marked} anomalies"
      )
      current_start = current_end
    end
  end
end
