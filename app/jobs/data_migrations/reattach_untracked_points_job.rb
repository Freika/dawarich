# frozen_string_literal: true

class DataMigrations::ReattachUntrackedPointsJob < ApplicationJob
  queue_as :data_migrations

  REPAIR_WINDOW = 12.months
  STAGGER_WINDOW_SECONDS = 3600

  def perform
    floor = REPAIR_WINDOW.ago.to_i
    user_ids = Point.where(user_id: Track.select(:user_id), track_id: nil, timestamp: floor..)
                    .where('anomaly IS NOT TRUE').distinct.pluck(:user_id)

    User.active_or_trial.where(id: user_ids).find_each do |user|
      Tracks::ThrottledBackfillJob.schedule(user, floor_timestamp: floor, force: true,
                                                  wait: rand(1..STAGGER_WINDOW_SECONDS).seconds)
    end
  end
end
