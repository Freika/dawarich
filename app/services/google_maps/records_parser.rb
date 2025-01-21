# frozen_string_literal: true

class GoogleMaps::RecordsParser
  include Imports::Broadcaster

  BATCH_SIZE = 1000
  attr_reader :import, :current_index

  def initialize(import, current_index = 0)
    @import = import
    @batch = []
    @current_index = current_index
  end

  def call(locations)
    Array(locations).each do |location|
      @batch << prepare_location_data(location)
      next unless @batch.size >= BATCH_SIZE

      bulk_insert_points(@batch)
      broadcast_import_progress(import, current_index)
      @batch = []
    end

    return unless @batch.any?

    bulk_insert_points(@batch)
    broadcast_import_progress(import, current_index)
  end

  private

  # rubocop:disable Metrics/MethodLength
  def prepare_location_data(location)
    {
      latitude: location['latitudeE7'].to_f / 10**7,
      longitude: location['longitudeE7'].to_f / 10**7,
      timestamp: Timestamps.parse_timestamp(location['timestamp'] || location['timestampMs']),
      altitude: location['altitude'],
      velocity: location['velocity'],
      raw_data: location,
      topic: 'Google Maps Timeline Export',
      tracker_id: 'google-maps-timeline-export',
      import_id: @import.id,
      user_id: @import.user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  # rubocop:enable Metrics/MethodLength
  def bulk_insert_points(batch)
    # Deduplicate records within the batch before upserting
    # Use all fields in the unique constraint for deduplication
    unique_batch = deduplicate_batch(batch)

    # Sort the batch to ensure consistent ordering and prevent deadlocks
    # sorted_batch = sort_batch(unique_batch)

    Point.upsert_all(
      unique_batch,
      unique_by: %i[latitude longitude timestamp user_id],
      returning: false,
      on_duplicate: :skip
    )
  rescue StandardError => e
    Rails.logger.error("Batch insert failed for import #{@import.id}: #{e.message}")

    # Create notification for the user
    Notification.create!(
      user: @import.user,
      title: 'Google Maps Import Error',
      content: "Failed to process location batch: #{e.message}",
      kind: :error
    )
  end

  def deduplicate_batch(batch)
    batch.uniq do |record|
      [
        record[:latitude].round(7),
        record[:longitude].round(7),
        record[:timestamp],
        record[:user_id]
      ]
    end
  end
end
