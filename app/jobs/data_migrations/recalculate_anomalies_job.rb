# frozen_string_literal: true

# 1.10.4 rewrote GPS noise detection: the user's accuracy threshold no longer
# discards anything, coordinates near (0, 0) are broken everywhere, and new
# detour/stay passes catch displaced fixes the old speed sandwich let through.
# Stored anomaly flags therefore disagree with the current rules in both
# directions, and the tracks, stats and digests built on top of them are stale.
#
# Dispatcher only: the per-user work is DataMigrations::RecalculateAnomaliesUserJob.
# Running this twice is safe — users already handed out are skipped, so a re-run
# only picks up whatever is left.
class DataMigrations::RecalculateAnomaliesJob < ApplicationJob
  queue_as :data_migrations

  # Re-evaluating one user costs a filter pass over every month they tracked
  # plus a full stats/tracks/digests rebuild, and the per-user job holds a
  # worker for all of it. Strict queue order does not preempt a running job, so
  # a wide fan-out would fill every Sidekiq thread with migration work no matter
  # how low its priority. Hand out a fixed number of slots instead and let each
  # finishing job pull the next user in, which also keeps the track chunks
  # draining rather than piling up behind a day of backlog.
  CONCURRENCY = 2
  USER_SCAN_BATCH_SIZE = 1_000

  def perform(limit: CONCURRENCY)
    runnable, skipped = next_users(limit)

    settle(skipped) if skipped.any?

    claimed = runnable.any? ? claim(runnable) : []

    if claimed.empty?
      # A pass that only settled skipped users would otherwise end without
      # anyone left to hand the slot back, stalling the chain.
      self.class.perform_later(limit: limit) if skipped.any?
      return
    end

    Rails.logger.info(
      "[DataMigrations::RecalculateAnomalies] handing #{claimed.size} user(s) to the rebuild"
    )

    begin
      ActiveJob.perform_all_later(
        claimed.map { |user_id| DataMigrations::RecalculateAnomaliesUserJob.new(user_id) }
      )
    rescue StandardError
      # The claim is only meaningful if a job exists to honour it; leaving it
      # behind would hide these users from every later pass.
      DataMigrations::RecalculateAnomaliesUserJob.release_claim(claimed)
      raise
    end
  end

  private

  # EXISTS rather than points_count: the counter is corrected on a schedule and
  # can read zero for a user who has just imported.
  #
  # Users who turned filtering off keep the flags they have. Re-running the
  # filter for them marks nothing, so a reset would silently unflag their
  # history — a change this migration was not asked to make. They are still
  # marked as handed out, so the queue drains and nothing reports them waiting.
  #
  # The boolean stays in Ruby rather than SQL: SafeSettings casts it with
  # ActiveModel::Type::Boolean, which treats "0", "f" and "off" as false too,
  # and a hand-rolled jsonb predicate would quietly disagree on those.
  def next_users(limit)
    runnable = []
    skipped = []

    pending_users.find_each(batch_size: USER_SCAN_BATCH_SIZE) do |user|
      if Users::SafeSettings.new(user.settings || {}).gps_filtering_enabled?
        runnable << user.id
        break if runnable.size >= limit
      else
        skipped << user.id
      end
    end

    [runnable, skipped]
  end

  def pending_users
    User.where('EXISTS (SELECT 1 FROM points WHERE points.user_id = users.id)')
        .where(
          "NOT jsonb_exists(COALESCE(settings, '{}'::jsonb), ?)",
          DataMigrations::RecalculateAnomaliesUserJob::QUEUED_SETTINGS_KEY
        )
        .select(:id, :settings)
  end

  # Claim and hand-out are one statement: two dispatchers released at the same
  # instant would otherwise both read the same unclaimed id and run it twice.
  # Only the ids this statement actually stamped come back.
  def claim(user_ids)
    stamp(user_ids, queued_key => Time.zone.now.iso8601)
  end

  # Nothing to run for these, so they are claimed and finished at once: they
  # drop out of later scans and never report themselves as waiting.
  def settle(user_ids)
    now = Time.zone.now.iso8601

    stamp(
      user_ids,
      queued_key => now,
      DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY => now
    )
  end

  def stamp(user_ids, values)
    binds = values.flat_map { |key, value| [key, value] }
    pairs = Array.new(values.size, '?, ?').join(', ')

    User.connection.select_values(
      ActiveRecord::Base.sanitize_sql_array(
        [
          "UPDATE users SET settings = COALESCE(settings, '{}'::jsonb) || jsonb_build_object(#{pairs}) " \
          "WHERE id IN (?) AND NOT jsonb_exists(COALESCE(settings, '{}'::jsonb), ?) RETURNING id",
          *binds, user_ids, queued_key
        ]
      )
    )
  end

  def queued_key
    DataMigrations::RecalculateAnomaliesUserJob::QUEUED_SETTINGS_KEY
  end
end
