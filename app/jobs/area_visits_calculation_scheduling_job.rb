# frozen_string_literal: true

class AreaVisitsCalculationSchedulingJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: false

  def perform
    User.find_each { AreaVisitsCalculatingJob.perform_later(_1.id) }
  end
end
