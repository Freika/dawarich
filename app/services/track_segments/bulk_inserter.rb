# frozen_string_literal: true

module TrackSegments
  class BulkInserter
    def self.call(track, segment_data)
      new(track, segment_data).call
    end

    def initialize(track, segment_data)
      @track = track
      @segment_data = segment_data
    end

    def call
      return [] if segment_data.empty?

      TrackSegment.insert_all(rows, unique_by: %i[track_id start_index])
      segment_data
    end

    private

    attr_reader :track, :segment_data

    def rows
      now = Time.current
      segment_data.map do |data|
        {
          track_id: track.id,
          transportation_mode: TrackSegment.transportation_modes.fetch(data[:mode].to_s),
          start_index: data[:start_index],
          end_index: data[:end_index],
          distance: data[:distance],
          duration: data[:duration],
          avg_speed: data[:avg_speed],
          max_speed: data[:max_speed],
          avg_acceleration: data[:avg_acceleration],
          confidence: TrackSegment.confidences.fetch(data[:confidence].to_s),
          source: data[:source],
          created_at: now,
          updated_at: now
        }
      end
    end
  end
end
