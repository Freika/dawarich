# frozen_string_literal: true

class Api::PlaceSerializer
  def initialize(place)
    @place = place
  end

  def call
    {
      id:         place.id,
      name:       place.name,
      longitude:  place.lon,
      latitude:   place.lat,
      city:       place.city,
      country:    place.country,
      source:     place.source,
      geodata:    place.geodata,
      reverse_geocoded_at: place.reverse_geocoded_at,
      created_at: place.created_at,
      updated_at: place.updated_at
    }
  end

  private

  attr_reader :place
end
