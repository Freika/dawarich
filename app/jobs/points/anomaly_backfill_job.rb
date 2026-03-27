# frozen_string_literal: true

# Dispatcher job: enqueues per-user jobs so work is parallelizable,
# resumable, and doesn't block a single Sidekiq worker for hours.
class Points::AnomalyBackfillJob < ApplicationJob
  queue_as :low_priority

  def perform
    Rails.logger.info('Enqueuing per-user anomaly backfill jobs')

    User.joins(:points).distinct.find_each do |user|
      Points::AnomalyBackfillUserJob.perform_later(user.id)
    end
  end
end
