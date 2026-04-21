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
      created_at: place.created_at,
      updated_at: place.updated_at,
      reverse_geocoded_at: place.reverse_geocoded_at,
      review_rating: place.review_rating,
      review_text: place.review_text,
      review_drafted_at: place.review_drafted_at,
      review_submitted_at: place.review_submitted_at,
      reviewed: place.reviewed?
    }
  end

  private

  attr_reader :place
end
