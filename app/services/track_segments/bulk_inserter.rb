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

      inserted = Track.transaction do
        current_track = Track.lock.find_by(id: track.id)
        next false unless current_track

        TrackSegment.insert_all(rows(current_track), unique_by: 'idx_track_segments_track_start_at_unique')
        true
      end

      inserted ? segment_data : []
    end

    private

    attr_reader :track, :segment_data

    def rows(current_track)
      now = Time.current
      segment_data.map do |data|
        {
          track_id: current_track.id,
          transportation_mode: TrackSegment.transportation_modes.fetch(data[:mode].to_s),
          start_at: data[:start_at],
          end_at: data[:end_at],
          path: data[:path_wkt] && "SRID=4326;#{data[:path_wkt]}",
          distance: data[:distance],
          duration: data[:duration],
          avg_speed: data[:avg_speed],
          max_speed: data[:max_speed],
          confidence: TrackSegment.confidences.fetch(data[:confidence].to_s),
          confidence_score: data[:confidence_score],
          source: data[:source],
          created_at: now,
          updated_at: now
        }
      end
    end
  end
end
