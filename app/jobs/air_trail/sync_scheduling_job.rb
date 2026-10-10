# frozen_string_literal: true

module AirTrail
  class SyncSchedulingJob < ApplicationJob
    queue_as :imports

    def perform(marker = nil)
      commands = Integrations::SchedulingCommands
      slot = commands.slot(self, marker)
      scope = User.where("settings->>'airtrail_url' <> '' AND settings->>'airtrail_api_key' <> ''")
      commands.sweep(scope, 'airtrail', 'cron:airtrail_flight_import_job', slot) do |ids, kind, at|
        commands.schedule_airtrail(ids, kind, at)
      end
    end
  end
end
