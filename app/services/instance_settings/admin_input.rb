# frozen_string_literal: true

module InstanceSettings
  class AdminInput
    attr_reader :values, :errors

    def initialize(values)
      geocoding = GeocodingInput.new(values)
      map_matching = MapMatchingInput.new(geocoding.values)

      @values = map_matching.values
      @errors = geocoding.errors + map_matching.errors
    end

    def valid?
      errors.empty?
    end
  end
end
