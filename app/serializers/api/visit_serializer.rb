# frozen_string_literal: true

class Api::VisitSerializer
  def initialize(visit)
    @visit = visit
  end

  def call
    {
      id: visit.id,
      area_id: visit.area_id || visit.place&.legacy_area_id,
      place_id: visit.place_id,
      user_id: visit.user_id,
      started_at: visit.started_at,
      ended_at: visit.ended_at,
      duration: visit.duration,
      name: visit.name,
      location_label: visit.location_label,
      display_name: visit.display_name,
      status: visit.status,
      confidence: visit.confidence,
      confidence_band: visit.confidence_band,
      place: serialize_place
    }
  end

  private

  attr_reader :visit

  def serialize_place
    return serialize_area if visit.place.nil?

    {
      id: visit.place.id,
      name: visit.place.name,
      latitude: visit.place.lat,
      longitude: visit.place.lon,
      visit_radius: visit.place.visit_radius
    }
  end

  def serialize_area
    return unless visit.area

    {
      id: nil,
      name: visit.area.name,
      latitude: visit.area.latitude.to_f,
      longitude: visit.area.longitude.to_f,
      visit_radius: visit.area.visit_radius
    }
  end
end
