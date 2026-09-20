# frozen_string_literal: true

module EnhancedImport
  module Adapters
    class PolarstepsAdapter < BaseAdapter
      SOURCE_LABEL = 'polarsteps'

      def translate
        return enum_for(:translate) unless block_given?

        steps(load_json_data).each do |step|
          next unless step.is_a?(Hash)

          visit = build_visit(step)
          yield visit if visit
        end
      end

      private

      # Polarsteps exports either a {"locations": [...]} GPS trail, which carries
      # no visit metadata at all, or a bare array of steps with arrival and
      # departure times. Only the latter describes visits.
      def steps(json)
        return json if json.is_a?(Array)
        return Array(json['steps']) if json.is_a?(Hash) && json['steps'].is_a?(Array)

        []
      end

      def build_visit(step)
        location = step['location']
        location = step if location.blank? && step['lat']
        return nil if location.blank?

        latitude  = location['lat']&.to_f
        longitude = (location['lon'] || location['lng'])&.to_f
        return nil if latitude.nil? || longitude.nil?

        started_at = parse_unix(step['arrived'] || step['start_time'])
        ended_at   = parse_unix(step['departed'] || step['end_time'])
        return nil if started_at.nil? || ended_at.nil?

        place_name = step['display_name'].presence || step['name'].presence || location['detail'].presence || 'Unknown'

        place = Extracted::Place.new(
          external_place_id: "polarsteps:#{step['id']}",
          name: place_name,
          latitude: latitude,
          longitude: longitude,
          semantic_type: 'polarsteps_step'
        )

        Extracted::Visit.new(
          started_at: started_at,
          ended_at: ended_at,
          place: place,
          name: place_name,
          confidence: nil,
          source_label: SOURCE_LABEL
        )
      end

      def parse_unix(value)
        return nil if value.blank?

        Time.zone.at(value.to_i)
      end
    end
  end
end
