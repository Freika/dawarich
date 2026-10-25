# frozen_string_literal: true

class DataMigrations::ReattachUntrackedPointsJob < ApplicationJob
  queue_as :data_migrations

  def perform
    User.active_or_trial
        .where('EXISTS (SELECT 1 FROM points WHERE points.user_id = users.id ' \
               'AND points.track_id IS NULL AND points.anomaly IS NOT TRUE)')
        .find_each { |user| Tracks::ThrottledBackfillJob.schedule(user) }
  end
end
