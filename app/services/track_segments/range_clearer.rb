# frozen_string_literal: true

module TrackSegments
  class RangeClearer
    def initialize(track, points, range)
      @track = track
      @points = points
      @range = range
    end

    def call
      overlapping.each { |segment| trim(segment) }
    end

    private

    attr_reader :track, :points, :range

    def overlapping
      track.track_segments.auto_classified.where(
        '(start_at IS NOT NULL AND start_at < :to AND end_at > :from) OR ' \
        '(start_at IS NULL AND start_index <= :last AND end_index >= :first)',
        from: Time.zone.at(points[range.first].timestamp), to: Time.zone.at(points[range.last].timestamp),
        first: range.first, last: range.last
      ).to_a
    end

    def trim(segment)
      covered = covered_indices(segment)
      outside = [covered.select { |i| i < range.first }, covered.select { |i| i > range.last }]
                .select { |run| run.size >= 2 }
      return segment.delete if outside.empty?

      segment.update!(attributes_for(segment, outside.first))
      segment.dup.update!(attributes_for(segment, outside.last)) if outside.size > 1
    end

    def covered_indices(segment)
      if segment.start_at
        points.each_index.select { |i| points[i].timestamp.between?(segment.start_at.to_i, segment.end_at.to_i) }
      else
        (segment.start_index..segment.end_index).to_a
      end
    end

    def attributes_for(segment, run)
      return { start_index: run.first, end_index: run.last } unless segment.start_at

      slice = points[run.first..run.last]
      distance = Point.calculate_distance_for_array_geocoder(slice, :m).round
      duration = slice.last.timestamp - slice.first.timestamp
      {
        start_at: Time.zone.at(slice.first.timestamp), end_at: Time.zone.at(slice.last.timestamp),
        path: Tracks::BuildPath.new(slice).call, distance: distance, duration: duration,
        avg_speed: Track.avg_speed_kmh(distance, duration)
      }
    end
  end
end
