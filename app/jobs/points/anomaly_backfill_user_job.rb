# frozen_string_literal: true

# Per-user anomaly backfill. Processes points in monthly chunks,
# guarded by an advisory lock so duplicate enqueues are harmless.
class Points::AnomalyBackfillUserJob < ApplicationJob
  queue_as :low_priority

  def perform(user_id)
    user = User.find(user_id)
    lock_key = "anomaly_backfill:#{user.id}"

    lock_acquired = ActiveRecord::Base.with_advisory_lock(lock_key, timeout_seconds: 0) do
      run_filter_in_monthly_chunks(user)
      true
    end

    Rails.logger.info("Skipping anomaly backfill for user #{user.id} — already locked") unless lock_acquired
  end

  private

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
