# frozen_string_literal: true

module Tracks
  module GenerationCommand
    TYPE = 'tracks.generate_range'
    OWNER_KEY = "command:#{TYPE}".freeze

    module_function

    def payload(user_id, start_at:, end_at:, mode:, untracked_only:, import_id:, job_queue:)
      zoned = [start_at, end_at].compact.find { _1.respond_to?(:time_zone) }
      {
        'user_id' => user_id,
        'start_at' => start_at&.iso8601(6),
        'end_at' => end_at&.iso8601(6),
        'time_zone' => (zoned&.time_zone || Time.zone).tzinfo.name,
        'mode' => mode.to_s,
        'untracked_only' => untracked_only ? true : false,
        'import_id' => import_id,
        'low_priority' => job_queue.to_s == 'low_priority'
      }
    end

    def job_options(payload)
      zone = ActiveSupport::TimeZone[payload.fetch('time_zone')]
      {
        start_at: payload['start_at'] && zone.parse(payload['start_at']),
        end_at: payload['end_at'] && zone.parse(payload['end_at']),
        mode: payload.fetch('mode').to_sym,
        untracked_only: payload.fetch('untracked_only'),
        import_id: payload['import_id'],
        job_queue: payload.fetch('low_priority') ? :low_priority : nil
      }
    end

    def forward(payload, event_id:, producer:)
      JobCommands.forward(TYPE, payload, event_id:, aggregate_id: payload.fetch('user_id'), producer:)
    end
  end
end
