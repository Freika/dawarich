# frozen_string_literal: true

class Tracks::BackfillScheduler
  DEBOUNCE_DELAY = 1.minute
  REDIS_KEY_TTL = 6.hours

  POP_RANGE_SCRIPT = <<~LUA
    local bounds = redis.call('ZRANGE', KEYS[1], 0, -1)
    redis.call('DEL', KEYS[1], KEYS[2])
    return bounds
  LUA

  def initialize(user_id, timestamps)
    @user_id = user_id
    @timestamps = timestamps.compact
  end

  def call
    return if @timestamps.empty?

    earliest = @timestamps.min
    return if earliest >= realtime_window_start

    redis_pool.with do |redis|
      latest = @timestamps.max
      redis.zadd(range_key, earliest, earliest.to_s, latest, latest.to_s)
      redis.expire(range_key, REDIS_KEY_TTL.to_i)

      if redis.set(schedule_key, 1, nx: true, ex: REDIS_KEY_TTL.to_i)
        Tracks::BackfillGenerationJob.set(wait: DEBOUNCE_DELAY).perform_later(@user_id)
      else
        redis.expire(schedule_key, REDIS_KEY_TTL.to_i)
      end
    end
  end

  def self.pop_range(user_id)
    new(user_id, []).pop_range
  end

  def pop_range
    redis_pool.with do |redis|
      bounds = redis.call('EVAL', POP_RANGE_SCRIPT, 2, range_key, schedule_key)
      return nil if bounds.blank?

      [bounds.first.to_i, bounds.last.to_i]
    end
  end

  private

  def realtime_window_start
    Tracks::IncrementalGenerator::LOOKBACK_HOURS.hours.ago.to_i
  end

  def range_key
    "track_backfill_range:user:#{@user_id}"
  end

  def schedule_key
    "track_backfill:user:#{@user_id}"
  end

  def redis_pool
    Sidekiq.redis_pool
  end
end
