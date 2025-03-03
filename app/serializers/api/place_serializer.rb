# frozen_string_literal: true

class Api::PlaceSerializer
  def initialize(place)
    @place = place
  end

  def call
    {
      id: place.id,
      name: place.name,
      longitude: place.longitude,
      latitude: place.latitude,
      city: place.city,
      country: place.country,
      source: place.source,
      geodata: place.geodata,
      reverse_geocoded_at: place.reverse_geocoded_at
    }
  end

  private

  attr_reader :place
end
