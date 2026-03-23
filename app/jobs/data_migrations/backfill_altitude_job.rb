# frozen_string_literal: true

# Dispatcher job: enqueues per-user jobs so work is parallelizable,
# resumable, and doesn't block a single Sidekiq worker for hours.
class DataMigrations::BackfillAltitudeJob < ApplicationJob
  queue_as :data_migrations

  def perform
    Rails.logger.info('Enqueuing per-user altitude backfill jobs')

    User.where('points_count > 0').find_each do |user|
      DataMigrations::BackfillAltitudeUserJob.perform_later(user.id)
    end
  end
end
