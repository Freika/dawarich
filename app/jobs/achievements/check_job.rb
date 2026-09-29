# frozen_string_literal: true

module Achievements
  class CheckJob < ApplicationJob
    queue_as :achievements

    DEBOUNCE_DELAY = 1.minute
    LOCK_TTL = 1.hour
    PENDING_TTL = 3.days
    OWNER_KEY = 'command:achievements.check'

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

    # Older queued jobs still send force:, which no longer changes behavior.
    def perform(user_id, notify: true, oldest_timestamp: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
      Sidekiq.redis { |redis| redis.del(self.class.lock_key(user_id)) }
      user = User.find_by(id: user_id)
      return unless user

      pending = self.class.pending_members(user_id)
      oldest_timestamp = [oldest_timestamp, *pending.map(&:to_i)].compact.min
      consumed = check_or_forward(user, notify, oldest_timestamp)

      Sidekiq.redis { |redis| redis.zrem(self.class.pending_key(user_id), pending) } if consumed && pending.any?
    end

    private

    def check_or_forward(user, notify, oldest_timestamp)
      inserted = forward(user.id, notify, oldest_timestamp)
      return inserted.positive? if inserted

      notify &&= Progress.current_exploration.exists?(user_id: user.id)
      Achievements::RegionSetChecker.new(user, notify: notify, oldest_timestamp: oldest_timestamp).call
      true
    end

    def forward(user_id, notify, oldest_timestamp)
      ActiveRecord::Base.transaction do
        next unless JobOwnership.lock_owner(OWNER_KEY) == :oban

        JobCommands.forward(
          'achievements.check',
          { 'user_id' => user_id, 'notify' => notify ? true : false, 'oldest_timestamp' => oldest_timestamp },
          event_id: Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "achievements.check:#{user_id}:#{job_id}"),
          aggregate_id: user_id, producer: self.class.name
        )
      end
    end
  end
end
