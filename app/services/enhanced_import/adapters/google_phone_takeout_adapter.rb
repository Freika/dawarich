# frozen_string_literal: true

module EnhancedImport
  module Adapters
    class GooglePhoneTakeoutAdapter < BaseAdapter
      SOURCE_LABEL = 'google_phone_takeout'

      # Timeline.json runs to hundreds of megabytes; the point importer streams it
      # for that reason and so does this, rather than materialising the whole
      # object graph in a Sidekiq worker.
      def translate(&block)
        return enum_for(:translate) unless block_given?

        profile = nil

        handler = GoogleMaps::PhoneTakeoutStreamHandler.new(
          on_entry: ->(section, value) { emit_segment(section, value, &block) },
          on_profile: ->(value) { profile = value }
        )

        stream_file { |io| Oj.saj_parse(handler, io) }

        Array(profile&.dig('frequentPlaces')).each do |place|
          extracted_place = build_frequent_place(place)
          yield extracted_place if extracted_place
        end
      end

      private

      def emit_segment(section, value)
        return unless section == :semantic_segment
        return unless value.is_a?(Hash)

        visit = build_visit(value)
        yield visit if visit

        track = build_track(value)
        yield track if track
      end

      include Imports::ActivityTypeMapping

      def build_track(segment)
        activity = segment['activity']
        return nil if activity.blank?

        candidate = activity['topCandidate']
        mode = candidate ? map_activity_type(candidate['type']) : nil
        return nil if mode.blank?

        started_at = parse_time(segment['startTime'])
        ended_at   = parse_time(segment['endTime'])
        return nil if started_at.nil? || ended_at.nil?

        Extracted::Track.new(
          tracker_id: "import-#{import.id}-activity-#{started_at.to_i}",
          start_at: started_at,
          end_at: ended_at,
          distance_m: activity['distanceMeters']&.to_i,
          transportation_mode: mode,
          confidence: candidate['probability'],
          source_label: SOURCE_LABEL,
          segments: [
            Extracted::TrackSegment.new(
              start_index: 0,
              end_index: 0,
              transportation_mode: mode,
              confidence: candidate['probability'],
              source_label: SOURCE_LABEL
            )
          ]
        )
      end

      def build_visit(segment)
        candidate = segment.dig('visit', 'topCandidate')
        return nil if candidate.blank?

        coords = parse_lat_lng(candidate.dig('placeLocation', 'latLng'))
        return nil if coords.nil?

        started_at = parse_time(segment['startTime'])
        ended_at   = parse_time(segment['endTime'])
        return nil if started_at.nil? || ended_at.nil?

        place = Extracted::Place.new(
          external_place_id: "google:#{candidate['placeId']}",
          name: humanize_semantic_type(candidate['semanticType']) || 'Unknown',
          latitude: coords[0],
          longitude: coords[1],
          semantic_type: candidate['semanticType']
        )

        Extracted::Visit.new(
          started_at: started_at,
          ended_at: ended_at,
          place: place,
          name: place.name,
          confidence: candidate['probability'],
          source_label: SOURCE_LABEL
        )
      end

      def parse_time(value)
        return nil if value.blank?

        Time.zone.parse(value)
      rescue ArgumentError
        nil
      end

      def humanize_semantic_type(type)
        return nil if type.blank?

        type.to_s.sub(/^TYPE_/, '').sub(/^INFERRED_/, '').tr('_', ' ').titleize
      end

      def build_frequent_place(place)
        return nil if place.blank?
        return nil if place['placeId'].blank?

        coords = parse_lat_lng(place['placeLocation']) || parse_e7_pair(place)
        return nil if coords.nil?

        Extracted::Place.new(
          external_place_id: "google:#{place['placeId']}",
          name: place['label'].presence || place['name'].presence || 'Frequent place',
          latitude: coords[0],
          longitude: coords[1],
          semantic_type: place['semanticType'] || 'FREQUENT_PLACE'
        )
      end

      def parse_e7_pair(place)
        latitude  = parse_e7(place['latitudeE7'])
        longitude = parse_e7(place['longitudeE7'])
        return nil if latitude.nil? || longitude.nil?

        [latitude, longitude]
      end
    end
  end
end
