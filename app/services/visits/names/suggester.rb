# frozen_string_literal: true

module Visits
  module Names
    # Suggests names for places based on geodata from tracked points
    class Suggester
      STREETISH_OSM_KEYS = %w[highway place boundary landuse natural waterway railway].freeze

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
        feature_counts = features.group_by { |f| f.dig('properties', 'type') }
                                 .transform_values(&:size)
        feature_counts.max_by { |_, count| count }&.first
      end

      def find_most_common_name(features, feature_type)
        common_features = features.select { |f| f.dig('properties', 'type') == feature_type }
        name_counts = common_features.group_by { |f| f.dig('properties', 'name') }
                                     .transform_values(&:size)
        name_counts.max_by { |_, count| count }&.first
      end
    end
  end
end
