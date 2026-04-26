# frozen_string_literal: true

class AreaVisitsCalculationSchedulingJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: false

  def perform
    User.active_or_trial.find_each do |user|
      next unless user.safe_settings.visits_suggestions_enabled?

      AreaVisitsCalculatingJob.perform_later(user.id)
      PlaceVisitsCalculatingJob.perform_later(user.id)
    end
  end
end
