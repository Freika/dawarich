# frozen_string_literal: true

module Tracks::BackfillCommands
  COMMANDS = {
    'tracks.backfill' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        JobCommands.enqueue_after_commit(nil) do
          Time.use_zone(payload.fetch('time_zone')) do
            Tracks::BackfillGenerationJob.set(wait_until: at).perform_later(payload.fetch('user_id'))
          end
        end
      }
    }
  }.freeze
end
