# frozen_string_literal: true

module Achievements
  class CheckJob < ApplicationJob
    queue_as :achievements

    DEBOUNCE_DELAY = 1.minute
    LOCK_TTL = 1.hour
    PENDING_TTL = 3.days

    def self.schedule(user_id, oldest_timestamp: nil)
      defer(user_id, oldest_timestamp: oldest_timestamp)
      newly_scheduled = Sidekiq.redis { |redis| redis.set(lock_key(user_id), 1, nx: true, ex: LOCK_TTL.to_i) }

      set(wait: DEBOUNCE_DELAY).perform_later(user_id) if newly_scheduled
    end

    def self.defer(user_id, oldest_timestamp:)
      return unless oldest_timestamp

      Sidekiq.redis do |redis|
        redis.zadd(pending_key(user_id), oldest_timestamp.to_i, "#{oldest_timestamp.to_i}:#{SecureRandom.hex(4)}")
        redis.expire(pending_key(user_id), PENDING_TTL.to_i)
      end
    end

    def self.pending_members(user_id)
      Sidekiq.redis { |redis| redis.zrange(pending_key(user_id), 0, -1) }
    end

    def self.pending_timestamps(user_id)
      pending_members(user_id).map(&:to_i)
    end

    def self.lock_key(user_id)
      "achievements_check:user:#{user_id}"
    end

    def self.pending_key(user_id)
      "achievements_check:user:#{user_id}:oldest"
    end

    def perform(user_id, notify: true, oldest_timestamp: nil, force: false)
      Sidekiq.redis { |redis| redis.del(self.class.lock_key(user_id)) }
      return unless force || Flipper.enabled?(:achievements)

      user = User.find_by(id: user_id)
      return unless user

      pending = self.class.pending_members(user_id)
      notify &&= Progress.current_exploration.exists?(user_id: user_id)
      oldest_timestamp = [oldest_timestamp, *pending.map(&:to_i)].compact.min
      Achievements::RegionSetChecker.new(user, notify: notify, oldest_timestamp: oldest_timestamp).call

      Sidekiq.redis { |redis| redis.zrem(self.class.pending_key(user_id), pending) } if pending.any?
    end
  end
end
