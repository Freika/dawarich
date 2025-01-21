# frozen_string_literal: true

class GoogleMaps::RecordsParser
  BATCH_SIZE = 1000
  attr_reader :import

  def initialize(import)
    @import = import
    @batch = []
  end

  def call(records)
    Array(records).each do |record|
      @batch << parse_json(record)

      if @batch.size >= BATCH_SIZE
        bulk_insert_points
        @batch = []
      end
    end

    bulk_insert_points if @batch.any?
  end

  private

  def parse_json(json)
    {
      latitude: json['latitudeE7'].to_f / 10**7,
      longitude: json['longitudeE7'].to_f / 10**7,
      timestamp: Timestamps.parse_timestamp(json['timestamp'] || json['timestampMs']),
      altitude: json['altitude'],
      velocity: json['velocity'],
      raw_data: json,
      topic: 'Google Maps Timeline Export',
      tracker_id: 'google-maps-timeline-export',
      import_id: import.id,
      user_id: import.user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def bulk_insert_points
    Point.upsert_all(
      @batch,
      unique_by: %i[latitude longitude timestamp user_id],
      returning: false
    )
  end
end
