# frozen_string_literal: true

class Api::VisitSerializer
  def initialize(visit)
    @visit = visit
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
      place: {
        latitude: visit.place&.lat || visit.area&.latitude,
        longitude: visit.place&.lon || visit.area&.longitude,
        id: visit.place&.id
      }
    }
  end

  private

  attr_reader :visit
end
