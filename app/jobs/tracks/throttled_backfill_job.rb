# frozen_string_literal: true

# Serial, rate-limited full-history track generation for users whose history is
# too large for Tracks::DailyGenerationJob's catch-up path (no tracks and more
# than BOOTSTRAP_POINTS_LIMIT points). Walks the history newest-first, one
# SLICE at a time, handing each slice to the existing parallel generator with
# untracked_only so re-runs and overlaps never rewrite already-tracked points
# (that flag, plus the tracks unique index, is what makes overlapping slices
# safe — untracked_only skips the per-user lock), and with
# job_queue: :low_priority so the chunk fan-out never competes with
# Tracks::RealtimeGenerationJob on :tracks. The pause between slices bounds
# the write rate to roughly one slice a minute instead of enqueueing thousands
# of chunk jobs at once.
class Tracks::ThrottledBackfillJob < ApplicationJob
  queue_as :low_priority

  SLICE = 30.days
  PAUSE = 1.minute
  DEDUP_KEY_TTL = 12.hours
  # A finished walk keeps its dedup key this long as a backoff: a history that
  # produced no tracks at all would otherwise be re-scheduled by every daily
  # run and re-walked from scratch. New tracks flip the daily guard off long
  # before the backoff expires; a history that stays trackless is re-judged
  # weekly instead of daily.
  COMPLETION_BACKOFF = 7.days

  def self.redis_key(user_id)
    "track_throttled_backfill:user:#{user_id}"
  end

  def self.schedule(user)
    newly_scheduled = Sidekiq.redis do |redis|
      redis.set(redis_key(user.id), 1, nx: true, ex: DEDUP_KEY_TTL.to_i)
    end

    perform_later(user.id, nil) if newly_scheduled

    newly_scheduled
  end

  def perform(user_id, cursor_timestamp = nil)
    user = User.find_by(id: user_id)
    return release_key(user_id) unless user

    cursor = cursor_timestamp || Time.current.to_i
    slice_end = user.points.where(timestamp: ...cursor).maximum(:timestamp)
    return complete(user_id) if slice_end.nil?

    slice_start = slice_end - SLICE.to_i

    Tracks::ParallelGenerator.new(
      user,
      start_at: Time.zone.at(slice_start),
      end_at: Time.zone.at(slice_end),
      mode: :bulk,
      untracked_only: true,
      job_queue: :low_priority
    ).call

    refresh_key(user_id)
    self.class.set(wait: PAUSE).perform_later(user_id, slice_start)
  end

  private

  def complete(user_id)
    Rails.logger.info("Tracks::ThrottledBackfillJob: backfill complete for user #{user_id}")
    Sidekiq.redis do |redis|
      redis.set(self.class.redis_key(user_id), 1, ex: COMPLETION_BACKOFF.to_i)
    end
  end

  def release_key(user_id)
    Sidekiq.redis { |redis| redis.del(self.class.redis_key(user_id)) }
  end

  def refresh_key(user_id)
    Sidekiq.redis { |redis| redis.set(self.class.redis_key(user_id), 1, ex: DEDUP_KEY_TTL.to_i) }
  end
end
