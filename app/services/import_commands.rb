# frozen_string_literal: true

module ImportCommands
  UPDATE_POINTS_COUNT = 'imports.update_points_count'
  AIRTRAIL_FLIGHTS = 'imports.airtrail_flights'
  UPDATE_POINTS_COUNT_KEY = "command:#{UPDATE_POINTS_COUNT}".freeze
  AIRTRAIL_FLIGHTS_KEY = "command:#{AIRTRAIL_FLIGHTS}".freeze

  module_function

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
