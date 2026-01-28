# frozen_string_literal: true

# Redis-based debouncer for near real-time track generation.
#
# This service prevents excessive track generation by coalescing rapid point
# arrivals into a single job execution. When points arrive in quick succession
# (e.g., from OwnTracks or Overland), the debouncer delays processing until
# the burst settles.
#
# How it works:
# 1. First call sets a Redis key and schedules a job after DEBOUNCE_DELAY
# 2. Subsequent calls extend the key's TTL (sliding window) but don't schedule new jobs
# 3. When the job runs, it clears the key and processes all accumulated points
#
# This ensures tracks are generated quickly (< 1 minute) while avoiding:
# - Duplicate track generation for the same points
# - Excessive Sidekiq jobs during high-frequency updates
# - Race conditions between overlapping track generations
#
# Used by:
# - Points::Create
# - Overland::PointsCreator
# - OwnTracks::PointCreator
#
class Tracks::RealtimeDebouncer
  DEBOUNCE_DELAY = 45.seconds
  REDIS_KEY_TTL = 2.minutes

  def initialize(user_id)
    @user_id = user_id
  end

  def trigger
    redis_pool.with do |redis|
      key = redis_key
      # NX = only set if not exists, EX = expiry in seconds
      if redis.set(key, 1, nx: true, ex: REDIS_KEY_TTL.to_i)
        # First trigger - schedule the job
        Tracks::RealtimeGenerationJob.set(wait: DEBOUNCE_DELAY).perform_later(@user_id)
      else
        # Subsequent trigger - extend TTL (sliding window)
        redis.expire(key, REDIS_KEY_TTL.to_i)
      end
    end
  end

  def clear
    redis_pool.with { |redis| redis.del(redis_key) }
  end

  private

  def redis_key
    "track_realtime:user:#{@user_id}"
  end

  def redis_pool
    Sidekiq.redis_pool
  end
end
