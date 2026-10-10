# frozen_string_literal: true

module TeslaMate
  class SyncSchedulingJob < ApplicationJob
    queue_as :imports

    def perform(marker = nil)
      commands = Integrations::SchedulingCommands
      slot = commands.slot(self, marker)
      scope = User.where("settings->>'teslamate_url' <> ''")
      commands.sweep(scope, 'teslamate', 'cron:teslamate_sync_job', slot) do |ids, kind, at|
        commands.schedule_teslamate(ids, kind, at)
      end
    end
  end
end
