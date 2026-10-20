# frozen_string_literal: true

require 'tzf2'

module Timeline
  class TimezoneLookup
    def self.call(latitude, longitude)
      return if latitude.nil? || longitude.nil?

      TZF.tz_name(Float(latitude), Float(longitude))
    rescue TZF::UncoveredCoordinateError
      nil
    end
  end
end
