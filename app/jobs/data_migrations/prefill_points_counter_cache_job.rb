# frozen_string_literal: true

class DataMigrations::PrefillPointsCounterCacheJob < ApplicationJob
  queue_as :data_migrations

  def perform(user_id = nil)
    if user_id
      prefill_counter_for_user(user_id)
    else
      User.find_each(batch_size: 100) do |user|
        prefill_counter_for_user(user.id)
      end
    end
  end

  private

  def prefill_counter_for_user(user_id)
    User.where(id: user_id).update_all(
      'points_count = (SELECT COUNT(*) FROM points WHERE points.user_id = users.id)'
    )
  end
end
