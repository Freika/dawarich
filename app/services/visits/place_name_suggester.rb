# frozen_string_literal: true

module Visits
  # Suggests names for places based on geodata from tracked points
  class PlaceNameSuggester
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

      build_descriptive_name(features, most_common_type, most_common_name)
    end

    private

    attr_reader :points

    def extract_geocoded_points(points)
      points.select { |p| p.geodata.present? && !p.geodata.empty? }
    end

    def extract_features(geocoded_points)
      geocoded_points.flat_map do |point|
        next [] unless point.geodata['features'].is_a?(Array)

        point.geodata['features']
      end.compact
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

    def build_descriptive_name(features, feature_type, name)
      feature = features.find do |f|
        f.dig('properties', 'type') == feature_type &&
          f.dig('properties', 'name') == name
      end

      properties = feature['properties']
      [
        name,
        properties['street'],
        properties['city'],
        properties['state']
      ].compact.uniq.join(', ')
    end
  end
end
