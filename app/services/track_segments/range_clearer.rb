# frozen_string_literal: true

module TrackSegments
  class RangeClearer
    def initialize(track, points, range, keep: [])
      @track = track
      @points = points
      @range = range
      @keep = keep
    end

    def call
      overlapping.each { |segment| trim(segment) }
    end

    private

    attr_reader :track, :points, :range, :keep

    def overlapping
      track.track_segments.auto_classified.where.not(id: keep.map(&:id)).where(
        '(start_at IS NOT NULL AND start_at < :to AND end_at > :from) OR ' \
        '(start_at IS NULL AND start_index <= :last AND end_index >= :first)',
        from: Time.zone.at(points[range.first].timestamp), to: Time.zone.at(points[range.last].timestamp),
        first: range.first, last: range.last
      ).to_a
    end

    def trim(segment)
      covered = segment.covered_indices(points.map(&:timestamp))
      outside = [covered.select { |i| i < range.first }, covered.select { |i| i > range.last }]
                .select { |run| run.size >= 2 }
      return segment.delete if outside.empty?

      reanchor(segment, outside.first)
      reanchor(segment.dup, outside.last) if outside.size > 1
    end

    def reanchor(segment, run)
      if segment.start_at
        segment.assign_attributes(start_at: Time.zone.at(points[run.first].timestamp),
                                  end_at: Time.zone.at(points[run.last].timestamp),
                                  start_index: nil, end_index: nil)
      else
        segment.assign_attributes(start_index: run.first, end_index: run.last)
      end
      GeometryRecalculator.apply(segment, points)
    end
  end
end
