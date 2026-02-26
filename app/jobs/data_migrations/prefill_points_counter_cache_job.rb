# frozen_string_literal: true

class DataMigrations::PrefillPointsCounterCacheJob < ApplicationJob
  queue_as :data_migrations

  def perform(user_id = nil)
    if user_id
      prefill_counter_for_user(user_id)
    else
      User.non_deleted.find_each(batch_size: 100) do |user|
        prefill_counter_for_user(user.id)
      end
    end
  end

  private

  def prefill_counter_for_user(user_id)
    User.reset_counters(user_id, :points)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "User #{user_id} not found, skipping counter cache update"
  end
end
