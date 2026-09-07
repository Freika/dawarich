# frozen_string_literal: true

module Visits
  module Names
    # Builds descriptive names for places from geodata features
    class Builder
      # Keys that may carry a feature's category, in provider precedence:
      # `type` for normalized Nominatim/LocationIQ data, `osm_value` for raw
      # Photon features, `result_type` for raw Geoapify features.
      FEATURE_TYPE_KEYS = %w[type osm_value result_type].freeze

      def self.build_from_properties(properties)
        return nil if properties.blank?

        name_components = [
          properties['name'],
          properties['street'],
          properties['housenumber'],
          properties['city'],
          properties['state']
        ].filter_map { |component| meaningful_component(component) }.uniq

        name_components.any? ? name_components.join(', ') : nil
      end

      def self.meaningful_component(component)
        normalized = component.to_s.strip
        return nil if normalized.blank? || %w[yes no].include?(normalized.downcase)

        normalized
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
          feature_type_for(f) == feature_type &&
            f.dig('properties', 'name') == name
        end
      end

      # Reads a feature's category from whichever provider key it carries
      # (see Visits::Names::Suggester#feature_type_for). Photon carries
      # `osm_value` and Geoapify carries `result_type`; normalized data
      # carries `type`.
      def feature_type_for(feature)
        props = feature['properties'].is_a?(Hash) ? feature['properties'] : {}
        FEATURE_TYPE_KEYS.each { |key| return props[key] if props.key?(key) }
        nil
      end

      def properties
        return {} unless feature && feature['properties'].is_a?(Hash)

        feature['properties']
      end
    end
  end
end
