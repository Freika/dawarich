# frozen_string_literal: true

# Per-user half of the 1.10.4 noise re-evaluation. Idempotent: a user is stamped
# once their points have been re-checked and their derived data rebuilt, so
# re-running the migration, or a second dispatcher pass after a restart, skips
# everyone already done instead of recalculating the whole instance again.
#
# Holds one of the dispatcher's slots for its whole run and hands it back when
# it is finished, so the migration never occupies more workers than that.
class DataMigrations::RecalculateAnomaliesUserJob < ApplicationJob
  # Housekeeping nobody is waiting on: low_priority is last in Sidekiq's strict
  # queue order. The rebuild runs inline so it stays here too, and the track
  # chunks it fans out are routed to low_priority as well, so a full-history
  # rebuild never queues ahead of live tracking on :tracks.
  queue_as :low_priority

  QUEUED_SETTINGS_KEY = 'anomaly_rules_recalculation_queued_at'
  RECALCULATED_SETTINGS_KEY = 'anomaly_rules_recalculated_at'
  # Another backfill already holds this user's lock — an import or a manual
  # re-check. Come back rather than stamping work that never happened.
  LOCK_RETRY_WAIT = 15.minutes
  # A lock still held after this many tries is not transient contention any
  # more; give up loudly instead of re-queueing every 15 minutes forever.
  MAX_LOCK_ATTEMPTS = 8

  # Bounded, because a failing user re-runs the whole reset and filter pass on
  # every attempt. Sidekiq's default 25 would do that for days, and would hold
  # the dispatcher slot the entire time.
  MAX_REBUILD_ATTEMPTS = 3

  retry_on StandardError, wait: :polynomially_longer, attempts: MAX_REBUILD_ATTEMPTS do |job, error|
    user_id = job.arguments.first
    Rails.logger.error(
      "[DataMigrations::RecalculateAnomalies] user #{user_id} failed: #{error.class}: #{error.message}. " \
      "Re-run with: DataMigrations::RecalculateAnomaliesUserJob.perform_later(#{user_id})"
    )
    DataMigrations::RecalculateAnomaliesJob.perform_later(limit: 1)
  end

  def perform(user_id, attempt: 1)
    user = User.find_by(id: user_id)
    return release_slot if user.nil?
    return release_slot if recalculated?(user)
    # Filtering off means the filter marks nothing, so a reset would only strip
    # flags this migration was never asked to touch.
    return release_slot unless user.safe_settings.gps_filtering_enabled?

    unless Points::AnomalyBackfillUserJob.perform_now(user.id, reset: true, notify: false, rebuild: :inline)
      return retry_after_lock(user_id, attempt)
    end

    mark_recalculated(user)
    release_slot
  rescue Tracks::PerUserLock::AcquisitionTimeout
    # The track lock is busy, not broken. Retrying the job wholesale would
    # re-run the reset and filter pass each time, so take the bounded path that
    # lock contention already uses — and leave the user unstamped either way.
    retry_after_lock(user_id, attempt)
  end

  private

  # Hand the dispatcher slot back so the next user starts. Every terminal path
  # goes through here; the retry paths deliberately do not, because they keep
  # the slot for their own re-run.
  def release_slot
    DataMigrations::RecalculateAnomaliesJob.perform_later(limit: 1)
    nil
  end

  def retry_after_lock(user_id, attempt)
    if attempt >= MAX_LOCK_ATTEMPTS
      Rails.logger.error(
        "[DataMigrations::RecalculateAnomalies] user #{user_id} still locked after #{attempt} attempts, giving up. " \
        "Re-run with: DataMigrations::RecalculateAnomaliesUserJob.perform_later(#{user_id})"
      )
      return release_slot
    end

    self.class.set(wait: LOCK_RETRY_WAIT).perform_later(user_id, attempt: attempt + 1)
    nil
  end

  def recalculated?(user)
    user.settings&.dig(RECALCULATED_SETTINGS_KEY).present?
  end

  # Atomic JSONB merge in SQL: settings is written from several places, and a
  # read-modify-write here would drop whatever changed while the filter ran.
  def mark_recalculated(user)
    User.where(id: user.id).update_all(
      ActiveRecord::Base.sanitize_sql_array(
        [
          "settings = COALESCE(settings, '{}'::jsonb) || jsonb_build_object(?, ?)",
          RECALCULATED_SETTINGS_KEY, Time.zone.now.iso8601
        ]
      )
    )
  end
end
