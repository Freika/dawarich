# frozen_string_literal: true

module EnhancedImport
  module Writers
    class SegmentWriter
      def upsert(track, extracted)
        return nil if track.nil?

        existing = TrackSegment.find_by(track_id: track.id, start_index: extracted.start_index)
        return [existing, false] if existing

        segment = track.track_segments.create!(
          start_index: extracted.start_index,
          end_index: resolve_end_index(track, extracted),
          transportation_mode: extracted.transportation_mode,
          confidence: confidence_level(extracted.confidence),
          source: extracted.source_label
        )
        [segment, true]
      rescue ActiveRecord::RecordNotUnique
        existing = TrackSegment.find_by(track_id: track.id, start_index: extracted.start_index)
        [existing, false]
      end

      private

      # Google emits one activity per track without point offsets, so a source
      # segment arrives as 0..0 and must be stretched over the track it describes.
      def resolve_end_index(track, extracted)
        return extracted.end_index if extracted.end_index > extracted.start_index

        last_index = track.points.count - 1
        return extracted.end_index if last_index <= extracted.start_index

        last_index
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
