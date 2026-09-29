# frozen_string_literal: true

module AirTrail
  class SyncSchedulingJob < ApplicationJob
    queue_as :imports

    def perform
      User.where("settings->>'airtrail_url' <> '' AND settings->>'airtrail_api_key' <> ''")
          .find_each { |user| ImportCommands.airtrail_flights(user.id, producer: self.class.name) }
    end
  end
end
