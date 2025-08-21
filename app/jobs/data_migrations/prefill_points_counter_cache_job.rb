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
    user = User.find(user_id)
    points_count = user.points.count

    User.where(id: user_id).update_all(points_count: points_count)

    Rails.logger.info "Updated points_count for user #{user_id}: #{points_count}"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "User #{user_id} not found, skipping counter cache update"
  end
end
