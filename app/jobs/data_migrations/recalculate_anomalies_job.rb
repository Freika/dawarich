# frozen_string_literal: true

# 1.10.4 rewrote GPS noise detection: the user's accuracy threshold no longer
# discards anything, coordinates near (0, 0) are broken everywhere, and new
# detour/stay passes catch displaced fixes the old speed sandwich let through.
# Stored anomaly flags therefore disagree with the current rules in both
# directions, and the tracks, stats and digests built on top of them are stale.
#
# Dispatcher only: the per-user work is DataMigrations::RecalculateAnomaliesUserJob,
# which runs on low_priority (last in Sidekiq's strict queue order) so it never
# starves live traffic. Running this twice is safe — users stamped by a previous
# pass are skipped, so a re-run only picks up whatever is left.
class DataMigrations::RecalculateAnomaliesJob < ApplicationJob
  queue_as :data_migrations

  # Re-evaluating one user costs a filter pass over every month they tracked
  # plus a full stats/tracks/digests recalculation, so the fleet is spread over
  # a window that grows with it: a single-user instance starts within seconds,
  # a large one trickles through a day instead of queueing everything at once.
  SECONDS_PER_USER = 30
  MAX_STAGGER_WINDOW_SECONDS = 24.hours.to_i
  ENQUEUE_BATCH_SIZE = 1_000
  USER_SCAN_BATCH_SIZE = 1_000

  def self.stagger_window(user_count)
    [user_count * SECONDS_PER_USER, MAX_STAGGER_WINDOW_SECONDS].min
  end

  def perform
    user_ids = eligible_user_ids
    return if user_ids.empty?

    window = self.class.stagger_window(user_ids.size)

    Rails.logger.info(
      "[DataMigrations::RecalculateAnomalies] enqueuing #{user_ids.size} user(s) over #{window}s"
    )

    now = Time.current

    jobs = user_ids.map do |user_id|
      job = DataMigrations::RecalculateAnomaliesUserJob.new(user_id)
      job.scheduled_at = now + rand(0..window).seconds
      job
    end

    jobs.each_slice(ENQUEUE_BATCH_SIZE) { |batch| ActiveJob.perform_all_later(batch) }
  end

  private

  # EXISTS rather than points_count: the counter is corrected on a schedule and
  # can read zero for a user who has just imported, and a missed user here never
  # gets a second chance.
  #
  # Users who turned filtering off keep the flags they have. Re-running the
  # filter for them marks nothing, so a reset would silently unflag their
  # history — a change this migration was not asked to make.
  # The boolean stays in Ruby rather than SQL: SafeSettings casts it with
  # ActiveModel::Type::Boolean, which treats "0", "f" and "off" as false too,
  # and a hand-rolled jsonb predicate would quietly disagree on those. Only id
  # and settings are loaded, in batches, so nothing accumulates but the ids.
  def eligible_user_ids
    ids = []

    User.where('EXISTS (SELECT 1 FROM points WHERE points.user_id = users.id)')
        .where(
          "NOT jsonb_exists(COALESCE(settings, '{}'::jsonb), ?)",
          DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY
        )
        .select(:id, :settings)
        .find_each(batch_size: USER_SCAN_BATCH_SIZE) do |user|
          ids << user.id if Users::SafeSettings.new(user.settings || {}).gps_filtering_enabled?
        end

    ids
  end
end
