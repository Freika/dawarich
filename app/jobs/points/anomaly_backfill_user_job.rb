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
    populated_months = user.points
                           .distinct
                           .pluck(Arel.sql("date_trunc('month', to_timestamp(timestamp))"))
                           .compact
                           .sort
    return if populated_months.empty?

    total_months = populated_months.length

    populated_months.each_with_index do |month_start, index|
      chunk_start = month_start.to_i
      chunk_end = (month_start + 1.month).to_i

      marked = Points::AnomalyFilter.new(user.id, chunk_start, chunk_end).call
      Rails.logger.info(
        "[AnomalyBackfill] User #{user.id}: month #{index + 1}/#{total_months}, marked #{marked} anomalies"
      )
    end
  end
end
