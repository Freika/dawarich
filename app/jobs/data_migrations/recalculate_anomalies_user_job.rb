# frozen_string_literal: true

# Per-user half of the 1.10.4 noise re-evaluation. Idempotent: a user is stamped
# once their points have been re-checked and the rebuild is queued, so re-running
# the migration, or a second dispatcher pass after a restart, skips everyone
# already done instead of recalculating the whole instance again.
class DataMigrations::RecalculateAnomaliesUserJob < ApplicationJob
  # Housekeeping nobody is waiting on: low_priority is last in Sidekiq's strict
  # queue order, so this only runs when no live work is pending.
  queue_as :low_priority

  RECALCULATED_SETTINGS_KEY = 'anomaly_rules_recalculated_at'
  # Another backfill already holds this user's lock — an import or a manual
  # re-check. Come back rather than stamping work that never happened.
  LOCK_RETRY_WAIT = 15.minutes

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user.nil?
    return if recalculated?(user)
    # Filtering off means the filter marks nothing, so a reset would only strip
    # flags this migration was never asked to touch.
    return unless user.safe_settings.gps_filtering_enabled?

    unless Points::AnomalyBackfillUserJob.perform_now(user.id, reset: true, notify: false)
      self.class.set(wait: LOCK_RETRY_WAIT).perform_later(user.id)
      return
    end

    mark_recalculated(user)
  end

  private

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
