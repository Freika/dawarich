# frozen_string_literal: true

module Visits
  module Names
    # Suggests names for places based on geodata from tracked points
    class Suggester
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
        points.select { |p| p.geodata.present? && !p.geodata.empty? }
      end

      def extract_features(geocoded_points)
        geocoded_points.flat_map do |point|
          geodata = point.geodata

          if geodata['features'].is_a?(Array)
            geodata['features']
          elsif geodata['type'] == 'Feature' && geodata['properties'].is_a?(Hash)
            [geodata]
          elsif flat_geodata?(geodata)
            [pseudo_feature(geodata)]
          else
            []
          end
        end.compact
      end

      # Wraps Nominatim/LocationIQ flat geodata into the feature shape
      # the name voting below expects.
      def flat_geodata?(geodata)
        geodata['address'].is_a?(Hash) || geodata['display_name'].present? || geodata['lat'].present?
      end

      def pseudo_feature(geodata)
        address = geodata['address'] || {}

        {
          'type' => 'Feature',
          'properties' => {
            'type' => geodata['type'] || geodata['category'],
            'name' => geodata['name'].presence || [address['road'], address['house_number']].compact.join(' ').presence,
            'osm_key' => geodata['category'],
            'osm_value' => geodata['type'] || geodata['addresstype'],
            'street' => address['road'] || address['pedestrian'] || address['footway'],
            'housenumber' => address['house_number'],
            'city' => address['city'] || address['town'] || address['village'],
            'state' => address['state'],
            'country' => address['country'],
            'postcode' => address['postcode']
          }
        }
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
