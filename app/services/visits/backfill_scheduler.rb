# frozen_string_literal: true

class Visits::BackfillScheduler
  DEBOUNCE_DELAY = 1.minute
  REDIS_KEY_TTL = 6.hours
  MAX_AGE = 30.days

  ACCUMULATE_SCRIPT = <<~LUA
    redis.call('ZADD', KEYS[1], ARGV[1], ARGV[1], ARGV[2], ARGV[2])
    redis.call('ZREMRANGEBYRANK', KEYS[1], 1, -2)
    redis.call('EXPIRE', KEYS[1], ARGV[3])
    local scheduled = redis.call('SET', KEYS[2], 1, 'NX', 'EX', ARGV[3])
    redis.call('EXPIRE', KEYS[2], ARGV[3])
    if scheduled then return 1 else return 0 end
  LUA

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
    now = Time.current
    late = @timestamps.select do |timestamp|
      timestamp >= MAX_AGE.ago(now).to_i &&
        timestamp < Visits::RealtimeDebouncer::LOOKBACK_WINDOW.ago(now).to_i
    end
    return if late.empty?
    return unless User.find_by(id: @user_id)&.safe_settings&.visits_suggestions_enabled?

    Sidekiq.redis_pool.with do |redis|
      scheduled = redis.call('EVAL', ACCUMULATE_SCRIPT, 2, range_key, schedule_key,
                             late.min, late.max, REDIS_KEY_TTL.to_i)
      next unless scheduled == 1

      begin
        Visits::BackfillSuggestingJob.set(wait: DEBOUNCE_DELAY).perform_later(@user_id)
      rescue StandardError
        redis.del(schedule_key)
        raise
      end
    end
  end

  def self.pop_range(user_id)
    new(user_id, []).pop_range
  end

  def pop_range
    Sidekiq.redis_pool.with do |redis|
      bounds = redis.call('EVAL', POP_RANGE_SCRIPT, 2, range_key, schedule_key)
      return nil if bounds.blank?

      [bounds.first.to_i, bounds.last.to_i]
    end
  end

  private

  def range_key
    "visit_backfill_range:user:#{@user_id}"
  end

  def schedule_key
    "visit_backfill:user:#{@user_id}"
  end
end
