# frozen_string_literal: true

class AreaVisitsCalculationSchedulingJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: false

  def perform
    User.find_each do |user|
      AreaVisitsCalculatingJob.perform_later(user.id)
      PlaceVisitsCalculatingJob.perform_later(user.id)
    end
  end
end
