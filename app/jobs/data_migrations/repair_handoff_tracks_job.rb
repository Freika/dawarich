# frozen_string_literal: true

class DataMigrations::RepairHandoffTracksJob < ApplicationJob
  queue_as :data_migrations

  REPAIR_WINDOW = 12.months
  STAGGER_WINDOW_SECONDS = 3600

  def perform
    floor = REPAIR_WINDOW.ago
    user_ids = Track.where(start_at: floor..).group(:user_id)
                    .having("COUNT(DISTINCT COALESCE(tracker_id, '')) > 1").pluck(:user_id)

    User.active_or_trial.where(id: user_ids).find_each do |user|
      Tracks::HandoffRepairJob.set(wait: rand(1..STAGGER_WINDOW_SECONDS).seconds)
                              .perform_later(user.id, floor.to_i)
    end
  end
end
