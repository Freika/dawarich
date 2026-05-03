# frozen_string_literal: true

class Visits::RealtimeDebouncer
  DEBOUNCE_DELAY = 5.minutes
  REDIS_KEY_TTL = 10.minutes
  LOOKBACK_WINDOW = 25.hours

  def initialize(user_id)
    @user_id = user_id
  end

  def trigger
    return unless DawarichSettings.reverse_geocoding_enabled?
    return unless user_opted_in?

    redis_pool.with do |redis|
      key = redis_key
      if redis.set(key, 1, nx: true, ex: REDIS_KEY_TTL.to_i)
        VisitSuggestingJob
          .set(wait: DEBOUNCE_DELAY)
          .perform_later(
            user_id: @user_id,
            start_at: LOOKBACK_WINDOW.ago.iso8601,
            end_at: Time.current.iso8601
          )
      else
        redis.expire(key, REDIS_KEY_TTL.to_i)
      end
    end
  end

  def clear
    redis_pool.with { |redis| redis.del(redis_key) }
  end

  private

  def user_opted_in?
    User.find_by(id: @user_id)&.safe_settings&.visits_suggestions_enabled?
  end

  def redis_key
    "visit_realtime:user:#{@user_id}"
  end

  def redis_pool
    Sidekiq.redis_pool
  end
end
