# frozen_string_literal: true

module AchievementCheckHelpers
  def clear_achievement_checks(user_id)
    Sidekiq.redis do |redis|
      redis.call('DEL', Achievements::CheckJob.lock_key(user_id), Achievements::CheckJob.pending_key(user_id))
    end
  end
end

RSpec.configure { |config| config.include AchievementCheckHelpers }
