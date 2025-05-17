# frozen_string_literal: true

module Visits
  module Names
    # Builds descriptive names for places from geodata features
    class Builder
      def self.build_from_properties(properties)
        return nil if properties.blank?

        name_components = [
          properties['name'],
          properties['street'],
          properties['housenumber'],
          properties['city'],
          properties['state']
        ].compact.reject(&:empty?).uniq

        name_components.any? ? name_components.join(', ') : nil
      end

      def initialize(features, feature_type, name)
        @features = features
        @feature_type = feature_type
        @name = name
      end

      def call
        return nil if features.blank? || feature_type.blank? || name.blank?
        return nil unless feature

        [
          name,
          properties['street'],
          properties['city'],
          properties['state']
        ].compact.uniq.join(', ')
      end

      private

      attr_reader :features, :feature_type, :name

      def feature
        @feature ||= find_feature
      end

      def find_feature
        features.find do |f|
          f.dig('properties', 'type') == feature_type &&
            f.dig('properties', 'name') == name
        end || find_feature_by_osm_value
      end

      def find_feature_by_osm_value
        features.find do |f|
          f.dig('properties', 'osm_value') == feature_type &&
            f.dig('properties', 'name') == name
        end
      end

      def properties
        return {} unless feature && feature['properties'].is_a?(Hash)

        feature['properties']
      end
    end
  end
end
