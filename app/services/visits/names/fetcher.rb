# frozen_string_literal: true

module Visits
  module Names
    # Fetches names for places from reverse geocoding API
    class Fetcher
      def initialize(center)
        @center = center
      end

      def call
        return nil if geocoder_results.blank?

        build_place_name
      end

      private

      attr_reader :center

      def geocoder_results
        @geocoder_results ||= Geocoder.search(
          center, limit: 10, distance_sort: true, radius: 1, units: ::DISTANCE_UNIT
        )
      end

      def build_place_name
        return nil if geocoder_results.first&.data.blank?

        properties = geocoder_results.first.data['properties']
        return nil unless properties.present?

        # First try the direct properties approach
        name = Visits::Names::Builder.build_from_properties(properties)
        return name if name.present?

        # Fall back to the instance-based approach
        return nil unless properties['name'] && properties['osm_value']

        Visits::Names::Builder.new(
          features,
          properties['osm_value'],
          properties['name']
        ).call
      end

      def features
        geocoder_results.map do |result|
          {
            'properties' => result.data['properties']
          }
        end.compact
      end
    end
  end
end
