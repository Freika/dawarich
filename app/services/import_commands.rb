# frozen_string_literal: true

module ImportCommands
  UPDATE_POINTS_COUNT = 'imports.update_points_count'
  AIRTRAIL_FLIGHTS = 'imports.airtrail_flights'
  UPDATE_POINTS_COUNT_KEY = "command:#{UPDATE_POINTS_COUNT}".freeze
  AIRTRAIL_FLIGHTS_KEY = "command:#{AIRTRAIL_FLIGHTS}".freeze
  PROCESS_GPX = 'imports.process_gpx'

  module_function

  def process(import, producer:)
    unless native_gpx?(import)
      return Imports::ProcessCommands.process(import, producer:) if Imports::ProcessCommands.native?(import)

      JobCommands.enqueue_after_commit(nil) { Import::ProcessJob.perform_later(import.id) }
      return :sidekiq
    end

    JobCommands.produce(PROCESS_GPX,
                        { 'import_id' => import.id, 'user_id' => import.user_id, 'time_zone' => Time.zone.name },
                        aggregate_id: import.id, producer:, dedupe_key: "process-gpx:#{import.id}")
  end

  def native_gpx?(import)
    import.gpx? && import.file.attached? && File.extname(import.file.filename.to_s).casecmp?('.gpx') &&
      (import.raw_data.nil? || import.raw_data.is_a?(Hash)) &&
      (import.additional_data_extraction.nil? || import.additional_data_extraction.is_a?(Hash))
  end

  def update_points_count(import_id, producer:)
    JobCommands.produce(UPDATE_POINTS_COUNT, { 'import_id' => import_id },
                        aggregate_id: import_id, producer:, dedupe_key: "points-count:#{import_id}")
  end

  def forward_update_points_count(import_id, event_id:)
    JobCommands.forward(UPDATE_POINTS_COUNT, { 'import_id' => import_id },
                        event_id:, aggregate_id: import_id, producer: 'Import::UpdatePointsCountJob',
                        dedupe_key: "points-count:#{import_id}")
  end

  def airtrail_flights(user_id, producer:)
    JobCommands.produce(AIRTRAIL_FLIGHTS, { 'user_id' => user_id },
                        aggregate_id: user_id, producer:, dedupe_key: "airtrail:#{user_id}")
  end

  def forward_airtrail_flights(user_id, event_id:)
    JobCommands.forward(AIRTRAIL_FLIGHTS, { 'user_id' => user_id },
                        event_id:, aggregate_id: user_id, producer: 'AirTrail::ImportFlightsJob',
                        dedupe_key: "airtrail:#{user_id}")
  end
end
