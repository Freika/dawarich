# frozen_string_literal: true

module EnhancedImport
  module Writers
    class SegmentWriter
      def upsert(track, extracted, window: nil)
        return nil if track.nil?

        points = track.points.order(:timestamp, :id).select(:id, :timestamp, :lonlat).to_a
        range = index_range(points, extracted, window)
        return nil if range.nil?

        keep = kept_segments(track, extracted.source_label)
        pieces = uncovered_pieces(points, range, keep)
        return nil if pieces.empty?

        existing = pieces.map { |piece| own_segment_at(track, extracted, points[piece.first]) }
        return [existing.first, false] if existing.all?

        [write_pieces(track, extracted, points, range, pieces, keep), true]
      rescue ActiveRecord::RecordNotUnique
        Rails.logger.warn(
          "event=enhanced_import.segment_write_conflict track_id=#{track.id} source=#{extracted.source_label}"
        )
        [own_segment_at(track, extracted, points[pieces.first.first]), false]
      end

      private

      def index_range(points, extracted, window)
        inside = points.each_index.select { |i| window.nil? || window.cover?(points[i].timestamp) }
        offsets = extracted.start_index..extracted.end_index
        inside = inside[offsets] || [] if offsets.size > 1
        inside.first..inside.last if inside.any?
      end

      def kept_segments(track, source_label)
        track.track_segments.outranking_inference.reject { |s| !s.manually_corrected? && s.source == source_label }
      end

      def uncovered_pieces(points, range, keep)
        timestamps = points.map(&:timestamp)
        covered = keep.flat_map { |segment| segment.covered_indices(timestamps) }.to_set

        range.reject { |i| covered.include?(i) }
             .slice_when { |a, b| b != a + 1 }
             .map { |run| run.first..run.last }
      end

      def own_segment_at(track, extracted, point)
        track.track_segments.find_by(start_at: Time.zone.at(point.timestamp), source: extracted.source_label)
      end

      def write_pieces(track, extracted, points, range, pieces, keep)
        TrackSegment.transaction do
          TrackSegments::RangeClearer.new(track, points, range, keep: keep).call
          pieces.map { |piece| create_piece(track, extracted, points, piece) }.first
        end
      end

      def create_piece(track, extracted, points, piece)
        segment = track.track_segments.new(
          start_at: Time.zone.at(points[piece.first].timestamp),
          end_at: Time.zone.at(points[piece.last].timestamp),
          transportation_mode: extracted.transportation_mode,
          confidence: confidence_level(extracted.confidence),
          source: extracted.source_label
        )
        TrackSegments::GeometryRecalculator.apply(segment, points)
      end

      STRING_CONFIDENCE = { 'high' => :high, 'medium' => :medium, 'low' => :low }.freeze

      def confidence_level(value)
        return :low if value.nil?

        mapped = STRING_CONFIDENCE[value.to_s.strip.downcase]
        return mapped if mapped

        numeric = value.to_f
        return :high if numeric >= 0.8 && numeric <= 1.0
        return :high if numeric >= 80
        return :medium if numeric >= 0.5 && numeric < 0.8
        return :medium if numeric >= 50

        :low
      end
    end
  end
end
