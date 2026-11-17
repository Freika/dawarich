# frozen_string_literal: true

# Per-user anomaly backfill. Processes points in monthly chunks,
# guarded by an advisory lock so duplicate enqueues are harmless.
class Points::AnomalyBackfillUserJob < ApplicationJob
  include Resumable

  queue_as :low_priority

  def perform(user_id, reset: false, notify: true, rebuild: :async)
    user = User.find(user_id)
    lock_key = "anomaly_backfill:#{user.id}"

    lock_acquired = ActiveRecord::Base.with_advisory_lock(lock_key, timeout_seconds: 0) do
      step :reset_flags do
        next unless reset

        Points::AnomalyRebuildScope.new(user).remember
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
    scope = Points::AnomalyRebuildScope.new(user)
    years = scope.changed_years

    if years && years.empty?
      Rails.logger.info("[AnomalyBackfill] User #{user.id}: no flags changed, nothing to rebuild")
      notify_nothing_changed(user) if notify && detached_track_ids.empty?
    else
      Rails.logger.info("[AnomalyBackfill] User #{user.id}: rebuilding years #{years&.join(', ') || 'all'}")
      rebuild_data(user, notify: notify, rebuild: rebuild, years: years)
      rebuild_achievements(user, notify: notify)
    end
    recalculate_detached_tracks if years

    # A queued rebuild forgets the fingerprint itself once it succeeds, so a
    # rebuild that fails for good leaves it for the next re-check to compare.
    scope.forget unless queued_rebuild?(years, rebuild)
  end

  def queued_rebuild?(years, rebuild)
    rebuild != :inline && (years.nil? || years.any?)
  end

  # Points left unflagged between the reset and the re-filter can be joined to
  # a track by live generation; flagging them again detaches them without
  # changing the fingerprint, so those tracks are rebuilt one by one.
  # ponytail: held in memory, so a run resumed mid-filter forgets the tracks
  # detached before the restart; persist them if that window ever matters.
  def recalculate_detached_tracks
    jobs = detached_track_ids.uniq.map { |track_id| Tracks::RecalculateJob.new(track_id).set(queue: :low_priority) }
    ActiveJob.perform_all_later(jobs) if jobs.any?
  end

  def detached_track_ids
    @detached_track_ids ||= []
  end

  def notify_nothing_changed(user)
    I18n.with_locale(user.locale) do
      Notifications::Create.new(
        user: user,
        kind: :info,
        title: I18n.t('jobs.data_migrations.recalculate_anomalies_user_job.gps_noise_re_check_finished'),
        content: I18n.t('jobs.points.anomaly_backfill_user_job.nothing_changed')
      ).call
    end
  end

  # #perform rather than .perform_now: perform_now routes exceptions through
  # rescue_with_handler, and Users::RecalculateDataJob's retry_on swallows a
  # PerUserLock::AcquisitionTimeout there — it re-enqueues onto :stats and
  # returns normally, so an inline caller would record a rebuild that never
  # happened. Calling perform directly lets the timeout reach us.
  #
  # Every yearly digest carries all-time totals and a comparison with the
  # year before, so the job also refreshes the digests of the other years,
  # after the changed years' stats.
  def rebuild_data(user, notify:, rebuild:, years:)
    options = { notify: notify }
    if years
      options[:year] = years
      other_digest_years = user.digests.yearly.distinct.pluck(:year) - years
      options[:digest_years] = other_digest_years if other_digest_years.any?
    end

    if rebuild == :inline
      Users::RecalculateDataJob.new.perform(user.id, **options, job_queue: :low_priority)
    else
      Users::RecalculateDataJob.perform_later(user.id, **options, anomaly_rebuild: true)
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
  # tracks and stats afterwards, a non-resetting one has no rebuild coming and
  # must let the filter queue its own.
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

      filter = Points::AnomalyFilter.new(
        user.id, chunk_start, chunk_end,
        invalidate_dependents: invalidate_dependents, job_queue: :low_priority
      )
      marked = filter.call
      detached_track_ids.concat(filter.detached_track_ids) unless invalidate_dependents
      Rails.logger.info(
        "[AnomalyBackfill] User #{user.id}: month #{index + 1}/#{total_months}, marked #{marked} anomalies"
      )

      step.set!(chunk_start)
    end
  end
end
