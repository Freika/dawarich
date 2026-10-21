# frozen_string_literal: true

module Imports
  module ProcessCommands
    TYPE = 'imports.process_normal'
    SOURCES = %w[google_semantic_history owntracks google_records google_phone_takeout immich_api geojson
                 photoprism_api kml csv tcx fit polarsteps google_photos mobile_photo_library].freeze
    COMMANDS = {
      TYPE => {
        version: 1,
        sidekiq: lambda { |payload, _at|
          JobCommands.enqueue_after_commit(nil) do
            Time.use_zone(payload.fetch('time_zone')) { Import::ProcessJob.perform_later(payload.fetch('import_id')) }
          end
        }
      }
    }.freeze

    module_function

    def native?(import)
      (import.source.nil? || SOURCES.include?(import.source)) && import.file.attached? &&
        (import.raw_data.nil? || import.raw_data.is_a?(Hash)) &&
        (import.additional_data_extraction.nil? || import.additional_data_extraction.is_a?(Hash))
    end

    def process(import, producer:)
      payload = { 'import_id' => import.id, 'user_id' => import.user_id, 'time_zone' => Time.zone.name }
      JobCommands.produce(TYPE, payload, aggregate_id: import.id, producer:, dedupe_key: "process-normal:#{import.id}")
    end

    def forward(import, event_id:, zone: Time.zone.name)
      gpx = ImportCommands.native_gpx?(import)
      type = gpx ? 'imports.process_gpx' : TYPE
      lane = gpx ? 'gpx' : 'normal'
      payload = { 'import_id' => import.id, 'user_id' => import.user_id, 'time_zone' => zone }
      JobCommands.forward(type, payload, event_id:, aggregate_id: import.id,
                          producer: 'Import::ProcessJob', dedupe_key: "process-#{lane}:#{import.id}")
    end
  end
end
