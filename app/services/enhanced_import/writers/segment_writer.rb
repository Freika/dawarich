# frozen_string_literal: true

module EnhancedImport
  module Writers
    class SegmentWriter
      def upsert(track, extracted, window: nil)
        return nil if track.nil?

        points = track.points.order(:timestamp, :id).select(:id, :timestamp, :lonlat).to_a
        timestamps = points.map(&:timestamp)
        range = index_range(timestamps, extracted, window)
        return nil if range.nil?

        pieces = uncorrected_pieces(track, timestamps, range)
        return nil if pieces.empty?

        existing = pieces.map { |piece| TrackSegment.find_by(track_id: track.id, start_index: piece.first) }
        return [existing.first, false] if existing.all?

        [write_pieces(track, extracted, points, range, pieces), true]
      rescue ActiveRecord::RecordNotUnique
        [TrackSegment.find_by(track_id: track.id, start_index: pieces.first.first), false]
      end

      private

      # Google emits one activity per track without point offsets, so a source
      # segment arrives as 0..0 and must be stretched over the track it describes.
      def index_range(timestamps, extracted, window)
        offsets = extracted.start_index..extracted.end_index
        inside = timestamps.each_index.select do |i|
          offsets.size > 1 ? offsets.cover?(i) : window.nil? || window.cover?(timestamps[i])
        end
        inside.first..inside.last if inside.any?
      end

      def uncorrected_pieces(track, timestamps, range)
        corrected = track.track_segments.manually_corrected.flat_map { |s| covered_indices(s, timestamps) }.to_set

        range.reject { |i| corrected.include?(i) }
             .slice_when { |a, b| b != a + 1 }
             .map { |run| run.first..run.last }
      end

      def covered_indices(segment, timestamps)
        if segment.start_at && segment.end_at
          timestamps.each_index.select { |i| timestamps[i].between?(segment.start_at.to_i, segment.end_at.to_i) }
        elsif segment.start_index && segment.end_index
          (segment.start_index..segment.end_index).to_a
        else
          []
        end
      end

      def write_pieces(track, extracted, points, range, pieces)
        TrackSegment.transaction do
          TrackSegments::RangeClearer.new(track, points, range).call
          pieces.map { |piece| create_piece(track, extracted, piece) }.first
        end
      end

      def create_piece(track, extracted, piece)
        track.track_segments.create!(
          start_index: piece.first,
          end_index: piece.last,
          transportation_mode: extracted.transportation_mode,
          confidence: confidence_level(extracted.confidence),
          source: extracted.source_label
        )
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
