# frozen_string_literal: true

module AirTrail
  class SyncSchedulingJob < ApplicationJob
    queue_as :imports

    def perform
      user_ids = User.where("settings->>'airtrail_url' <> '' AND settings->>'airtrail_api_key' <> ''").ids
      ActiveJob.perform_all_later(user_ids.map { |user_id| AirTrail::ImportFlightsJob.new(user_id) })
    end
  end
end
