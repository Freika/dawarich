# frozen_string_literal: true

module GeofenceEvents
  module Evaluator
    class StateStore
      KEY_PREFIX = 'geofence:inside'
      POOL_SIZE = 5
      POOL_TIMEOUT = 1 # seconds

      class << self
        def currently_inside(user)
          pool.with { |r| r.smembers(key(user)).map(&:to_i).to_set }
        end

        def apply(user, area, event_type)
          case event_type.to_sym
          when :enter then pool.with { |r| r.sadd(key(user), area.id) }
          when :leave then pool.with { |r| r.srem(key(user), area.id) }
          end
        end

        def reset!(user)
          pool.with { |r| r.del(key(user)) }
        end

        private

        def key(user)
          "#{KEY_PREFIX}:#{user.id}"
        end

        def pool
          @pool ||= ConnectionPool.new(size: POOL_SIZE, timeout: POOL_TIMEOUT) do
            Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
          end
        end
      end
    end
  end
end
