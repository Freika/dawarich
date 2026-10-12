# frozen_string_literal: true

module Visits
  module Names
    # Suggests names for places based on geodata from tracked points
    class Suggester
      STREETISH_OSM_KEYS = %w[highway place boundary landuse natural waterway railway].freeze
      # Geoapify has no osm_key; its result_type says how coarse the match is.
      STREETISH_RESULT_TYPES = %w[street postcode district suburb locality city county state country].freeze
      # Keys that may carry a feature's category, in provider precedence:
      # `type` for normalized Nominatim/LocationIQ data and for raw Photon
      # features (Photon's place rank), `osm_value` as a fallback, and
      # `result_type` for raw Geoapify features, which carry no `type`.
      FEATURE_TYPE_KEYS = %w[type osm_value result_type].freeze

      def initialize(points)
        @points = points
      end

      def call
        geocoded_points = extract_geocoded_points(points)
        return nil if geocoded_points.empty?

        features = extract_features(geocoded_points)
        return nil if features.empty?

        most_common_type = find_most_common_feature_type(features)
        return nil unless most_common_type

        most_common_name = find_most_common_name(features, most_common_type)
        return nil if most_common_name.blank?

        Visits::Names::Builder.new(
          features, most_common_type, most_common_name
        ).call
      end

      private

      attr_reader :points

      def extract_geocoded_points(points)
        points.select { |p| p.geodata.is_a?(Hash) && p.geodata.present? }
      end

      def extract_features(geocoded_points)
        geocoded_points.flat_map do |point|
          geodata = point.geodata

          if geodata['features'].is_a?(Array)
            geodata['features']
          elsif geodata['type'] == 'Feature' && geodata['properties'].is_a?(Hash)
            [geodata]
          else
            [normalized_feature(geodata)]
          end
        end.compact
      end

      def normalized_feature(geodata)
        properties = Geocoding::ResultNormalizer.from_data(geodata)[:properties]
        return nil if properties['name'].blank? || STREETISH_OSM_KEYS.include?(properties['osm_key'])

        { 'type' => 'Feature', 'properties' => properties }
      end

      def find_most_common_feature_type(features)
        feature_counts = features.group_by { |f| feature_type_for(f) }
                                 .transform_values(&:size)
        feature_counts.max_by { |_, count| count }&.first
      end

      def find_most_common_name(features, feature_type)
        common_features = features.select { |f| feature_type_for(f) == feature_type && !streetish_feature?(f) }
        name_counts = common_features.group_by { |f| f.dig('properties', 'name') }
                                     .transform_values(&:size)
        name_counts.max_by { |_, count| count }&.first
      end

      # Reads a feature's category from whichever provider key it carries;
      # a key that is present but blank falls through to the next one.
      def feature_type_for(feature)
        props = feature['properties'].is_a?(Hash) ? feature['properties'] : {}
        FEATURE_TYPE_KEYS.each { |key| return props[key] if props[key].present? }
        nil
      end

      # Raw provider features skip `normalized_feature`, so the street gate
      # is applied here before a street or district can win the name vote.
      def streetish_feature?(feature)
        props = feature['properties'].is_a?(Hash) ? feature['properties'] : {}
        STREETISH_OSM_KEYS.include?(props['osm_key']) || STREETISH_RESULT_TYPES.include?(props['result_type'])
      end
    end
  end
end
