# frozen_string_literal: true

# 1.11.0 rewrote GPS noise detection: the user's accuracy threshold no longer
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
  # How long a claim is trusted before a later pass may take the user back. Long
  # enough that a legitimately slow rebuild is never stolen mid-run, short enough
  # that a restart does not strand the account until someone notices.
  STALE_CLAIM_AFTER = 6.hours

  def perform(limit: CONCURRENCY)
    runnable, skipped = next_users(limit)

    settle(skipped) if skipped.any?

    claimed = runnable.any? ? claim(runnable) : []

    if claimed.empty?
      # Nothing was handed out, so nobody will hand the slot back. That happens
      # when this pass only settled skipped users, and when it lost the claim
      # race to a concurrent dispatcher — ask again rather than losing a slot.
      self.class.perform_later(limit: limit) if skipped.any? || runnable.any?
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
        .where(*claimable_condition)
        .select(:id, :settings)
  end

  # Claimable = never handed out, OR handed out so long ago that the worker
  # cannot still be alive and it neither finished nor gave up.
  #
  # Sidekiq OSS drops in-flight jobs on hard shutdown, so a container restart
  # during a multi-hour rebuild leaves a user claimed and unstamped. Without the
  # staleness arm those users are invisible to every later pass, which makes the
  # "re-running only picks up what is left" contract false for exactly the
  # users a re-run exists to rescue.
  #
  # The timestamp is cast, not compared as text. Text comparison looked cheaper
  # but is wrong: config.time_zone defaults to Europe/Berlin and is settable per
  # instance, so a claim can be stored with a "+02:00" or "-07:00" offset. Those
  # sort by wall-clock digits, and on any zone behind UTC a claim written a
  # second ago sorts below a UTC cutoff — instantly "stale", handing a second
  # worker a user the first is still rebuilding.
  #
  # The pattern guard keeps the cast from raising on an absent or malformed
  # value, which would take the dispatcher down; anything unparseable is treated
  # as stale, since a claim nobody can date is a claim nobody can trust. It
  # matches the whole date-and-time prefix, not just the date, and COALESCEs
  # first — a JSON null yields NULL from ->>, which would otherwise make both
  # arms NULL and leave the user claimable by nobody, forever.
  def claimable_condition
    [
      "(NOT jsonb_exists(COALESCE(settings, '{}'::jsonb), :failed) " \
      'AND (' \
      "NOT jsonb_exists(COALESCE(settings, '{}'::jsonb), :queued) " \
      'OR (' \
      "NOT jsonb_exists(COALESCE(settings, '{}'::jsonb), :done) " \
      'AND (' \
      "COALESCE(settings ->> :queued, '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' " \
      'OR (settings ->> :queued)::timestamptz < :stale))))',
      {
        queued: queued_key,
        done: DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY,
        failed: DataMigrations::RecalculateAnomaliesUserJob::FAILED_SETTINGS_KEY,
        stale: STALE_CLAIM_AFTER.ago
      }
    ]
  end

  # Claim and hand-out are one statement: two dispatchers released at the same
  # instant would otherwise both read the same unclaimed id and run it twice.
  # Only the ids this statement actually stamped come back.
  def claim(user_ids)
    stamp(user_ids, queued_key => Time.current.utc.iso8601)
  end

  # Nothing to run for these, so they are claimed and finished at once: they
  # drop out of later scans and never report themselves as waiting.
  def settle(user_ids)
    now = Time.current.utc.iso8601

    stamp(
      user_ids,
      queued_key => now,
      DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY => now
    )
  end

  # The guard is the SAME predicate pending_users selects on, so a user the scan
  # considers claimable is one this statement will actually stamp. When the two
  # drifted apart, a stale claim was handed out and then silently refused, and
  # the dispatcher lost the slot.
  def stamp(user_ids, values)
    pairs = Array.new(values.size) { |i| ":k#{i}, :v#{i}" }.join(', ')
    binds = {}
    values.each_with_index do |(key, value), i|
      binds[:"k#{i}"] = key
      binds[:"v#{i}"] = value
    end

    condition_sql, condition_binds = claimable_condition

    User.connection.select_values(
      ActiveRecord::Base.sanitize_sql_array(
        [
          "UPDATE users SET settings = COALESCE(settings, '{}'::jsonb) || jsonb_build_object(#{pairs}) " \
          "WHERE id IN (:user_ids) AND #{condition_sql} RETURNING id",
          binds.merge(condition_binds).merge(user_ids: user_ids)
        ]
      )
    )
  end

  def queued_key
    DataMigrations::RecalculateAnomaliesUserJob::QUEUED_SETTINGS_KEY
  end
end
