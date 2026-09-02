# frozen_string_literal: true

module Stats
  class RecalculationDebouncer
    DEBOUNCE_DELAY = 1.minute
    REDIS_KEY_TTL = 5.minutes

    def initialize(user_id)
      @user_id = user_id
    end

    def trigger
      redis_pool.with do |redis|
        if redis.set(redis_key, 1, nx: true, ex: REDIS_KEY_TTL.to_i)
          Stats::FullRecalculationJob.set(wait: DEBOUNCE_DELAY).perform_later(@user_id)
        else
          redis.expire(redis_key, REDIS_KEY_TTL.to_i)
        end
      end
    end

    def clear
      redis_pool.with { |redis| redis.del(redis_key) }
    end

    private

    def redis_key
      "stats_full_recalculation:user:#{@user_id}"
    end

    def redis_pool
      Sidekiq.redis_pool
    end
  end
end
