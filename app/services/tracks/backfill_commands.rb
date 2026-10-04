# frozen_string_literal: true

module Tracks::BackfillCommands
  COMMANDS = {
    'tracks.throttled_backfill' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        JobCommands.enqueue_after_commit(nil) do
          Time.use_zone(payload.fetch('time_zone')) do
            Tracks::ThrottledBackfillJob.set(wait_until: at).perform_later(payload.fetch('user_id'),
                                                                           payload.fetch('cursor_timestamp'),
                                                                           walk_id: payload.fetch('walk_id'),
                                                                           time_zone: payload.fetch('time_zone'))
          end
        end
      }
    },
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
