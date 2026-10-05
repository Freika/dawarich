# frozen_string_literal: true

module Imports
  module TeslamateCommands
    COMMANDS = {
      'imports.teslamate_sync' => {
        version: 1,
        sidekiq: lambda { |payload, at|
          JobCommands.enqueue_after_commit(nil) do
            TeslaMate::SyncJob.set(wait_until: at).perform_later(payload.fetch('user_id'))
          end
        }
      }
    }.freeze

    module_function

    def forward(user_id, event_id:)
      ActiveRecord::Base.transaction do
        next false unless JobOwnership.lock_owner('command:imports.teslamate_sync') == :oban

        JobCommands.forward('imports.teslamate_sync', { 'user_id' => user_id },
                            event_id:, aggregate_id: user_id, producer: 'TeslaMate::SyncJob')
        true
      end
    end
  end
end
