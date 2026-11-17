# frozen_string_literal: true

# Per-user anomaly backfill. Processes points in monthly chunks,
# guarded by an advisory lock so duplicate enqueues are harmless.
class Points::AnomalyBackfillUserJob < ApplicationJob
  include Resumable
  include UserTimezone

  queue_as :low_priority

  def perform(user_id, reset: false, notify: true, rebuild: :async)
    user = User.find(user_id)
    lock_key = "anomaly_backfill:#{user.id}"

    lock_acquired = ActiveRecord::Base.with_advisory_lock(lock_key, timeout_seconds: 0) do
      step :reset_flags do
        next unless reset

        @anomalies_before = anomaly_fingerprints(user)
        reset_existing_flags(user)
      end

      step :filter_months, start: 0 do |step|
        run_filter_in_monthly_chunks(user, step, invalidate_dependents: !reset)
      end

      true
    end

    if lock_acquired
      # When we reset & re-evaluated anomalies, the tracks/stats/digests built
      # off the old anomaly state are stale. Rebuild them with the new flags,
      # but only for the years whose flagged points changed: a full-history
      # rebuild rewrites every point's track_id, and on a fleet-wide sweep that
      # bloated the points indexes by ~25 GB a day.
      # A fleet-wide data migration passes notify: false so an upgrade does not
      # hand every user a notification they never asked for, and rebuild: :inline
      # to keep the rebuild on the caller's queue and its failures visible to it.
      rebuild_after_reset(user, notify: notify, rebuild: rebuild) if reset
    else
      Rails.logger.info("Skipping anomaly backfill for user #{user.id} — already locked")
    end

    # Whether the work actually ran: a caller that records progress must not
    # record a run that the lock skipped.
    lock_acquired
  end

  private

  def rebuild_after_reset(user, notify:, rebuild:)
    years = changed_years(user)
    return if years && years.empty?

    rebuild_data(user, notify: notify, rebuild: rebuild, years: years)
    rebuild_achievements(user, notify: notify)
  end

  # nil when the run resumed after the reset step, so the flags it started
  # from are gone: rebuild everything, as before.
  def changed_years(user)
    return if @anomalies_before.nil?

    after = anomaly_fingerprints(user)
    (@anomalies_before.keys | after.keys).reject { |year| @anomalies_before[year] == after[year] }.sort
  end

  # { year => [count, digest of the ids] } of the user's flagged points, the
  # year taken in the user's timezone as Users::RecalculateDataJob splits it.
  def anomaly_fingerprints(user)
    zone = with_user_timezone(user) { Time.zone.tzinfo.name }
    year_sql = "EXTRACT(YEAR FROM to_timestamp(timestamp) AT TIME ZONE #{Point.connection.quote(zone)})::int"

    user.points.where(anomaly: true).group(Arel.sql(year_sql))
        .pluck(Arel.sql(year_sql), Arel.sql("count(*), md5(string_agg(id::text, ',' ORDER BY id))"))
        .to_h { |year, count, digest| [year, [count, digest]] }
  end

  # #perform rather than .perform_now: perform_now routes exceptions through
  # rescue_with_handler, and Users::RecalculateDataJob's retry_on swallows a
  # PerUserLock::AcquisitionTimeout there — it re-enqueues onto :stats and
  # returns normally, so an inline caller would record a rebuild that never
  # happened. Calling perform directly lets the timeout reach us.
  def rebuild_data(user, notify:, rebuild:, years:)
    options = { notify: notify }
    options[:year] = years if years

    if rebuild == :inline
      Users::RecalculateDataJob.new.perform(user.id, **options, job_queue: :low_priority)
    else
      Users::RecalculateDataJob.perform_later(user.id, **options)
    end
  end

  def rebuild_achievements(user, notify:)
    oldest_timestamp = user.points.minimum(:timestamp)
    return if oldest_timestamp.nil?

    Achievements::CheckJob.perform_later(user.id, notify: notify, oldest_timestamp: oldest_timestamp)
  end

  def reset_existing_flags(user)
    cleared = user.points.where(anomaly: true).update_all(anomaly: false, updated_at: Time.current)
    # Clearing un-hides points in vector tiles; the filter re-run only bumps
    # when it MARKS anomalies, so the all-clear outcome must invalidate here.
    Points::TileEpoch.bump(user.id) if cleared.positive?
    Rails.logger.info("[AnomalyBackfill] User #{user.id}: cleared #{cleared} anomaly flags before re-evaluation")
  end

  # invalidate_dependents mirrors the reset flow: a resetting run rebuilds
  # tracks and stats wholesale afterwards, a non-resetting one has no rebuild
  # coming and must let the filter queue its own.
  def run_filter_in_monthly_chunks(user, step, invalidate_dependents:)
    populated_months = user.points
                           .distinct
                           .pluck(Arel.sql("date_trunc('month', to_timestamp(timestamp))"))
                           .compact
                           .sort
    return if populated_months.empty?

    total_months = populated_months.length

    populated_months.each_with_index do |month_start, index|
      chunk_start = month_start.to_i
      next if chunk_start <= step.cursor

      chunk_end = (month_start + 1.month).to_i

      marked = Points::AnomalyFilter.new(
        user.id, chunk_start, chunk_end,
        invalidate_dependents: invalidate_dependents, job_queue: :low_priority
      ).call
      Rails.logger.info(
        "[AnomalyBackfill] User #{user.id}: month #{index + 1}/#{total_months}, marked #{marked} anomalies"
      )

      step.set!(chunk_start)
    end
  end
end
