# frozen_string_literal: true

class DataMigrations::PrefillPointsCounterCacheJob < ApplicationJob
  include Resumable

  queue_as :data_migrations

  BATCH_SIZE = 100

  def perform(user_id = nil, batch_size: BATCH_SIZE)
    return prefill_counter_for_user(user_id) if user_id

    step :prefill, start: 0 do |step|
      loop do
        user_ids = User.where('id > ?', step.cursor).order(:id).limit(batch_size).pluck(:id)

        break if user_ids.empty?

        user_ids.each { |id| prefill_counter_for_user(id) }

        step.set!(user_ids.last)
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
