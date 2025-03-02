# frozen_string_literal: true

class Api::VisitSerializer
  def initialize(visit)
    @visit = visit
  end

  def call
    {
      id: id,
      area_id: area_id,
      user_id: user_id,
      started_at: started_at,
      ended_at: ended_at,
      duration: duration,
      name: name,
      status: status,
      place: {
        latitude: visit.place&.latitude || visit.area&.latitude,
        longitude: visit.place&.longitude || visit.area&.longitude
      }
    }
  end

  private

  attr_reader :visit

  def id
    visit.id
  end

  def area_id
    visit.area_id
  end

  def user_id
    visit.user_id
  end

  def started_at
    visit.started_at
  end

  def ended_at
    visit.ended_at
  end

  def duration
    visit.duration
  end

  def name
    visit.name
  end

  def status
    visit.status
  end

  def place_id
    visit.place_id
  end
end
