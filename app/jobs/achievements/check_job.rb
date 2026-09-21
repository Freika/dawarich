# frozen_string_literal: true

module Achievements
  class CheckJob < ApplicationJob
    queue_as :achievements

    DEBOUNCE_DELAY = 1.minute
    LOCK_TTL = 5.minutes
    PENDING_TTL = 1.day

    def self.schedule(user_id, oldest_timestamp: nil)
      newly_scheduled = Sidekiq.redis do |redis|
        if oldest_timestamp
          redis.zadd(pending_key(user_id), oldest_timestamp.to_i, oldest_timestamp.to_i)
          redis.expire(pending_key(user_id), PENDING_TTL.to_i)
        end
        redis.set(lock_key(user_id), 1, nx: true, ex: LOCK_TTL.to_i)
      end

      set(wait: DEBOUNCE_DELAY).perform_later(user_id) if newly_scheduled
    end

    def self.take_pending_timestamp(user_id)
      Sidekiq.redis do |redis|
        redis.del(lock_key(user_id))
        oldest, = redis.multi do |transaction|
          transaction.zrange(pending_key(user_id), 0, 0)
          transaction.del(pending_key(user_id))
        end
        oldest.first&.to_i
      end
    end

    def self.lock_key(user_id)
      "achievements_check:user:#{user_id}"
    end

    def self.pending_key(user_id)
      "achievements_check:user:#{user_id}:oldest"
    end

    def perform(user_id, notify: true, oldest_timestamp: nil, force: false)
      return unless force || Flipper.enabled?(:achievements)

      oldest_timestamp = [oldest_timestamp, self.class.take_pending_timestamp(user_id)].compact.min
      user = User.find_by(id: user_id)
      return unless user

      Achievements::RegionSetChecker.new(user, notify: notify, oldest_timestamp: oldest_timestamp).call
    end
  end
end
