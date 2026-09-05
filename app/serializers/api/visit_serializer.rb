# frozen_string_literal: true

class Api::VisitSerializer
  def initialize(visit, point_center: nil)
    @visit = visit
    @point_center = point_center
  end

  def call
    {
      id: visit.id,
      area_id: visit.area_id,
      user_id: visit.user_id,
      started_at: visit.started_at,
      ended_at: visit.ended_at,
      duration: visit.duration,
      name: visit.name,
      status: visit.status,
      confidence: visit.confidence,
      confidence_band: visit.confidence_band,
      place: {
        latitude: visit.place&.lat || visit.area&.latitude || point_center&.fetch(:lat),
        longitude: visit.place&.lon || visit.area&.longitude || point_center&.fetch(:lng),
        id: visit.place&.id
      }
    }
  end

  private

  attr_reader :visit, :point_center
end
