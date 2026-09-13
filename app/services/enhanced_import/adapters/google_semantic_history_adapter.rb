# frozen_string_literal: true

module EnhancedImport
  module Adapters
    class GoogleSemanticHistoryAdapter < BaseAdapter
      SOURCE_LABEL = 'google_semantic_history'

      def translate
        return enum_for(:translate) unless block_given?

        json = load_json_data
        Array(json['timelineObjects']).each do |obj|
          if obj['placeVisit']
            visit = build_visit(obj['placeVisit'])
            yield visit if visit
          elsif obj['activitySegment']
            track = build_track(obj['activitySegment'])
            yield track if track
          end
        end
      end

      private

      include Imports::ActivityTypeMapping

      def build_track(activity)
        mode = map_activity_type(activity['activityType'])
        return nil if mode.blank?

        duration = activity['duration'] || {}
        started_at = duration_time(duration, 'start')
        ended_at   = duration_time(duration, 'end')
        return nil if started_at.nil? || ended_at.nil?

        Extracted::Track.new(
          tracker_id: "import-#{import.id}-activity-#{started_at.to_i}",
          start_at: started_at,
          end_at: ended_at,
          distance_m: activity['distance']&.to_i,
          transportation_mode: mode,
          confidence: activity['confidence'],
          source_label: SOURCE_LABEL,
          segments: [
            Extracted::TrackSegment.new(
              start_index: 0,
              end_index: 0,
              transportation_mode: mode,
              confidence: activity['confidence'],
              source_label: SOURCE_LABEL
            )
          ]
        )
      end

      def build_visit(place_visit)
        location = place_visit['location']
        return nil if location.blank?
        return nil if location['placeId'].blank?

        latitude  = parse_e7(location['latitudeE7'])
        longitude = parse_e7(location['longitudeE7'])
        return nil if latitude.nil? || longitude.nil?

        duration = place_visit['duration'] || {}
        started_at = duration_time(duration, 'start')
        ended_at   = duration_time(duration, 'end')
        return nil if started_at.nil? || ended_at.nil?

        place = Extracted::Place.new(
          external_place_id: "google:#{location['placeId']}",
          name: location['name'].presence || humanize_semantic_type(location['semanticType']) || 'Unknown',
          latitude: latitude,
          longitude: longitude,
          semantic_type: location['semanticType']
        )

        Extracted::Visit.new(
          started_at: started_at,
          ended_at: ended_at,
          place: place,
          name: place.name,
          confidence: place_visit['visitConfidence'],
          source_label: SOURCE_LABEL
        )
      end

      # Exports from before ~2022 carry epoch-ms strings under
      # startTimestampMs/endTimestampMs instead of ISO8601 timestamps.
      def duration_time(duration, prefix)
        parse_time(duration["#{prefix}Timestamp"]) || parse_epoch_ms(duration["#{prefix}TimestampMs"])
      end

      def parse_time(value)
        return nil if value.blank?

        Time.zone.parse(value)
      rescue ArgumentError
        nil
      end

      def parse_epoch_ms(value)
        return nil unless value.to_s.match?(/\A\d+\z/)

        Time.zone.at(value.to_i / 1000.0)
      end

      def humanize_semantic_type(type)
        return nil if type.blank?

        type.to_s.sub(/^TYPE_/, '').sub(/^INFERRED_/, '').tr('_', ' ').titleize
      end
    end
  end
end
