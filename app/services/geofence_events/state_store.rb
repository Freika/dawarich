# frozen_string_literal: true

module GeofenceEvents
  class StateStore
    class Unavailable < StandardError; end

    ADVANCE_SCRIPT = <<~LUA
      local current = redis.call('GET', KEYS[1])
      if (not current) or tonumber(current) < tonumber(ARGV[1]) then
        redis.call('SET', KEYS[1], ARGV[1])
      end
      return 1
    LUA

    def initialize(user)
      @user = user
    end

    def inside_ids
      with_redis do |redis|
        ensure_built(redis)
        redis.call('SMEMBERS', inside_key).to_set(&:to_i)
      end
    end

    def enter!(area_id)
      change('SADD', area_id)
    end

    def leave!(area_id)
      change('SREM', area_id)
    end

    def evaluated_at
      with_redis { |redis| redis.call('GET', evaluated_key)&.to_i }
    end

    def advance_evaluated_at!(timestamp)
      with_redis { |redis| redis.call('EVAL', ADVANCE_SCRIPT, 1, evaluated_key, timestamp.to_i) }
    end

    def reset!
      with_redis { |redis| redis.call('DEL', inside_key, ready_key, evaluated_key) }
    end

    private

    def change(command, area_id)
      with_redis do |redis|
        ensure_built(redis)
        redis.call(command, inside_key, area_id).to_i == 1
      end
    end

    def ensure_built(redis)
      return if redis.call('EXISTS', ready_key).to_i == 1

      ids = areas_entered_last
      redis.call('SADD', inside_key, *ids) if ids.any?
      redis.call('SET', ready_key, '1')
    end

    def areas_entered_last
      GeofenceEvent.real.where(user_id: @user.id)
                   .select('DISTINCT ON (area_id) area_id, event_type')
                   .order(:area_id, occurred_at: :desc, id: :desc)
                   .select(&:event_type_enter?).map(&:area_id)
    end

    def with_redis(&)
      Sidekiq.redis_pool.with(&)
    rescue RedisClient::Error => e
      raise Unavailable, e.message
    end

    def inside_key = "geofence:inside:#{@user.id}"
    def ready_key = "geofence:ready:#{@user.id}"
    def evaluated_key = "geofence:evaluated_at:#{@user.id}"
  end
end
