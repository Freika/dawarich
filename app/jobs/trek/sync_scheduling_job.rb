# frozen_string_literal: true

module Trek
  class SyncSchedulingJob < ApplicationJob
    queue_as :imports

    def perform(marker = nil)
      commands = Integrations::SchedulingCommands
      slot = commands.slot(self, marker)
      scope = TripSource.active.where(provider: 'trek')
      commands.sweep(scope, 'trek', 'cron:trek_sync_job', slot) do |ids, kind, at|
        commands.schedule_trek(ids, kind, at)
      end
    end
  end
end
