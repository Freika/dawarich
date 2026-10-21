# frozen_string_literal: true

module Achievements
  class CheckJob < ApplicationJob
    queue_as :achievements

    DEBOUNCE_DELAY = 1.minute
    LOCK_TTL = 1.hour
    OWNER_KEY = 'command:achievements.check'

    def self.schedule(user_id, oldest_timestamp: nil)
      defer(user_id, oldest_timestamp: oldest_timestamp)
      newly_scheduled = PhoenixClaims.claim(lock_key(user_id), LOCK_TTL.to_i)

      set(wait: DEBOUNCE_DELAY).perform_later(user_id) if newly_scheduled
    end

    def self.defer(user_id, oldest_timestamp:)
      PendingChecks.defer(user_id, oldest_timestamp.to_i) if oldest_timestamp
    end

    def self.lock_key(user_id)
      "achievements_check:user:#{user_id}"
    end

    def self.pending_key(user_id)
      "achievements_check:user:#{user_id}:oldest"
    end

    # Older queued jobs still send force:, which no longer changes behavior.
    def perform(user_id, notify: true, oldest_timestamp: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
      PhoenixClaims.unclaim(self.class.lock_key(user_id))
      user = User.find_by(id: user_id)
      return unless user

      pending, token = PendingChecks.read(user_id)
      oldest_timestamp = [oldest_timestamp, pending].compact.min
      consumed = check_or_forward(user, notify, oldest_timestamp)

      PendingChecks.consume(user_id, token) if consumed
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
