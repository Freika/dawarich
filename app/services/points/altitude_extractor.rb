# frozen_string_literal: true

module Points
  # Extracts precise altitude from raw_data across all import source formats.
  # Used by the backfill job to recover fractional altitude lost by integer truncation.
  class AltitudeExtractor
    class << self
      def from_raw_data(raw_data)
        return nil unless raw_data.is_a?(Hash) && raw_data.present?

        extract_altitude(raw_data)
      end

      private

      def extract_altitude(data)
        # OwnTracks: 'alt'
        return data['alt'].to_f if data.key?('alt')

        # Overland/GeoJSON: properties.altitude or geometry.coordinates[2]
        if data.key?('properties')
          alt = data.dig('properties', 'altitude')
          return alt.to_f if alt.present?

          alt = data.dig('geometry', 'coordinates', 2)
          return alt.to_f if alt.present?
        end

        # Google Phone Takeout: altitudeMeters
        return data['altitudeMeters'].to_f if data.key?('altitudeMeters')

        # GPX (XML as hash): 'ele'
        return data['ele'].to_f if data.key?('ele')

        # Google Records: 'altitude'
        return data['altitude'].to_f if data.key?('altitude')

        nil
      end
    end
  end
end
